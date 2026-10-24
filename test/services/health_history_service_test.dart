import 'dart:convert';

import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

HealthReportEntry report(
  int minute, {
  String id = 'report',
  String target = 'https://example.com/path?private=value#fragment',
  String details = 'Request https://user:secret@example.com/path?q=token#part',
}) => HealthReportEntry.capture(
  id: '$id-$minute',
  checkedAt: DateTime.utc(2026, 10, 23, 12, minute),
  target: target,
  results: {
    for (final check in HealthCheck.values)
      check: HealthResult(
        check == HealthCheck.routing
            ? HealthStatus.failed
            : HealthStatus.passed,
        'message-$minute',
        params: {'code': '$minute'},
        details: details,
        action: check == HealthCheck.routing
            ? HealthAction.urlDiagnostics
            : null,
      ),
  },
  adviceKey: 'healthRoutingFailedAdvice',
);

void main() {
  test(
    'recording opt-out and shorter retention take effect immediately',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      final history = HealthHistoryService(
        memoryOnly: true,
        settings: settings,
      );
      await history.initialize();
      addTearDown(history.onClose);
      final now = DateTime.now();
      HealthReportEntry entry(String id, int age) => HealthReportEntry.capture(
        id: id,
        checkedAt: now.subtract(Duration(days: age)),
        target: 'https://example.com',
        results: report(1).results,
      );
      await history.add(entry('recent', 1));
      await history.add(entry('older', 10));
      expect(history.entries, hasLength(2));
      await settings.set('recordHealthHistory', false);
      await history.add(entry('disabled', 0));
      expect(history.entries, hasLength(2));
      await settings.set('historyRetentionDays', 7);
      // remove queues behind the retention write, preserving the remaining record.
      await history.remove('missing');
      expect(history.entries.map((e) => e.id), ['recent']);
      await settings.set('recordHealthHistory', true);
      await history.add(entry('resumed', 0));
      expect(history.entries.map((e) => e.id), ['resumed', 'recent']);
      await history.clear();
      expect(history.entries, isEmpty);
    },
  );
  test(
    'capture strips target credentials, query, fragments and bounds details',
    () {
      final entry = report(1);
      expect(entry.target, 'https://example.com/path');
      expect(
        entry.results[HealthCheck.core]?.details,
        'Request https://example.com/path',
      );
      expect(entry.toMap()['target'], isNot(contains('private=value')));
      expect(entry.toMap()['checks'].toString(), isNot(contains('secret')));

      final long = HealthReportEntry.capture(
        id: 'long',
        checkedAt: DateTime.utc(2026),
        target: 'https://example.com',
        results: {
          HealthCheck.core: HealthResult(
            HealthStatus.failed,
            'x' * 2048,
            details: 'x' * 4096,
          ),
        },
      );
      expect(
        long.results[HealthCheck.core]!.message.length,
        lessThanOrEqualTo(HealthReportEntry.maxTargetLength),
      );
      expect(
        long.results[HealthCheck.core]!.details.length,
        lessThanOrEqualTo(HealthReportEntry.maxDetailLength),
      );
    },
  );

  test(
    'strictly validates serialized report enum values and all check records',
    () {
      final data = report(1).toMap();
      expect(
        HealthReportEntry.fromMap(data).target,
        'https://example.com/path',
      );

      final badStatus = Map<String, dynamic>.from(data)
        ..['checks'] = Map<String, dynamic>.from(data['checks'] as Map);
      (badStatus['checks'] as Map)['core'] = {
        ...(data['checks'] as Map)['core'] as Map,
        'status': 'invented',
      };
      expect(() => HealthReportEntry.fromMap(badStatus), throwsFormatException);

      final missing = Map<String, dynamic>.from(data)
        ..['checks'] = Map<String, dynamic>.from(data['checks'] as Map)
        ..['checks'].remove('dns');
      expect(() => HealthReportEntry.fromMap(missing), throwsFormatException);
    },
  );

  test(
    'history persists newest bounded reports and restores them in time order',
    () async {
      final preferences = _Preferences();
      final history = HealthHistoryService(
        preferences: preferences,
        maxEntries: 2,
      );
      await history.initialize();
      await history.add(report(1));
      await history.add(report(3));
      await history.add(report(2));

      expect(history.entries.map((entry) => entry.checkedAt.minute), [3, 2]);
      final persisted = jsonDecode(preferences.stored!) as List;
      expect(persisted, hasLength(2));
      expect(jsonEncode(persisted), isNot(contains('private=value')));

      final restored = HealthHistoryService(
        preferences: preferences,
        maxEntries: 2,
      );
      await restored.initialize();
      expect(restored.entries.map((entry) => entry.checkedAt.minute), [3, 2]);
      await restored.clear();
      expect(restored.entries, isEmpty);
    },
  );

  test(
    'malformed or duplicate stored records are skipped without blocking valid history',
    () async {
      final valid = report(4).toMap();
      final preferences = _Preferences()
        ..stored = jsonEncode([
          valid,
          valid,
          {'not': 'a report'},
          'not a map',
        ]);
      final history = HealthHistoryService(preferences: preferences);
      await history.initialize();
      expect(history.entries, hasLength(1));
      expect(history.entries.single.checkedAt.minute, 4);
    },
  );

  test(
    'failed write does not publish history and later writes recover',
    () async {
      final preferences = _Preferences()..failNext = true;
      final history = HealthHistoryService(preferences: preferences);
      await history.initialize();
      await expectLater(history.add(report(1)), throwsStateError);
      expect(history.entries, isEmpty);
      await history.add(report(2));
      expect(history.entries.single.checkedAt.minute, 2);
    },
  );
}
