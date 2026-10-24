import 'dart:convert';

import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/node_quality_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
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

class _Core extends CoreService {
  _Core(super.profiles, super.settings);
  final calls = <String>[];
  @override
  Future<void> testAll() async {
    calls.add('all');
  }

  @override
  Future<int?> testDelay(String name) async {
    calls.add(name);
    delays[name] = 42;
    return 42;
  }
}

void main() {
  late _Core core;
  late NodeQualityService quality;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 10, 24, 12);
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = _Core(ProfileService(), settings)..status.value = CoreStatus.running;
    quality = NodeQualityService(core, memoryOnly: true, clock: () => now);
    await quality.initialize();
  });

  tearDown(() async {
    quality.onClose();
    await quality.flush().catchError((Object _) {});
  });

  test(
    'disabled and cleared quality samples do not reappear from the full delay map',
    () async {
      core.delays['Tokyo'] = 40;
      core.delays['Seoul'] = 50;
      await quality.clear();
      core.delays['Tokyo'] = 60;
      expect(quality.summaries(const Duration(days: 1)).single.name, 'Tokyo');
      await core.settings.set('recordNodeQuality', false);
      core.delays['Tokyo'] = 70;
      core.delays['Seoul'] = 80;
      await core.settings.set('recordNodeQuality', true);
      core.delays['Tokyo'] = 90;
      expect(
        quality
            .summaries(const Duration(days: 1))
            .single
            .samples
            .map((s) => s.delay),
        [60, 90],
      );
      now = now.add(const Duration(days: 8));
      await core.settings.set('historyRetentionDays', 7);
      expect(quality.summaries(const Duration(days: 90)), isEmpty);
    },
  );

  test(
    'records changed manual delay results, failures, average and jitter',
    () {
      core.delays['Tokyo'] = 40;
      core.delays['Tokyo'] = 40;
      now = now.add(const Duration(minutes: 1));
      core.delays['Tokyo'] = 60;
      now = now.add(const Duration(minutes: 1));
      core.delays['Tokyo'] = -1;
      final summary = quality.summaries(const Duration(days: 1)).single;
      expect(summary.samples.map((sample) => sample.delay), [40, 60, -1]);
      expect(summary.average, 50);
      expect(summary.jitter, 10);
      expect(summary.failureRate, closeTo(1 / 3, .001));
      expect(summary.unavailable, isTrue);
    },
  );

  test(
    'windowing, retention, bounds, persistence and corrupt nodes are safe',
    () async {
      final preferences = _Preferences();
      quality.onClose();
      quality = NodeQualityService(
        core,
        preferences: preferences,
        clock: () => now,
        maxSamplesPerNode: 2,
        maxNodes: 2,
      );
      await quality.initialize();
      for (var index = 0; index < 4; index++) {
        core.delays['Tokyo'] = 10 + index;
        now = now.add(const Duration(minutes: 1));
      }
      core.delays['Seoul'] = 30;
      core.delays['Singapore'] = 40;
      await quality.flush();
      expect(quality.summaries(const Duration(days: 1)), hasLength(2));
      final data = jsonDecode(preferences.stored!) as Map;
      expect((data['nodes'] as Map).length, 2);

      final restored = NodeQualityService(
        core,
        preferences: preferences,
        clock: () => now,
      );
      await restored.initialize();
      expect(restored.summaries(const Duration(days: 1)), hasLength(2));
      restored.onClose();

      preferences.stored = jsonEncode({
        'version': 1,
        'nodes': {
          'ok': [
            {'at': now.toIso8601String(), 'delay': 42},
          ],
          'bad': [
            {'at': 'invalid', 'delay': -2},
          ],
        },
      });
      final corrupted = NodeQualityService(
        core,
        preferences: preferences,
        clock: () => now,
      );
      await corrupted.initialize();
      expect(corrupted.summaries(const Duration(days: 1)).single.name, 'ok');
      corrupted.onClose();
    },
  );

  test(
    'manual tests do not run when stopped and running state is released',
    () async {
      core.status.value = CoreStatus.stopped;
      await quality.testAll();
      await quality.test('Tokyo');
      expect(core.calls, isEmpty);
      core.status.value = CoreStatus.running;
      await quality.testAll();
      await quality.test('Tokyo');
      expect(core.calls, ['all', 'Tokyo']);
      expect(quality.running.value, isFalse);
    },
  );

  test(
    'failed persistence does not discard collected quality samples',
    () async {
      final preferences = _Preferences()..failNext = true;
      quality.onClose();
      quality = NodeQualityService(
        core,
        preferences: preferences,
        clock: () => now,
      );
      await quality.initialize();
      core.delays['Tokyo'] = 42;
      await expectLater(quality.flush(), throwsStateError);
      expect(quality.summaries(const Duration(days: 1)).single.lastDelay, 42);
      await quality.flush();
      expect(preferences.stored, isNotNull);
    },
  );
}
