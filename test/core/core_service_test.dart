import 'dart:async';
import 'dart:io';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/traffic_statistics.dart';
import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:dclash_flutter/platform/core_runtime.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class TestProfiles extends ProfileService {
  String content = 'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n';
  ClashProfile current = const ClashProfile(
    id: 'fixture',
    name: 'Test fixture',
    source: ProfileSource.custom,
    path: 'fixture.yaml',
  );
  @override
  ClashProfile? get active => current;
  @override
  Future<String> readContent(ClashProfile profile) async => content;
}

class TestRuntime implements CoreRuntime {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final calls = <String>[];
  Completer<void>? gate;
  Object? openError;
  Object? updateError;
  bool failClose = false;
  final modeUpdates = <String>[];
  final openedFields = <Map<String, dynamic>>[];
  Map<String, dynamic> memoryStats = {
    'rss': 32 * 1024 * 1024,
    'heapInuse': 8 * 1024 * 1024,
    'stackInuse': 1024 * 1024,
    'runtimeOther': 1024 * 1024,
  };
  String setupMessage = '';
  bool failTrafficBaseline = false;
  Map<String, dynamic> trafficTotals = {'up': 0, 'down': 0};
  Map<String, dynamic> connectionSnapshot = {'connections': []};
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  void cancelPendingStart() {
    calls.add('cancel');
  }

  @override
  Future<void> open(String home, Map<String, dynamic> fields) async {
    calls.add('open');
    openedFields.add(Map<String, dynamic>.from(fields));
    if (gate != null) await gate!.future;
    if (openError != null) throw openError!;
  }

