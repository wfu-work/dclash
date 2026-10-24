import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../../../domains/network_health.dart';
import '../../../domains/network_health_report.dart';
import '../../../platform/network_health_host.dart';
import '../../../services/core_service.dart';
import '../../../services/health_history_service.dart';
import 'network_diagnostics_controller.dart';

class NetworkHealthController extends GetxController {
  NetworkHealthController(
    this.core, {
    NetworkHealthHost? host,
    this.history,
    this.hostTimeout = const Duration(seconds: 5),
  }) : host = host ?? IoNetworkHealthHost(),
       network = NetworkDiagnosticsController(core);

  final CoreService core;
  final NetworkHealthHost host;
  final Duration hostTimeout;
  final NetworkDiagnosticsController network;
  final HealthHistoryService? history;
  final running = false.obs;
  final results = <HealthCheck, HealthResult>{}.obs;
  final notice = RxnString();
  final error = RxnString();
  final finishedAt = Rxn<DateTime>();
  final historyError = RxnString();
  final _workers = <Worker>[];
  String testedUrl = '';
  int _generation = 0;
  bool _disposed = false;
  String _settings = '';

  String get defaultUrl {
    final value = '${core.settings.fields['testUrl'] ?? ''}';
    return NetworkDiagnosticsController.parseUrl(value) != null
        ? value
        : 'https://www.gstatic.com/generate_204';
  }

  int get completed => results.values
      .where((result) => result.status != HealthStatus.checking)
      .length;
  int get failures => results.values
      .where((result) => result.status == HealthStatus.failed)
      .length;
  int get warnings => results.values
      .where((result) => result.status == HealthStatus.warning)
      .length;

  String get summaryKey {
    if (core.preview) return 'healthPreview';
    if (running.value) return 'diagnosticRunning';
    if (results.isEmpty) return 'healthEmpty';
    return failures == 0 && warnings == 0 ? 'healthPassed' : 'healthAttention';
  }

