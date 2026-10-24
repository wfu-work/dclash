import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../../domains/network_diagnostics.dart';
import '../../../platform/core_rpc.dart';
import '../../../services/core_service.dart';

class NetworkDiagnosticsController extends GetxController {
  NetworkDiagnosticsController(this.core);

  final CoreService core;
  final proxyName = ''.obs;
  final compareEnabled = false.obs;
  final comparisonProxyName = 'DIRECT'.obs;
  final timeout = 10000.obs;
  final probing = false.obs;
  final checkingServices = false.obs;
  final urlResults = <UrlDiagnosticResult>[].obs;
  final serviceResults = <String, ServiceDiagnosticResult>{}.obs;
  final pendingServices = <String>{}.obs;
  final error = RxnString();
  final notice = RxnString();
  final contextRevision = 0.obs;
  final _workers = <Worker>[];
  int _generation = 0;
  bool _disposed = false;
  String _context = '';
  DiagnosticStamp? _route;

  bool get busy => probing.value || checkingServices.value;

  List<String> get routes =>
      {
            '',
            'DIRECT',
            for (final group in core.groups) ...[
              group.name,
              ...group.nodes.map((node) => node.name),
            ],
          }
          .where(
            (name) => !const {'REJECT', 'REJECT-DROP', 'PASS'}.contains(name),
          )
          .toList();

  @override
  void onInit() {
    super.onInit();
    _context = _fingerprint();
    _workers.add(
      everAll(
        [
          core.status,
          core.groups,
          core.providers,
          core.settings.fields,
          core.profiles.activeId,
          core.profiles.profiles,
        ],
        (_) {
          final next = _fingerprint();
          if (next == _context) return;
          _context = next;
          _invalidate();
          if (!routes.contains(proxyName.value)) proxyName.value = '';
          _ensureComparisonRoute();
        },
      ),
    );
    _workers.add(ever(core.routeState, (_) => _acceptRoute()));
    _acceptRoute();
  }

  String _fingerprint() => jsonEncode([
    core.status.value.name,
    core.settings.fields['mode'],
    core.profiles.active?.toJson(),
    for (final group in core.groups)
      [
        group.name,
        group.selected,
        group.nodes.map((node) => [node.name, node.type]).toList(),
      ],
    core.providers,
  ]);

  void _acceptRoute() {
    if (core.routeState.isEmpty) {
      _route = null;
      return;
    }
    final next = DiagnosticStamp.fromMap(core.routeState);
    if (_route != null && _route != next) _invalidate();
    _route = next;
  }

  void _invalidate() {
    if (busy || urlResults.isNotEmpty || serviceResults.isNotEmpty) {
      notice.value = 'diagnosticRouteChanged';
    }
    _generation++;
    contextRevision.value++;
    probing.value = checkingServices.value = false;
    urlResults.clear();
    serviceResults.clear();
    pendingServices.clear();
    error.value = null;
  }

  void selectRoute(String value) {
    if (busy || proxyName.value == value) return;
    _invalidate();
    notice.value = null;
    proxyName.value = value;
    _ensureComparisonRoute();
  }

  void _ensureComparisonRoute() {
    if (!routes.contains(comparisonProxyName.value) ||
        comparisonProxyName.value == proxyName.value) {
      comparisonProxyName.value = proxyName.value.isEmpty ? 'DIRECT' : '';
    }
  }

  void selectComparisonRoute(String value) {
    if (busy || value == proxyName.value) return;
    comparisonProxyName.value = value;
    urlResults.clear();
  }

  static Uri? parseUrl(String text) {
    final input = text.trim();
    if (input.isEmpty || RegExp(r'\s').hasMatch(input)) return null;
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return null;
    }
    return uri;
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && core.running;

  void invalidateContext() => _invalidate();

  Future<bool> _prepare(int generation) async {
    if (!core.running) throw StateError('diagnosticConnectFirst'.tr);
    await core.setRouteWatching(this, enabled: true);
    if (_current(generation) && _route == null) {
      throw StateError('diagnosticInvalidResponse'.tr);
    }
    return _current(generation);
  }

