import 'dart:async';

import 'package:dclash_flutter/app/pages/tools/network_health_controller.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';
import '../support/health_host.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

class _FailingHistory extends HealthHistoryService {
  _FailingHistory() : super(memoryOnly: true);

  @override
  Future<void> add(HealthReportEntry entry) async {
    throw StateError('history unavailable');
  }
}

void main() {
  late DiagnosticCore core;
  late FakeHealthHost host;
  late NetworkHealthController controller;

  setUp(() async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    host = FakeHealthHost();
    controller = NetworkHealthController(core, host: host)..onInit();
  });
  tearDown(() => controller.onClose());

  test('runs six checks and compares current routing with DIRECT', () async {
    await controller.run('https://example.com');
    expect(controller.results, hasLength(6));
    expect(controller.completed, 6);
    expect(controller.failures, 0);
    expect(controller.warnings, 0);
    expect(controller.summaryKey, 'healthPassed');
    expect(controller.finishedAt.value, isNotNull);
    expect(
      core.calls.where((c) => c.$1 == 'probe').map((c) => c.$2['proxy-name']),
      ['', 'DIRECT'],
    );
    expect(
      core.calls.every((c) => ['probe', 'watchRoute'].contains(c.$1)),
      isTrue,
    );
    expect(controller.report, contains('https://example.com'));
    expect(controller.report, contains('DomainSuffix,example.com'));
  });

  test(
    'saves a sanitized completed report without changing the result',
    () async {
      final history = HealthHistoryService(memoryOnly: true);
      controller.onClose();
      controller = NetworkHealthController(core, host: host, history: history)
        ..onInit();

      await controller.run('https://example.com/path?q=private#fragment');
      await flush();

      expect(controller.finishedAt.value, isNotNull);
      expect(controller.historyError.value, isNull);
      expect(history.entries, hasLength(1));
      expect(history.entries.single.target, 'https://example.com/path');
      expect(
        history.entries.single.toMap().toString(),
        isNot(contains('secret')),
      );
      expect(controller.results, hasLength(6));
    },
  );

  test(
    'history write failure is surfaced while the completed result remains',
    () async {
      final history = _FailingHistory();
      controller.onClose();
      controller = NetworkHealthController(core, host: host, history: history)
        ..onInit();

      await controller.run('https://example.com');
      await flush();

      expect(controller.finishedAt.value, isNotNull);
      expect(controller.results, hasLength(6));
      expect(controller.historyError.value, 'healthHistorySaveFailed');
    },
  );

  test(
    'DNS failure does not hide working routes or misdiagnose proxy',
    () async {
      host.dns = (_) async => throw StateError('resolver offline');
      await controller.run('https://example.com');
      expect(controller.results[HealthCheck.dns]?.status, HealthStatus.failed);
      expect(
        controller.results[HealthCheck.routing]?.status,
        HealthStatus.passed,
      );
      expect(controller.routingAdvice, 'healthRemoteDnsAdvice');
      expect(controller.completed, 6);
    },
  );

  test('transport failure on one route preserves the other route', () async {
    core.respond = (_, args) async {
      if (args['proxy-name'] == 'DIRECT') throw StateError('direct blocked');
      return core.probe(args);
    };
    await controller.run('https://example.com');
    expect(controller.results[HealthCheck.direct]?.status, HealthStatus.failed);
    expect(
      controller.results[HealthCheck.routing]?.status,
      HealthStatus.passed,
    );
    expect(controller.routingAdvice, 'healthDirectFailedAdvice');
    expect(
      controller.results[HealthCheck.direct]?.details,
      contains('direct blocked'),
    );
  });

  test(
    'HTTP restrictions are warnings, separate from transport failure',
    () async {
      core.respond = (_, args) async => {
        ...core.probe(args),
        'status-code': 403,
      };
      await controller.run('https://example.com');
      expect(
        controller.results[HealthCheck.routing]?.status,
        HealthStatus.warning,
      );
      expect(controller.results[HealthCheck.routing]?.params['code'], '403');
      expect(controller.failures, 0);
      expect(controller.warnings, 2);
    },
  );

  test('compares observed system proxy with requested local port', () async {
    core.settings.fields['systemProxy'] = true;
    host.proxy = () async => const SystemProxySnapshot(
      http: SystemProxyEndpoint(enabled: true, host: '127.0.0.1', port: 9999),
      https: SystemProxyEndpoint(enabled: false),
    );
    await controller.run('https://example.com');
    expect(
      controller.results[HealthCheck.systemProxy]?.message,
      'healthProxyMismatch',
    );
    expect(
      controller.results[HealthCheck.systemProxy]?.status,
      HealthStatus.failed,
    );
    expect(
      controller.results[HealthCheck.systemProxy]?.action,
      HealthAction.networkSettings,
    );
  });

  test(
    'TUN setting and unsupported OS inspection never prove capture',
    () async {
      core.settings.fields['tunEnabled'] = true;
      host.proxy = () async => null;
      await controller.run('https://example.com');
      expect(
        controller.results[HealthCheck.systemProxy]?.status,
        HealthStatus.warning,
      );
      expect(
        controller.results[HealthCheck.systemProxy]?.message,
        'healthTunUnverified',
      );
    },
  );

  test(
    'stopped core skips dependent checks and still inspects DNS and OS',
    () async {
      core.status.value = CoreStatus.failed;
      core.error.value = 'config unavailable';
      await controller.run('https://example.com');
      expect(controller.results[HealthCheck.core]?.status, HealthStatus.failed);
      expect(
        controller.results[HealthCheck.core]?.action,
        HealthAction.profiles,
      );
      expect(
        controller.results[HealthCheck.systemProxy]?.message,
        'healthProxyCoreStopped',
      );
      expect(controller.results[HealthCheck.dns]?.status, HealthStatus.passed);
      for (final check in [
        HealthCheck.listener,
        HealthCheck.direct,
        HealthCheck.routing,
      ]) {
        expect(controller.results[check]?.status, HealthStatus.skipped);
      }
      expect(core.calls, isEmpty);
      expect(host.calls, ['proxy', 'dns:example.com']);
    },
  );

  test('preview mode never invokes native core or host checks', () async {
    controller.onClose();
    core = DiagnosticCore(core.profiles, core.settings, preview: true)
      ..status.value = CoreStatus.running;
    controller = NetworkHealthController(core, host: host)..onInit();
    await controller.run('https://example.com');
    expect(host.calls, isEmpty);
    expect(core.calls, isEmpty);
    expect(controller.summaryKey, 'healthPreview');
    expect(
      controller.results.values.every((r) => r.status == HealthStatus.skipped),
      isTrue,
    );
  });

  test(
    'stopped core with a requested but disabled proxy reports actual state',
    () async {
      core.status.value = CoreStatus.stopped;
      core.settings.fields['systemProxy'] = true;
      host.proxy = () async => const SystemProxySnapshot(
        http: SystemProxyEndpoint(enabled: false),
        https: SystemProxyEndpoint(enabled: false),
      );
      await controller.run('https://example.com');
      expect(
        controller.results[HealthCheck.systemProxy]?.message,
        'healthProxyOff',
      );
      expect(
        controller.results[HealthCheck.systemProxy]?.status,
        HealthStatus.warning,
      );
    },
  );

  test('URL validation avoids I/O and numeric IPv4/IPv6 skip DNS', () async {
    await controller.run('not-a-url');
    expect(controller.error.value, 'diagnosticInvalidUrl');
    expect(host.calls, isEmpty);
    expect(core.calls, isEmpty);
    for (final url in ['http://127.0.0.1', 'http://[::1]']) {
      await controller.run(url);
      expect(controller.results[HealthCheck.dns]?.status, HealthStatus.skipped);
    }
    expect(host.calls.any((c) => c.startsWith('dns:')), isFalse);
  });

  test(
    'host checks time out independently without blocking completion',
    () async {
      controller.onClose();
      host.dns = (_) => Completer<List<String>>().future;
      host.listener = (_) async => throw StateError('connection refused');
      controller = NetworkHealthController(
        core,
        host: host,
        hostTimeout: const Duration(milliseconds: 10),
      )..onInit();
      await controller.run('https://example.com');
      expect(controller.results[HealthCheck.dns]?.status, HealthStatus.failed);
      expect(
        controller.results[HealthCheck.listener]?.status,
        HealthStatus.failed,
      );
      expect(
        controller.results[HealthCheck.routing]?.status,
        HealthStatus.passed,
      );
      expect(controller.completed, 6);
      expect(controller.running.value, isFalse);
    },
  );

  test(
    'route changes invalidate pending local checks and late results',
    () async {
      final pending = Completer<List<String>>();
      host.dns = (_) => pending.future;
      final first = controller.run('https://old.example.com');
      await flush();
      await controller.run('https://duplicate.example.com');
      expect(host.calls.where((c) => c.startsWith('dns:')), hasLength(1));
      core.nativeRoute['picks-version'] = 2;
      core.routeState.assignAll(core.nativeRoute);
      expect(controller.results, isEmpty);
      expect(controller.notice.value, 'diagnosticRouteChanged');
      host.dns = (_) async => ['203.0.113.2'];
      await controller.run('https://new.example.com');
      pending.complete(['203.0.113.99']);
      await first;
      expect(
        controller.results[HealthCheck.dns]?.details,
        contains('203.0.113.2'),
      );
      expect(controller.report, isNot(contains('old.example.com')));
    },
  );

  test(
    'network setting changes cancel native work before another run',
    () async {
      final pending = Completer<Map>();
      core.respond = (_, args) => pending.future;
      final first = controller.run('https://old.example.com');
      await flush();
      core.settings.fields['mixedPort'] = 8888;
      expect(controller.results, isEmpty);
      core.respond = (_, args) async => core.probe(args);
      await controller.run('https://new.example.com');
      pending.complete({
        ...core.probe({'url': 'https://old.example.com'}),
        'status-code': 500,
      });
      await first;
      expect(
        controller.results[HealthCheck.routing]?.status,
        HealthStatus.passed,
      );
      expect(
        controller.results[HealthCheck.listener]?.details,
        '127.0.0.1:8888',
      );
      core.settings.fields['themeMode'] = 'dark';
      expect(controller.results, hasLength(6));
    },
  );

  test(
    'disposal ignores late host replies and releases route watcher',
    () async {
      final pending = Completer<List<String>>();
      host.dns = (_) => pending.future;
      final run = controller.run('https://example.com');
      await flush();
      controller.onClose();
      final before = Map.of(controller.results);
      pending.complete(['203.0.113.88']);
      await run;
      expect(controller.results, before);
      expect(core.calls.last, ('watchRoute', false));
    },
  );
}
