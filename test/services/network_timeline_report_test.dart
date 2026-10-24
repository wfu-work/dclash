import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/domains/network_timeline.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/diagnostic_report_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/network_timeline_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/traffic_fixture.dart';

class _Preferences implements SharedPreferences {
  String? stored;
  bool failNext = false;

  @override
  String? getString(String key) => stored;

  @override
  Future<bool> setString(String key, String value) async {
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

HealthReportEntry _healthReport({
  String id = 'report',
  String details = 'Request https://user:secret@example.com/path?q=token#part',
}) => HealthReportEntry.capture(
  id: id,
  checkedAt: DateTime.utc(2026, 10, 24, 10),
  target: 'https://example.com/path?private=value#fragment',
  results: {
    for (final check in HealthCheck.values)
      check: HealthResult(
        check == HealthCheck.dns ? HealthStatus.failed : HealthStatus.passed,
        'healthCoreRunning',
        details: details,
      ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsService settings;
  late CoreService core;
  late HealthHistoryService health;
  late TrafficStatisticsService traffic;
  late NetworkTimelineService timeline;
  late DateTime now;

  setUp(() async {
    Get.testMode = true;
    now = DateTime.utc(2026, 10, 24, 12);
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = CoreService(ProfileService(), settings);
    health = HealthHistoryService(memoryOnly: true);
    await health.initialize();
    traffic = TrafficStatisticsService(
      core,
      memoryOnly: true,
      clock: () => now,
    );
    await traffic.initialize();
    timeline = NetworkTimelineService(
      core,
      settings,
      health,
      traffic,
      memoryOnly: true,
      clock: () => now,
    );
    await timeline.initialize();
  });

  tearDown(() async {
    timeline.onClose();
    traffic.onClose();
    await timeline.flush().catchError((Object _) {});
    await traffic.flush().catchError((Object _) {});
    Get.reset();
  });

  test(
    'records low-frequency state changes, diagnostics, and sanitized issues',
    () async {
      core.status.value = CoreStatus.starting;
      core.status.value = CoreStatus.running;
      core.routeState.assignAll({'core-epoch': 1, 'picks-version': 1});
      core.routeState.assignAll({'core-epoch': 1, 'picks-version': 2});
      await settings.set('mode', 'global');
      await settings.set('systemProxy', true);
      await settings.set('tunEnabled', true);
      core.error.value =
          'token=private 192.168.1.5 https://user:secret@example.com/x?q=1';
      core.logs.add(
        CoreLog(
          level: 'error',
          message: 'password=hidden /Users/alice/private.yaml',
          time: now,
        ),
      );
      await health.add(_healthReport());

      expect(
        timeline.entries.map((event) => event.titleKey),
        containsAll([
          'timelineCoreStatus',
          'timelineRouteChanged',
          'timelineModeChanged',
          'timelineSystemProxyChanged',
          'timelineTunChanged',
          'timelineCoreError',
          'timelineLogIssue',
          'timelineHealthAttention',
        ]),
      );
      final stored = jsonEncode(
        timeline.entries.map((event) => event.toMap()).toList(),
      );
      expect(stored, isNot(contains('private=value')));
      expect(stored, isNot(contains('secret')));
      expect(stored, isNot(contains('192.168.1.5')));
      expect(stored, isNot(contains('/Users/alice')));
    },
  );

  test(
    'persists valid timeline events in order and skips corrupt data',
    () async {
      final preferences = _Preferences();
      timeline.onClose();
      timeline = NetworkTimelineService(
        core,
        settings,
        health,
        traffic,
        preferences: preferences,
        clock: () => now,
        maxEntries: 2,
      );
      await timeline.initialize();
      timeline.add(
        kind: TimelineKind.core,
        severity: TimelineSeverity.info,
        titleKey: 'timelineCoreStatus',
        occurredAt: now.subtract(const Duration(minutes: 2)),
      );
      timeline.add(
        kind: TimelineKind.error,
        severity: TimelineSeverity.error,
        titleKey: 'timelineCoreError',
        occurredAt: now,
      );
      timeline.add(
        kind: TimelineKind.route,
        severity: TimelineSeverity.info,
        titleKey: 'timelineRouteChanged',
        occurredAt: now.subtract(const Duration(minutes: 1)),
      );
      await timeline.flush();
      expect(timeline.entries, hasLength(2));
      final persisted = jsonDecode(preferences.stored!) as List;
      expect(persisted, hasLength(2));

      final restored = NetworkTimelineService(
        core,
        settings,
        health,
        traffic,
        preferences: preferences,
        clock: () => now,
        maxEntries: 2,
      );
      await restored.initialize();
      expect(restored.entries.first.titleKey, 'timelineCoreError');
      restored.onClose();

      preferences.stored = jsonEncode([
        persisted.first,
        persisted.first,
        {'invalid': true},
        'not a map',
      ]);
      final malformed = NetworkTimelineService(
        core,
        settings,
        health,
        traffic,
        preferences: preferences,
        clock: () => now,
      );
      await malformed.initialize();
      expect(malformed.entries, hasLength(1));
      malformed.onClose();
    },
  );

  test('timeline retention and clear remain local and bounded', () async {
    timeline.add(
      kind: TimelineKind.core,
      severity: TimelineSeverity.info,
      titleKey: 'timelineCoreStatus',
      occurredAt: now.subtract(const Duration(days: 31)),
    );
    timeline.add(
      kind: TimelineKind.core,
      severity: TimelineSeverity.info,
      titleKey: 'timelineCoreStatus',
    );
    expect(timeline.entries, hasLength(1));
    await timeline.clear();
    expect(timeline.entries, isEmpty);
  });

  test(
    'disabled timeline does not replay old logs or reports when resumed',
    () async {
      await settings.set('recordTimeline', false);
      core.logs.add(
        CoreLog(level: 'error', message: 'disabled log', time: now),
      );
      await health.add(_healthReport(id: 'disabled-report'));
      core.status.value = CoreStatus.running;
      expect(timeline.entries, isEmpty);
      await settings.set('recordTimeline', true);
      core.logs.add(
        CoreLog(
          level: 'warning',
          message: 'new log',
          time: now.add(const Duration(seconds: 1)),
        ),
      );
      await health.add(_healthReport(id: 'new-report'));
      expect(timeline.entries, hasLength(2));
      expect(
        timeline.entries.where((e) => e.detail.contains('disabled')),
        isEmpty,
      );
      await timeline.clear();
      core.logs.refresh();
      health.entries.refresh();
      expect(timeline.entries, isEmpty);
    },
  );

  test(
    'report package is a sanitized text and JSON ZIP with no new core calls',
    () async {
      core.status.value = CoreStatus.failed;
      core.version.value =
          'mihomo https://user:secret@version.example/path?q=key';
      core.error.value =
          'Authorization: Bearer secret /home/user/config.yaml 10.0.0.5';
      trafficBaseline(core);
      trafficSample(core, upload: 100, download: 200);
      await health.add(_healthReport());
      core.logs.add(
        CoreLog(level: 'error', message: 'api_key=hidden', time: now),
      );
      final service = DiagnosticReportService(
        core,
        settings,
        health,
        traffic,
        timeline,
        clock: () => now,
      );
      final before = List.of(core.logs);
      final text = service.buildText();
      final archive = ZipDecoder().decodeBytes(service.buildArchive());
      final files = {
        for (final file in archive.files) file.name: utf8.decode(file.content),
      };
      expect(files.keys, {
        'dclash-diagnostic-report.txt',
        'dclash-diagnostic-report.json',
      });
      expect(files['dclash-diagnostic-report.txt'], text);
      for (final content in files.values) {
        expect(content, isNot(contains('secret')));
        expect(content, isNot(contains('hidden')));
        expect(content, isNot(contains('10.0.0.5')));
        expect(content, isNot(contains('/home/user')));
        expect(content, isNot(contains('q=key')));
      }
      expect(core.logs, before);
    },
  );
}