  Future<bool> _acceptResult(int generation, DiagnosticStamp stamp) async {
    // Refresh the stamp before publishing: an automatic selection may have
    // changed since the last route event arrived at the host.
    if (!_current(generation)) return false;
    await core.setRouteWatching(this, enabled: true);
    if (!_current(generation)) return false;
    if (_route != stamp) {
      _invalidate();
      return false;
    }
    return true;
  }

  Future<void> diagnoseUrl(String text) async {
    if (busy || _disposed) return;
    final uri = parseUrl(text);
    error.value = notice.value = null;
    urlResults.clear();
    if (uri == null) {
      error.value = 'diagnosticInvalidUrl'.tr;
      return;
    }
    final generation = ++_generation;
    final selected = proxyName.value;
    final comparison = comparisonProxyName.value;
    final compare = compareEnabled.value && selected != comparison;
    probing.value = true;
    try {
      if (!await _prepare(generation)) return;
      final targets = [selected, if (compare) comparison];
      // Each request carries its own route. Neither probe changes group picks.
      await Future.wait(
        targets.map((route) async {
          final response = await core.invoke('probe', {
            'url': uri.toString(),
            'proxy-name': route,
            'timeout': timeout.value,
            'max-body': 0,
          });
          if (!_current(generation)) return;
          if (response == null) throw StateError('diagnosticBusy'.tr);
          final result = UrlDiagnosticResult(
            requestedUrl: uri.toString(),
            proxyName: route,
            data: response as Map,
          );
          if (await _acceptResult(generation, result.stamp)) {
            urlResults.add(result);
            urlResults.sort(
              (a, b) => targets
                  .indexOf(a.proxyName)
                  .compareTo(targets.indexOf(b.proxyName)),
            );
          }
        }),
      );
    } catch (failure) {
      if (_current(generation)) error.value = _message(failure);
    } finally {
      if (generation == _generation && !_disposed) probing.value = false;
    }
  }

  Future<void> checkServices([DiagnosticService? service]) async {
    if (busy || _disposed) return;
    final generation = ++_generation;
    final selected = proxyName.value;
    final targets = service == null ? DiagnosticService.all : [service];
    error.value = notice.value = null;
    if (service == null) serviceResults.clear();
    for (final item in targets) {
      serviceResults.remove(item.id);
    }
    pendingServices.addAll(targets.map((item) => item.id));
    checkingServices.value = true;
    try {
      if (!await _prepare(generation)) return;
      var next = 0;
      Future<void> worker() async {
        while (_current(generation) && next < targets.length) {
          final item = targets[next++];
          try {
            // One service per call gives incremental results and isolates
            // failures. Three workers keep the core's shared probe pool free.
            final response = await core.invoke('serviceCheck', {
              'proxy-name': selected,
              'names': [item.id],
              'timeout': timeout.value,
            });
            if (!_current(generation)) return;
            final items = response is List
                ? response
                : (response as Map)['items'] as List;
            final data = items.whereType<Map>().firstWhere(
              (data) => data['name'] == item.id,
            );
            final result = ServiceDiagnosticResult.fromMap(data);
            if (await _acceptResult(generation, result.stamp!)) {
              serviceResults[item.id] = result;
            }
          } catch (failure) {
            if (_current(generation)) {
              serviceResults[item.id] = ServiceDiagnosticResult.failure(
                failure is CoreException && failure.code == 'timeout'
                    ? 'timeout'
                    : 'failed',
                _message(failure),
              );
            }
          } finally {
            if (_current(generation)) pendingServices.remove(item.id);
          }
        }
      }

      await Future.wait(List.generate(3, (_) => worker()));
    } catch (failure) {
      if (_current(generation)) error.value = _message(failure);
    } finally {
      if (generation == _generation && !_disposed) {
        checkingServices.value = false;
        pendingServices.clear();
      }
    }
  }

  String _message(Object failure) => failure.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state):\s*'),
    '',
  );

  @override
  void onClose() {
    _disposed = true;
    _generation++;
    for (final worker in _workers) {
      worker.dispose();
    }
    unawaited(
      core.setRouteWatching(this, enabled: false).catchError((Object _) {}),
    );
    super.onClose();
  }
}