  String? get routingAdvice {
    final direct = results[HealthCheck.direct]?.status;
    final routed = results[HealthCheck.routing]?.status;
    if (direct == HealthStatus.passed && routed == HealthStatus.failed) {
      return 'healthRoutingFailedAdvice';
    }
    if (routed == HealthStatus.passed) {
      if (results[HealthCheck.dns]?.status == HealthStatus.failed) {
        return 'healthRemoteDnsAdvice';
      }
      if (direct == HealthStatus.failed) return 'healthDirectFailedAdvice';
    }
    if (direct == HealthStatus.failed && routed == HealthStatus.failed) {
      return 'healthBothFailedAdvice';
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    network.onInit();
    network.compareEnabled.value = true;
    _settings = _settingsFingerprint();
    _workers.add(ever(network.contextRevision, (_) => _invalidate()));
    _workers.add(ever(network.urlResults, (_) => _acceptUrls()));
    _workers.add(
      ever(core.settings.fields, (_) {
        final next = _settingsFingerprint();
        if (next == _settings) return;
        _settings = next;
        network.invalidateContext();
      }),
    );
  }

  String _settingsFingerprint() => jsonEncode([
    for (final key in const [
      'mixedPort',
      'systemProxy',
      'tunEnabled',
      'ipv6',
      'dnsOverride',
      'tunOverride',
      'bypassDomains',
      'stack',
      'testUrl',
      'testTimeout',
    ])
      core.settings.fields[key],
  ]);

  void _invalidate() {
    if (running.value || results.isNotEmpty) {
      notice.value = 'diagnosticRouteChanged';
    }
    _generation++;
    running.value = false;
    results.clear();
    finishedAt.value = null;
    error.value = null;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _publish(int generation, HealthCheck check, HealthResult result) {
    if (_current(generation)) results[check] = result;
  }

  Future<void> run(String text) async {
    if (running.value || _disposed) return;
    final uri = NetworkDiagnosticsController.parseUrl(text);
    if (uri == null) {
      error.value = 'diagnosticInvalidUrl';
      return;
    }
    final generation = ++_generation;
    error.value = notice.value = null;
    historyError.value = null;
    finishedAt.value = null;
    testedUrl = uri.toString();
    results.clear();
    if (core.preview) {
      for (final check in HealthCheck.values) {
        results[check] = const HealthResult(
          HealthStatus.skipped,
          'healthPreview',
        );
      }
      return;
    }
    running.value = true;
    for (final check in HealthCheck.values) {
      results[check] = const HealthResult(
        HealthStatus.checking,
        'diagnosticRunning',
      );
    }
    results[HealthCheck.core] = core.running
        ? const HealthResult(HealthStatus.passed, 'healthCoreRunning')
        : HealthResult(
            HealthStatus.failed,
            'healthCoreStopped',
            details: core.error.value ?? '',
            action: core.profiles.active == null
                ? HealthAction.profiles
                : HealthAction.overview,
          );
    final port = core.settings.fields['mixedPort'] as int? ?? 7890;
    // Start route observation before host checks; a config or pick change
    // invalidates the entire run, including DNS / OS reads still in flight.
    await Future.wait([
      _checkRoutes(generation, testedUrl),
      _listener(generation, port),
      _systemProxy(generation, port),
      _dns(generation, uri.host.replaceAll(RegExp(r'^\[|\]$'), '')),
    ]);
    if (_current(generation)) {
      running.value = false;
      finishedAt.value = DateTime.now();
      unawaited(_saveHistory(generation));
    }
  }

  Future<void> _saveHistory(int generation) async {
    final service = history;
    final completedAt = finishedAt.value;
    if (service == null || completedAt == null || !_current(generation)) return;
    try {
      await service.add(
        HealthReportEntry.capture(
          checkedAt: completedAt,
          target: testedUrl,
          results: results,
          adviceKey: routingAdvice,
        ),
      );
    } on Object {
      if (_current(generation)) historyError.value = 'healthHistorySaveFailed';
    }
  }

  Future<void> _listener(int generation, int port) async {
    if (!core.running) {
      _publish(
        generation,
        HealthCheck.listener,
        const HealthResult(HealthStatus.skipped, 'diagnosticConnectFirst'),
      );
      return;
    }
    try {
      await host.checkListener(port).timeout(hostTimeout);
      _publish(
        generation,
        HealthCheck.listener,
        HealthResult(
          HealthStatus.passed,
          'healthListenerPassed',
          details: '127.0.0.1:$port',
        ),
      );
    } catch (failure) {
      _publish(
        generation,
        HealthCheck.listener,
        HealthResult(
          HealthStatus.failed,
          'healthListenerFailed',
          details: '127.0.0.1:$port\n${_message(failure)}',
          action: HealthAction.networkSettings,
        ),
      );
    }
  }

  Future<void> _systemProxy(int generation, int port) async {
    final tun = core.settings.fields['tunEnabled'] == true;
    final requested = core.settings.fields['systemProxy'] == true;
    HealthResult result;
    try {
      final snapshot = await host.systemProxy().timeout(hostTimeout);
      if (snapshot == null) {
        result = HealthResult(
          HealthStatus.warning,
          tun ? 'healthTunUnverified' : 'healthProxyUnsupported',
          action: HealthAction.networkSettings,
        );
      } else if (snapshot.matches(port) && core.running) {
        result = HealthResult(
          HealthStatus.passed,
          'healthProxyPassed',
          details: snapshot.details,
        );
      } else if ((requested && core.running) || snapshot.matches(port)) {
        result = HealthResult(
          HealthStatus.failed,
          core.running ? 'healthProxyMismatch' : 'healthProxyCoreStopped',
          details: snapshot.details,
          action: HealthAction.networkSettings,
        );
      } else {
        result = HealthResult(
          HealthStatus.warning,
          tun
              ? 'healthTunUnverified'
              : snapshot.enabled
              ? 'healthProxyOther'
              : 'healthProxyOff',
          details: snapshot.details,
          action: HealthAction.networkSettings,
        );
      }
    } catch (failure) {
      result = HealthResult(
        HealthStatus.warning,
        'healthProxyReadFailed',
        details: _message(failure),
        action: HealthAction.networkSettings,
      );
    }
    _publish(generation, HealthCheck.systemProxy, result);
  }

  Future<void> _dns(int generation, String domain) async {
    if (InternetAddress.tryParse(domain) != null) {
      _publish(
        generation,
        HealthCheck.dns,
        const HealthResult(HealthStatus.skipped, 'healthDnsIp'),
      );
      return;
    }
    final clock = Stopwatch()..start();
    try {
      final addresses = await host.lookup(domain).timeout(hostTimeout);
      if (addresses.isEmpty) throw StateError('healthDnsEmpty'.tr);
      _publish(
        generation,
        HealthCheck.dns,
        HealthResult(
          HealthStatus.passed,
          'healthDnsPassed',
          params: {'ms': '${clock.elapsedMilliseconds}'},
          details: '$domain\n${addresses.join(', ')}',
        ),
      );
    } catch (failure) {
      _publish(
        generation,
        HealthCheck.dns,
        HealthResult(
          HealthStatus.failed,
          'healthDnsFailed',
          details: '$domain\n${_message(failure)}',
          action: HealthAction.networkSettings,
        ),
      );
    }
  }

  void _acceptUrls() {
    if (_disposed || !running.value) return;
    for (final result in network.urlResults) {
      results[result.proxyName == 'DIRECT'
          ? HealthCheck.direct
          : HealthCheck.routing] = HealthResult(
        result.successful
            ? HealthStatus.passed
            : result.receivedResponse
            ? HealthStatus.warning
            : HealthStatus.failed,
        result.receivedResponse ? 'healthHttpResponse' : 'healthRequestFailed',
        params: {'code': '${result.statusCode}', 'ms': '${result.delay}'},
        details: [
          if (result.message.isNotEmpty) result.message,
          if (result.error.isNotEmpty && result.message.isEmpty) result.error,
          if (result.chains.isNotEmpty) result.chains.reversed.join(' → '),
          if (result.proxyName.isEmpty && result.rule.isNotEmpty)
            result.matchedRule,
        ].join('\n'),
        action: HealthAction.urlDiagnostics,
      );
    }
  }

  Future<void> _checkRoutes(int generation, String url) async {
    if (!core.running) {
      for (final check in [HealthCheck.direct, HealthCheck.routing]) {
        _publish(
          generation,
          check,
          const HealthResult(HealthStatus.skipped, 'diagnosticConnectFirst'),
        );
      }
      return;
    }
    final timeout = core.settings.fields['testTimeout'] as int? ?? 5000;
    network.timeout.value = timeout.clamp(1000, 30000);
    await network.diagnoseUrl(url);
    if (!_current(generation)) return;
    _acceptUrls();
    for (final check in [HealthCheck.direct, HealthCheck.routing]) {
      if (results[check]?.status == HealthStatus.checking) {
        results[check] = HealthResult(
          HealthStatus.failed,
          'healthRequestFailed',
          details: network.error.value ?? 'diagnosticInvalidResponse'.tr,
          action: HealthAction.urlDiagnostics,
        );
      }
    }
  }

  static String _message(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state):\s*'),
    '',
  );

  String get report => [
    'healthTitle'.tr,
    testedUrl,
    if (finishedAt.value != null) finishedAt.value!.toIso8601String(),
    for (final check in HealthCheck.values)
      if (results[check] case final result?) ...[
        '',
        '${'healthCheck_${check.name}'.tr} · ${'healthStatus_${result.status.name}'.tr}',
        result.message.trParams(result.params),
        if (result.details.isNotEmpty) result.details,
      ],
    if (routingAdvice case final advice?) ...['', advice.tr],
  ].join('\n');

  @override
  void onClose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    for (final worker in _workers) {
      worker.dispose();
    }
    network.onClose();
    super.onClose();
  }
}
