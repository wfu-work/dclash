import 'dart:async';

import 'package:dclash_flutter/app/pages/tools/network_diagnostics_controller.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_diagnostics.dart';
import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late DiagnosticCore core;
  late NetworkDiagnosticsController controller;

  setUp(() async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    controller = NetworkDiagnosticsController(core)..onInit();
  });

  tearDown(() => controller.onClose());

  test('validates URLs before making any core requests', () async {
    for (final input in [
      '',
      'example.com',
      'ftp://example.com',
      'https://',
      'https://user:pass@example.com',
      'https://example.com/a b',
      'http://example.com:0',
      'http://example.com:65536',
      'http://example.com:abc',
    ]) {
      expect(
        NetworkDiagnosticsController.parseUrl(input),
        isNull,
        reason: input,
      );
      await controller.diagnoseUrl(input);
      expect(controller.error.value, isNotNull);
    }
    expect(core.calls, isEmpty);
    expect(
      NetworkDiagnosticsController.parseUrl(' https://example.com/a?q=1 '),
      Uri.parse('https://example.com/a?q=1'),
    );
    expect(
      NetworkDiagnosticsController.parseUrl('http://[::1]:8080'),
      isNotNull,
    );
  });

  test(
    'compares selected route and direct without changing proxy picks',
    () async {
      controller.selectRoute('Tokyo');
      controller.compareEnabled.value = true;
      controller.timeout.value = 5000;
      core.respond = (method, args) async => {
        ...core.probe(args),
        if (args['proxy-name'] == 'DIRECT') ...{
          'status-code': 0,
          'error': 'timeout',
          'message': 'deadline exceeded',
        },
      };
      await controller.diagnoseUrl('https://example.com');
      final requests = core.calls.where((call) => call.$1 == 'probe').toList();
      expect(requests.map((call) => (call.$2 as Map)['proxy-name']), [
        'Tokyo',
        'DIRECT',
      ]);
      expect(
        requests.every((call) => (call.$2 as Map)['timeout'] == 5000),
        isTrue,
      );
      expect(
        requests.every((call) => (call.$2 as Map)['max-body'] == 0),
        isTrue,
      );
      expect(core.calls.any((call) => call.$1 == 'changeProxy'), isFalse);
      expect(
        controller.urlResults.first.matchedRule,
        'DomainSuffix,example.com',
      );
      expect(controller.urlResults.first.successful, isTrue);
      expect(controller.urlResults.last.error, 'timeout');
      expect(controller.probing.value, isFalse);
    },
  );

  test(
    'HTTP error responses stay distinguishable from network failures',
    () async {
      core.respond = (_, args) async => {
        ...core.probe(args),
        'status-code': 403,
      };
      await controller.diagnoseUrl('https://example.com');
      expect(controller.urlResults.single.receivedResponse, isTrue);
      expect(controller.urlResults.single.successful, isFalse);
      expect(controller.urlResults.single.statusCode, 403);
      expect(controller.error.value, isNull);
    },
  );

  test(
    'compares current routing with a specified node and avoids duplicate routes',
    () async {
      controller.compareEnabled.value = true;
      controller.selectComparisonRoute('Tokyo');
      await controller.diagnoseUrl('https://example.com');
      expect(controller.urlResults.map((result) => result.proxyName), [
        '',
        'Tokyo',
      ]);
      controller.selectRoute('Tokyo');
      expect(controller.comparisonProxyName.value, '');
      await controller.diagnoseUrl('https://example.com');
      expect(controller.urlResults.map((result) => result.proxyName), [
        'Tokyo',
        '',
      ]);
    },
  );

  test(
    'appearance changes preserve results while routing mode changes invalidate them',
    () async {
      await controller.diagnoseUrl('https://example.com');
      await core.settings.set('themeMode', 'dark');
      expect(controller.urlResults, hasLength(1));
      await core.settings.set('mode', 'global');
      expect(controller.urlResults, isEmpty);
      expect(controller.notice.value, 'diagnosticRouteChanged');
    },
  );

  test('stopped core and duplicate clicks do not send probes', () async {
    core.status.value = CoreStatus.stopped;
    await controller.diagnoseUrl('https://example.com');
    expect(core.calls, isEmpty);
    expect(controller.probing.value, isFalse);
    core.status.value = CoreStatus.running;
    final reply = Completer<dynamic>();
    core.respond = (_, _) => reply.future;
    final running = controller.diagnoseUrl('https://example.com');
    await flush();
    await controller.diagnoseUrl('https://other.example');
    expect(core.calls.where((call) => call.$1 == 'probe'), hasLength(1));
    reply.complete(core.probe({'url': 'https://example.com'}));
    await running;
  });

  test(
    'route snapshot detects automatic changes before publishing a result',
    () async {
      core.respond = (_, args) async {
        final oldResult = core.probe(args);
        core.nativeRoute['picks-version'] = 2;
        return oldResult;
      };
      await controller.diagnoseUrl('https://example.com');
      expect(controller.urlResults, isEmpty);
      expect(controller.notice.value, 'diagnosticRouteChanged');
      expect(controller.busy, isFalse);
    },
  );

  test(
    'old request cannot replace results after a stop and new test',
    () async {
      final oldReply = Completer<dynamic>();
      core.respond = (_, _) => oldReply.future;
      final oldTest = controller.diagnoseUrl('https://old.example');
      await flush();
      core.status.value = CoreStatus.stopped;
      core.status.value = CoreStatus.running;
      core.respond = null;
      await controller.diagnoseUrl('https://new.example');
      oldReply.complete(core.probe({'url': 'https://old.example'}));
      await oldTest;
      expect(controller.urlResults.single.url, 'https://new.example');
    },
  );

  test(
    'checks all 13 services incrementally with three workers and isolated errors',
    () async {
      final gates = <String, Completer<dynamic>>{};
      var active = 0, peak = 0;
      core.respond = (_, args) async {
        final name = (args['names'] as List).single as String;
        active++;
        if (active > peak) peak = active;
        final gate = gates[name] = Completer<dynamic>();
        try {
          return await gate.future;
        } finally {
          active--;
        }
      };
      final sweep = controller.checkServices();
      await flush();
      expect(gates, hasLength(3));
      expect(controller.pendingServices, hasLength(13));
      gates['google']!.complete([core.service('google')]);
      await flush();
      expect(controller.serviceResults['google']?.region, 'JP');
      expect(controller.checkingServices.value, isTrue);
      expect(gates, hasLength(4));
      gates['github']!.completeError(
        const CoreException('timeout', 'Timed out'),
      );
      for (
        var round = 0;
        round < 20 && controller.checkingServices.value;
        round++
      ) {
        for (final entry in gates.entries.toList()) {
          if (!entry.value.isCompleted) {
            entry.value.complete([core.service(entry.key)]);
          }
        }
        await flush();
      }
      await sweep;
      expect(peak, 3);
      expect(
        gates.keys.toSet(),
        DiagnosticService.all.map((item) => item.id).toSet(),
      );
      expect(controller.serviceResults, hasLength(13));
      expect(controller.serviceResults['github']?.status, 'timeout');
      expect(controller.serviceResults['netflix']?.status, 'available');
      expect(controller.pendingServices, isEmpty);
    },
  );

  test(
    'single service refresh preserves other results and clears on route event',
    () async {
      await controller.checkServices();
      final google = controller.serviceResults['google'];
      await controller.checkServices(
        DiagnosticService.all.firstWhere((item) => item.id == 'netflix'),
      );
      expect(identical(controller.serviceResults['google'], google), isTrue);
      expect(
        (core.calls.lastWhere((call) => call.$1 == 'serviceCheck').$2
            as Map)['names'],
        ['netflix'],
      );
      core.routeState.assignAll({...core.nativeRoute, 'core-epoch': 2});
      expect(controller.serviceResults, isEmpty);
      expect(controller.notice.value, 'diagnosticRouteChanged');
    },
  );

  test(
    'native watch is shared across owners and ignores old route snapshots',
    () async {
      final other = Object();
      await core.setRouteWatching(controller, enabled: true);
      await core.setRouteWatching(other, enabled: true);
      await core.setRouteWatching(controller, enabled: false);
      expect(core.calls.last, ('watchRoute', true));
      core.nativeRoute['picks-version'] = 0;
      await core.setRouteWatching(other, enabled: true);
      expect(core.routeState['picks-version'], 1);
      await core.setRouteWatching(other, enabled: false);
      expect(core.calls.last, ('watchRoute', false));
    },
  );

  test(
    'closing a page releases its watch and ignores pending results',
    () async {
      final reply = Completer<dynamic>();
      core.respond = (_, _) => reply.future;
      final task = controller.diagnoseUrl('https://example.com');
      await flush();
      controller.onClose();
      reply.complete(core.probe({'url': 'https://example.com'}));
      await task;
      expect(controller.urlResults, isEmpty);
      expect(core.calls.last, ('watchRoute', false));
    },
  );
}
