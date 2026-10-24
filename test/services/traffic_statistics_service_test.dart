import 'dart:async';
import 'dart:convert';

import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/traffic_statistics.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/traffic_fixture.dart';

class _Preferences implements SharedPreferences {
  String? stored;
  bool failNext = false;
  Completer<void>? gate;
  int writes = 0;

  @override
  String? getString(String key) => stored;

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    await gate?.future;
    if (failNext) {
      failNext = false;
      return false;
    }
    stored = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoreService core;
  late TrafficStatisticsService statistics;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 10, 23, 12);
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = CoreService(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    statistics = TrafficStatisticsService(
      core,
      memoryOnly: true,
      clock: () => now,
    );
    await statistics.initialize();
    trafficBaseline(core);
  });

  tearDown(() async {
    statistics.onClose();
    await statistics.flush().catchError((Object _) {});
  });

  Future<void> usePreferences(
    _Preferences preferences, {
    int maxKeys = 500,
    int maxConnections = 10000,
  }) async {
    statistics.onClose();
    statistics = TrafficStatisticsService(
      core,
      preferences: preferences,
      clock: () => now,
      maxKeysPerDay: maxKeys,
      maxTrackedConnections: maxConnections,
    );
    await statistics.initialize();
    trafficBaseline(core);
  }

  test(
    'opt-out excludes disabled traffic and seeds active connection counters',
    () async {
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection()],
      );
      await core.settings.set('recordTraffic', false);
      trafficSample(
        core,
        upload: 1000,
        download: 2000,
        connections: [trafficConnection(upload: 1000, download: 2000)],
      );
      await core.settings.set('recordTraffic', true);
      trafficSample(
        core,
        upload: 1500,
        download: 2500,
        connections: [trafficConnection(upload: 1500, download: 2500)],
      );
      trafficSample(
        core,
        upload: 1510,
        download: 2520,
        connections: [trafficConnection(upload: 1510, download: 2520)],
      );
      expect(statistics.usage(TrafficPeriod.today).total, 330);
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.today)
            .single
            .usage
            .total,
        330,
      );
    },
  );

  test(
    'clearing active statistics keeps only new bytes, including previously unseen connections',
    () async {
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection()],
      );
      await statistics.clear();
      trafficSample(
        core,
        upload: 110,
        download: 220,
        connections: [
          trafficConnection(upload: 110, download: 220),
          trafficConnection(id: 'previously unseen'),
        ],
      );
      expect(statistics.usage(TrafficPeriod.today).total, 30);
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.today)
            .single
            .usage
            .total,
        30,
      );
    },
  );

  test(
    'ranks apps, normalized domains and leaf proxies without duplicate snapshots',
    () {
      final connection = trafficConnection();
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [connection],
      );
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [connection],
      );
      expect(statistics.usage(TrafficPeriod.today).total, 300);
      for (final dimension in TrafficDimension.values) {
        final rank = statistics.ranking(dimension, TrafficPeriod.today);
        expect(rank.single.usage.upload, 100);
        expect(rank.single.usage.download, 200);
      }
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
        'example.com',
      );
      expect(
        statistics
            .ranking(TrafficDimension.node, TrafficPeriod.today)
            .single
            .name,
        'Tokyo',
      );
    },
  );

  test(
    'closed requests retain final usage even after the visible request list is cleared',
    () {
      trafficSample(core, connections: [trafficConnection()]);
      core.requests.clear();
      trafficSample(
        core,
        counters: [const ConnectionTrafficCounter('one', 160, 450)],
      );
      trafficSample(
        core,
        counters: [const ConnectionTrafficCounter('one', 160, 450)],
      );
      // An older poll must not roll back either connection high-water mark.
      trafficSample(
        core,
        connections: [trafficConnection(upload: 120, download: 300)],
      );
      trafficSample(
        core,
        counters: [const ConnectionTrafficCounter('one', 170, 470)],
      );
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.today)
            .single
            .usage
            .total,
        640,
      );
    },
  );

  test(
    'daily totals include traffic whose connection details are unavailable',
    () {
      trafficSample(core, upload: 1000, download: 2000);
      expect(statistics.usage(TrafficPeriod.today).total, 3000);
      expect(
        statistics.ranking(TrafficDimension.application, TrafficPeriod.today),
        isEmpty,
      );
    },
  );

  test(
    'unidentified processes and empty routes use Unknown; DIRECT remains a route',
    () {
      trafficSample(
        core,
        connections: [
          trafficConnection(app: '', host: '', chains: []),
          trafficConnection(
            id: 'direct',
            chains: ['DIRECT'],
            app: r'C:\Apps\Browser.exe',
          ),
        ],
      );
      final nodes = statistics.ranking(
        TrafficDimension.node,
        TrafficPeriod.today,
      );
      expect(
        nodes.map((entry) => entry.name),
        containsAll(['DIRECT', TrafficStatisticsService.unknown]),
      );
      final apps = statistics.ranking(
        TrafficDimension.application,
        TrafficPeriod.today,
      );
      expect(
        apps.map((entry) => entry.name),
        containsAll(['Browser.exe', TrafficStatisticsService.unknown]),
      );
    },
  );

  test(
    'reconnect baselines exclude counters retained by an Android runtime',
    () {
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection()],
      );
      trafficBaseline(core, session: 2, upload: 100, download: 200);
      trafficSample(
        core,
        session: 2,
        upload: 130,
        download: 240,
        connections: [trafficConnection(upload: 30, download: 40)],
      );
      expect(statistics.usage(TrafficPeriod.today).total, 370);
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.today)
            .single
            .usage
            .total,
        370,
      );
    },
  );

  test('global counter resets affect each direction independently', () {
    trafficSample(core, upload: 100, download: 200);
    trafficSample(core, upload: 5, download: 220);
    expect(statistics.usage(TrafficPeriod.today).upload, 105);
    expect(statistics.usage(TrafficPeriod.today).download, 220);
    trafficSample(core, upload: -1, download: 0);
    trafficSample(core, upload: 10, download: 230);
    expect(statistics.usage(TrafficPeriod.today).total, 340);
  });

  test(
    'crossing midnight splits deltas by collection date and supports day filtering',
    () {
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection()],
      );
      now = DateTime(2026, 10, 24, 0, 0, 1);
      trafficSample(
        core,
        upload: 130,
        download: 240,
        connections: [trafficConnection(upload: 130, download: 240)],
      );
      expect(statistics.usage(TrafficPeriod.today).total, 70);
      expect(statistics.usage(TrafficPeriod.week).total, 370);
      expect(
        statistics
            .dailyUsage(TrafficPeriod.week)
            .map((entry) => entry.usage.total)
            .take(3),
        [70, 300, 0],
      );
      expect(
        statistics
            .ranking(
              TrafficDimension.domain,
              TrafficPeriod.week,
              date: DateTime(2026, 10, 23),
            )
            .single
            .usage
            .total,
        300,
      );
    },
  );

  test(
    'rankings aggregate days and sort independently by upload and download',
    () {
      trafficSample(
        core,
        connections: [
          trafficConnection(id: 'a', app: 'Upload', upload: 900, download: 100),
          trafficConnection(
            id: 'b',
            app: 'Download',
            upload: 200,
            download: 1200,
          ),
        ],
      );
      now = DateTime(2026, 10, 24);
      trafficSample(
        core,
        connections: [
          trafficConnection(id: 'c', app: 'Upload', upload: 100, download: 100),
        ],
      );
      final byUpload = statistics.ranking(
        TrafficDimension.application,
        TrafficPeriod.week,
        sort: TrafficSort.upload,
      );
      final byDownload = statistics.ranking(
        TrafficDimension.application,
        TrafficPeriod.week,
        sort: TrafficSort.download,
      );
      expect(byUpload.first.name, 'Upload');
      expect(byUpload.first.usage.total, 1200);
      expect(byDownload.first.name, 'Download');
    },
  );

  test(
    'persistence restores totals and rankings and bounds retained dates',
    () async {
      final preferences = _Preferences();
      await usePreferences(preferences);
      for (var day = 0; day < 35; day++) {
        now = DateTime(2026, 10, 23 + day);
        trafficSample(
          core,
          upload: (day + 1) * 100,
          download: (day + 1) * 200,
          connections: [trafficConnection(id: 'day-$day')],
        );
      }
      await statistics.flush();
      final saved = jsonDecode(preferences.stored!) as Map;
      expect((saved['days'] as Map), hasLength(30));
      statistics.onClose();
      statistics = TrafficStatisticsService(
        core,
        preferences: preferences,
        clock: () => now,
      );
      await statistics.initialize();
      expect(statistics.usage(TrafficPeriod.month).total, 9000);
      expect(
        statistics
            .ranking(TrafficDimension.application, TrafficPeriod.month)
            .single
            .usage
            .total,
        9000,
      );
      // Reopening while the runtime is active seeds, rather than recounting, it.
      trafficSample(
        core,
        upload: 3500,
        download: 7000,
        connections: [trafficConnection(id: 'day-34')],
      );
      expect(statistics.usage(TrafficPeriod.month).total, 9000);
    },
  );

  test(
    'corrupt days, invalid dates and incompatible schemas do not prevent loading',
    () async {
      final preferences = _Preferences();
      await usePreferences(preferences);
      trafficSample(
        core,
        upload: 10,
        download: 20,
        connections: [trafficConnection()],
      );
      await statistics.flush();
      final valid =
          (jsonDecode(preferences.stored!) as Map)['days']['2026-10-23'];
      for (final payload in [
        '{bad json',
        jsonEncode({
          'version': 999,
          'days': {'2026-10-23': valid},
        }),
        jsonEncode({
          'version': 1,
          'days': {
            '2026-10-23': valid,
            '2026-10-22': {
              'total': {'upload': -1, 'download': 5},
            },
            '2026-02-31': valid,
          },
        }),
      ]) {
        statistics.onClose();
        await statistics.flush();
        preferences.stored = payload;
        statistics = TrafficStatisticsService(
          core,
          preferences: preferences,
          clock: () => now,
        );
        await statistics.initialize();
      }
      expect(statistics.usage(TrafficPeriod.month).total, 30);
    },
  );

  test(
    'write failure preserves live counters and later saves recover',
    () async {
      final preferences = _Preferences()..failNext = true;
      await usePreferences(preferences);
      trafficSample(core, upload: 100, download: 200);
      await expectLater(statistics.flush(), throwsStateError);
      expect(statistics.saveError.value, isTrue);
      expect(statistics.usage(TrafficPeriod.today).total, 300);
      trafficSample(core, upload: 120, download: 250);
      await statistics.flush();
      expect(statistics.saveError.value, isFalse);
      expect(
        jsonDecode(
          preferences.stored!,
        )['days']['2026-10-23']['total']['download'],
        250,
      );
    },
  );

  test(
    'serialized writes retain updates received during an in-flight save',
    () async {
      final preferences = _Preferences()..gate = Completer<void>();
      await usePreferences(preferences);
      trafficSample(core, upload: 100, download: 200);
      final first = statistics.flush();
      await Future<void>.delayed(Duration.zero);
      trafficSample(core, upload: 120, download: 250);
      final second = statistics.flush();
      preferences.gate!.complete();
      await Future.wait([first, second]);
      expect(
        jsonDecode(
          preferences.stored!,
        )['days']['2026-10-23']['total']['download'],
        250,
      );
    },
  );

  test(
    'excess category names merge into Other without losing identified bytes',
    () async {
      await usePreferences(_Preferences(), maxKeys: 2);
      trafficSample(
        core,
        connections: [
          for (var i = 0; i < 10; i++)
            trafficConnection(id: '$i', host: '$i.example.com'),
        ],
      );
      final ranks = statistics.ranking(
        TrafficDimension.domain,
        TrafficPeriod.today,
      );
      expect(ranks.length, 3);
      expect(ranks.first.name, TrafficStatisticsService.other);
      expect(ranks.fold(0, (sum, entry) => sum + entry.usage.total), 3000);
    },
  );

  test(
    'evicted counters and older metadata never recount a connection lifetime',
    () async {
      await usePreferences(_Preferences(), maxConnections: 1);
      trafficSample(core, connections: [trafficConnection()]);
      trafficSample(
        core,
        connections: [
          trafficConnection(
            id: 'two',
            startedAt: now.add(const Duration(seconds: 1)),
          ),
        ],
      );
      trafficSample(
        core,
        counters: [const ConnectionTrafficCounter('one', 100, 200)],
      );
      trafficSample(core, connections: [trafficConnection()]);
      final rank = statistics
          .ranking(TrafficDimension.application, TrafficPeriod.today)
          .single;
      expect(rank.usage.total, 600);
    },
  );

  test('backgrounding flushes without changing system settings', () async {
    final preferences = _Preferences();
    await usePreferences(preferences);
    final before = Map.of(core.settings.fields);
    trafficSample(core, upload: 100, download: 200);
    statistics.didChangeAppLifecycleState(AppLifecycleState.paused);
    await statistics.flush();
    expect(preferences.writes, 1);
    expect(core.settings.fields, before);
  });

  test(
    'preview collection and updates after disposal do not write traffic',
    () async {
      statistics.onClose();
      core = CoreService(core.profiles, core.settings, preview: true);
      statistics = TrafficStatisticsService(
        core,
        memoryOnly: true,
        clock: () => now,
      );
      await statistics.initialize();
      trafficBaseline(core);
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection()],
      );
      statistics.onClose();
      trafficSample(core, upload: 200, download: 500);
      expect(statistics.usage(TrafficPeriod.today).total, 0);
      expect(
        statistics.ranking(TrafficDimension.domain, TrafficPeriod.today),
        isEmpty,
      );
    },
  );
}
