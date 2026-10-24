import 'dart:async';

import 'package:get/get.dart';

import '../../../domains/route_explanation.dart';
import '../../../services/core_service.dart';
import '../../../platform/core_rpc.dart';
import 'network_diagnostics_controller.dart';

class RouteExplanationController extends GetxController {
  RouteExplanationController(this.core);
  final CoreService core;
  final loading = false.obs;
  final result = Rxn<RouteExplanation>();
  final error = RxnString();
  final notice = RxnString();
  final _workers = <Worker>[];
  int _generation = 0;
  bool _disposed = false;

  String get defaultUrl {
    final value = '${core.settings.fields['testUrl'] ?? ''}';
    return NetworkDiagnosticsController.parseUrl(value) != null
        ? value
        : 'https://www.gstatic.com/generate_204';
  }

  @override
  void onInit() {
    super.onInit();
    _workers.add(ever(core.routeState, (_) => _invalidate()));
    _workers.add(
      everAll([core.status, core.groups, core.settings.fields], (_) {
        _invalidate();
      }),
    );
  }

  void _invalidate() {
    if (loading.value || result.value != null) {
      notice.value = 'routeExplainChanged';
    }
    _generation++;
    loading.value = false;
    result.value = null;
    error.value = null;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> explain(String text) async {
    if (loading.value || _disposed) return;
    final uri = NetworkDiagnosticsController.parseUrl(text);
    if (uri == null) {
      error.value = 'diagnosticInvalidUrl';
      return;
    }
    if (!core.running) {
      error.value = 'diagnosticConnectFirst';
      return;
    }
    final generation = ++_generation;
    error.value = notice.value = null;
    result.value = null;
    loading.value = true;
    try {
      await core.setRouteWatching(this, enabled: true);
      if (!_current(generation)) return;
      final response = await core.invoke('explainRoute', {
        'url': uri.toString(),
      });
      if (!_current(generation) || response is! Map) return;
      final explanation = RouteExplanation.fromMap(response);
      final route = core.routeState;
      if (route['core-epoch'] != explanation.stamp.coreEpoch ||
          route['picks-version'] != explanation.stamp.picksVersion) {
        notice.value = 'routeExplainChanged';
        return;
      }
      result.value = explanation;
    } on Object catch (failure) {
      if (_current(generation)) {
        error.value = failure is CoreException
            ? failure.message
            : failure.toString().replaceFirst(
                RegExp(r'^(Exception|StateError|Bad state):\s*'),
                '',
              );
      }
    } finally {
      if (_current(generation)) loading.value = false;
    }
  }

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