  @override
  Future<void> start(Map<String, dynamic> fields) async {
    calls.add('start');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> close() async {
    calls.add('close');
    if (failClose) throw StateError('proxy cleanup failed');
    await controller.close();
  }

  @override
  Future<void> setSystemProxy(bool enabled, Map<String, dynamic> fields) async {
    calls.add('systemProxy');
  }

  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    calls.add(method);
    if (method == 'getTotalTraffic' && failTrafficBaseline) {
      failTrafficBaseline = false;
      throw StateError('statistics baseline unavailable');
    }
    if (method == 'updateConfig') {
      modeUpdates.add((arguments as Map)['mode'] as String);
      if (updateError != null) throw updateError!;
    }
    return switch (method) {
      'getProxies' => {'proxies': {}, 'all': []},
      'getExternalProviders' => [],
      'getConnections' => connectionSnapshot,
      'getTotalTraffic' => trafficTotals,
      'getMemoryStats' => memoryStats,
      'getVersion' => 'test-fixture',
      'watchRoute' => {'core-epoch': 1, 'picks-version': 1, 'picks': {}},
      'setupConfig' => setupMessage,
      _ => {},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SettingsService settings;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dclash_service_');
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('initialize and preview never create a native runtime', () async {
    var creations = 0;
    final service = CoreService(
      TestProfiles(),
      settings,
      runtimeFactory: () {
        creations++;
        return TestRuntime();
      },
    );
    await service.initialize();
    expect(creations, 0);
    expect(service.status.value, CoreStatus.stopped);
    await service.disposeRuntime();
    final preview = CoreService(
      TestProfiles(),
      settings,
      preview: true,
      runtimeFactory: () {
        creations++;
        return TestRuntime();
      },
    );
    await preview.initialize();
    expect(preview.version.value, contains('Preview'));
    expect(creations, 0);
    await expectLater(preview.start(), throwsA(isA<CoreException>()));
    await preview.disposeRuntime();
  });
  test(
    'route events invalidate snapshots and stopping clears route state',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      addTearDown(service.disposeRuntime);
      await service.start();
      await service.setRouteWatching(Object(), enabled: true);
      expect(service.routeState['picks-version'], 1);
      runtime.controller.add({
        'type': 'routeChanged',
        'data': {
          'core-epoch': 1,
          'picks-version': 2,
          'picks': {'Proxy': 'Seoul'},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.routeState['picks-version'], 2);
      expect(service.routeState['picks'], {'Proxy': 'Seoul'});
      runtime.controller.add({
        'type': 'routeChanged',
        'data': {'core-epoch': 1, 'picks-version': 1, 'picks': {}},
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.routeState['picks-version'], 2);
      await service.stop();
      expect(service.routeState, isEmpty);
    },
  );
  test(
    'statistics captures event totals independently of request history and takes a final snapshot on stop',
    () async {
      final runtime = TestRuntime()
        ..trafficTotals = {'up': 100, 'down': 200}
        ..connectionSnapshot = {
          'uploadTotal': 100,
          'downloadTotal': 200,
          'connections': [],
        };
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      final statistics = TrafficStatisticsService(service, memoryOnly: true);
      await statistics.initialize();
      addTearDown(() async {
        await service.disposeRuntime();
        statistics.onClose();
        await statistics.flush();
      });
      await service.initialize();
      await service.start();
      expect(statistics.usage(TrafficPeriod.today).total, 0);
      runtime.controller.add({
        'type': 'request',
        'data': {
          'id': 'short',
          'start': DateTime.now().toIso8601String(),
          'metadata': {
            'process': '',
            'processPath': '/Apps/Browser',
            'host': '',
            'destinationIP': '203.0.113.1',
          },
          'upload': 0,
          'download': 0,
          'chains': ['Tokyo', 'Proxy'],
        },
      });
      await Future<void>.delayed(Duration.zero);
      service.requests.clear();
      runtime.controller.add({
        'type': 'requestTraffic',
        'data': [
          {'id': 'short', 'upload': 200, 'download': 400},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.requests, isEmpty);
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.today)
            .single
            .name,
        'Browser',
      );
      expect(
        statistics
            .ranking(TrafficDimension.domain, TrafficPeriod.today)
            .single
            .name,
        '203.0.113.1',
      );
      expect(
        statistics
            .ranking(TrafficDimension.node, TrafficPeriod.today)
            .single
            .usage
            .total,
        600,
      );

      runtime.connectionSnapshot = {
        'uploadTotal': 300,
        'downloadTotal': 600,
        'connections': [],
      };
      await service.refreshRuntime();
      expect(statistics.usage(TrafficPeriod.today).total, 600);
      runtime.connectionSnapshot = {
        'uploadTotal': 350,
        'downloadTotal': 650,
        'connections': [],
      };
      await service.stop();
      expect(statistics.usage(TrafficPeriod.today).total, 700);
    },
  );
  test(
    'an unavailable statistics baseline does not prevent connecting',
    () async {
      final runtime = TestRuntime()..failTrafficBaseline = true;
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      addTearDown(service.disposeRuntime);
      await service.start();
      expect(service.status.value, CoreStatus.running);
      expect(service.error.value, isNull);
    },
  );
  test(
    'runtime polling prefers the core process RSS for memory usage',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      await service.start();
      expect(service.memory.value, 32 * 1024 * 1024);
      await service.disposeRuntime();
    },
  );
  test(
    'background refresh slows polling without recreating the runtime',
    () async {
      final runtime = TestRuntime();
      var creations = 0;
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () {
          creations++;
          return runtime;
        },
        supportDirectory: () async => directory,
      );
      await service.initialize();
      addTearDown(service.disposeRuntime);
      await service.start();
      final initialPolls = runtime.calls
          .where((call) => call == 'getMemoryStats')
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(
        runtime.calls.where((call) => call == 'getMemoryStats').length,
        greaterThan(initialPolls),
      );
      service.setForeground(false);
      final backgroundPolls = runtime.calls
          .where((call) => call == 'getMemoryStats')
          .length;
      expect(service.pollIntervalSeconds, 5);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(
        runtime.calls.where((call) => call == 'getMemoryStats').length,
        backgroundPolls,
      );
      await settings.set('reduceBackgroundRefresh', false);
      expect(service.pollIntervalSeconds, 1);
      await settings.set('pollIntervalSeconds', 2);
      expect(service.pollIntervalSeconds, 2);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(creations, 1);
      expect(runtime.calls.where((call) => call == 'open').length, 1);
      expect(service.running, isTrue);
    },
  );
  test('restart closes the previous runtime and opens a new one', () async {
    final runtimes = <TestRuntime>[];
    final service = CoreService(
      TestProfiles(),
      settings,
      runtimeFactory: () {
        final runtime = TestRuntime();
        runtimes.add(runtime);
        return runtime;
      },
      supportDirectory: () async => directory,
    );
    await service.initialize();
    addTearDown(service.disposeRuntime);
    await expectLater(service.restart(), throwsA(isA<CoreException>()));
    expect(runtimes, isEmpty);
    await service.start();
    await service.restart();
    expect(runtimes, hasLength(2));
    expect(
      runtimes.first.calls,
      containsAllInOrder(['start', 'stop', 'close']),
    );
    expect(runtimes.last.calls, containsAllInOrder(['open', 'start']));
    expect(service.running, isTrue);
  });
  test('restart does not open another runtime when cleanup fails', () async {
    final runtime = TestRuntime();
    var creations = 0;
    final service = CoreService(
      TestProfiles(),
      settings,
      runtimeFactory: () {
        creations++;
        return runtime;
      },
      supportDirectory: () async => directory,
    );
    await service.initialize();
    addTearDown(() async {
      runtime.failClose = false;
      await service.disposeRuntime();
    });
    await service.start();
    runtime.failClose = true;
    await expectLater(service.restart(), throwsStateError);
    expect(creations, 1);
    expect(service.status.value, CoreStatus.failed);
    expect(service.error.value, contains('cleanup failed'));
  });
  test(
    'runtime memory falls back to allocation statistics without RSS',
    () async {
      final runtime = TestRuntime()
        ..memoryStats = {
          'rss': 0,
          'heapInuse': 8 * 1024 * 1024,
          'stackInuse': 1024 * 1024,
          'runtimeOther': 1024 * 1024,
        };
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      await service.start();
      expect(service.memory.value, 10 * 1024 * 1024);
      await service.disposeRuntime();
    },
  );
  test(
    'superseded open does not start listeners and closes owned runtime',
    () async {
      final runtime = TestRuntime()..gate = Completer<void>();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      final start = service.start();
      while (!runtime.calls.contains('open')) {
        await Future<void>.delayed(Duration.zero);
      }
      final stop = service.stop();
      runtime.gate!.complete();
      await Future.wait([start, stop]);
      expect(runtime.calls, isNot(contains('start')));
      expect(runtime.calls, contains('close'));
      expect(service.status.value, CoreStatus.stopped);
      await service.disposeRuntime();
    },
  );
  test(
    'running event histories remain bounded and native failure is visible',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      await service.start();
      for (var i = 0; i < 1200; i++) {
        runtime.controller.add({
          'type': 'log',
          'data': {'Payload': 'fixture $i'},
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(service.logs.length, 1000);
      expect(service.logs.first.message, 'fixture 200');
      await service.disposeRuntime();
      final broken = TestRuntime()
        ..openError = const CoreException(
          'missing_core',
          'DClashCore is missing',
        );
      final failed = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => broken,
        supportDirectory: () async => directory,
      );
      await expectLater(failed.start(), throwsA(isA<CoreException>()));
      expect(failed.status.value, CoreStatus.failed);
      expect(failed.error.value, contains('missing'));
      await failed.disposeRuntime();
    },
  );
  test('mode RPC failure leaves the persisted mode unchanged', () async {
    final runtime = TestRuntime();
    final service = CoreService(
      TestProfiles(),
      settings,
      runtimeFactory: () => runtime,
      supportDirectory: () async => directory,
    );
    await service.initialize();
    await service.start();
    runtime.updateError = const CoreException(
      'update_failed',
      'Mode update failed',
    );
    await expectLater(service.setMode('global'), throwsA(isA<CoreException>()));
    expect(settings.fields['mode'], 'rule');
    await service.disposeRuntime();
  });
  test(
    'failed cleanup retains its runtime and disposal can be retried',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.start();
      runtime.failClose = true;
      await expectLater(service.disposeRuntime(), throwsStateError);
      expect(service.status.value, CoreStatus.failed);
      runtime.failClose = false;
      await service.disposeRuntime();
      expect(runtime.calls.where((call) => call == 'close'), hasLength(2));
      expect(service.status.value, CoreStatus.stopped);
    },
  );
  test(
    'mode changes during opening supersede the captured startup fields',
    () async {
      final opening = TestRuntime()..gate = Completer<void>();
      final replacement = TestRuntime();
      var creations = 0;
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => creations++ == 0 ? opening : replacement,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      final start = service.start();
      while (opening.openedFields.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final changed = service.setMode('direct');
      while (settings.fields['mode'] != 'direct') {
        await Future<void>.delayed(Duration.zero);
      }
      opening.gate!.complete();
      await Future.wait([start, changed]);
      expect(opening.openedFields.single['mode'], 'rule');
      expect(opening.calls, isNot(contains('start')));
      expect(replacement.openedFields.single['mode'], 'direct');
      expect(service.status.value, CoreStatus.running);
      await service.disposeRuntime();
    },
  );
  test(
    'a rejected profile apply preserves the last generated file and runtime',
    () async {
      final runtime = TestRuntime();
      final profiles = TestProfiles();
      final service = CoreService(
        profiles,
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.start();
      final file = File('${directory.path}/config.yaml');
      final previous = await file.readAsString();
      profiles.content =
          'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,missing\n';
      runtime.setupMessage = 'proxy missing';
      await expectLater(service.reload(), throwsA(isA<CoreException>()));
      expect(await file.readAsString(), previous);
      expect(service.status.value, CoreStatus.running);
      expect(runtime.calls.where((call) => call == 'open'), hasLength(1));
      await service.disposeRuntime();
    },
  );
  test(
    'stopped-core maintenance blocks starts and releases on failure',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      final gate = Completer<void>();
      final maintenance = service.withStoppedCore(() => gate.future);
      await expectLater(service.start(), throwsA(isA<CoreException>()));
      await expectLater(service.reload(), throwsA(isA<CoreException>()));
      await expectLater(service.toggle(), throwsA(isA<CoreException>()));
      expect(runtime.calls, isEmpty);
      gate.complete();
      await maintenance;
      await expectLater(
        service.withStoppedCore<void>(() async => throw StateError('restore')),
        throwsStateError,
      );
      await service.start();
      expect(service.status.value, CoreStatus.running);
      await expectLater(
        service.withStoppedCore<void>(() async {}),
        throwsA(isA<CoreException>()),
      );
      await service.disposeRuntime();
    },
  );
  test(
    'a native crash stays failed after the owned runtime is cleaned up',
    () async {
      final runtime = TestRuntime();
      final service = CoreService(
        TestProfiles(),
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.start();
      runtime.controller.add({'type': 'crash', 'data': 'Core process exited'});
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while ((!runtime.controller.isClosed ||
              service.status.value != CoreStatus.failed) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(runtime.controller.isClosed, isTrue);
      expect(service.status.value, CoreStatus.failed);
      expect(service.error.value, contains('Core process exited'));
      await service.disposeRuntime();
    },
  );
  test(
    'an active profile content revision reapplies without an id change',
    () async {
      final runtime = TestRuntime();
      final profiles = TestProfiles();
      final service = CoreService(
        profiles,
        settings,
        runtimeFactory: () => runtime,
        supportDirectory: () async => directory,
      );
      await service.initialize();
      await service.start();
      runtime.calls.clear();
      profiles.current = profiles.current.copyWith(
        updatedAt: DateTime(2026, 10, 19),
      );
      profiles.profiles.assignAll([profiles.current]);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (!runtime.calls.contains('setupConfig') &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(runtime.calls, contains('setupConfig'));
      expect(runtime.calls, isNot(contains('open')));
      await service.disposeRuntime();
    },
  );
}
