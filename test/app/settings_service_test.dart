import 'dart:async';
import 'dart:convert';

import 'package:dclash_flutter/domains/script_library.dart';
import 'package:dclash_flutter/services/script_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences implements SharedPreferences {
  String? stored;
  bool failNext = false;
  Completer<void>? gate;
  int concurrent = 0;
  int peak = 0;

  @override
  String? getString(String key) => stored;

  @override
  Future<bool> setString(String key, String value) async {
    concurrent++;
    if (concurrent > peak) peak = concurrent;
    await gate?.future;
    concurrent--;
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
  test(
    'new preferences reject invalid values and equivalent shortcuts',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      for (final entry in <String, dynamic>{
        'historyRetentionDays': 0,
        'pollIntervalSeconds': 0,
        'backgroundIntervalSeconds': 1,
        'windowWidth': 100,
        'windowHeight': 9000,
        'autoCheckUpdates': 'true',
        'shortcutWindow': 'ctrl+ctrl+w',
        'shortcutConnection': 'alt+ctrl+w',
      }.entries) {
        await expectLater(
          settings.set(entry.key, entry.value),
          throwsFormatException,
        );
        expect(settings.fields[entry.key], SettingsService.defaults[entry.key]);
      }
    },
  );

  test(
    'window dimensions are persisted together or both stay unchanged',
    () async {
      final preferences = _Preferences();
      final settings = SettingsService(preferences: preferences);
      await settings.initialize();
      preferences.failNext = true;
      await expectLater(
        settings.setAll({'windowWidth': 1000, 'windowHeight': 700}),
        throwsStateError,
      );
      expect(settings.fields['windowWidth'], 1240);
      expect(settings.fields['windowHeight'], 850);
      await settings.setAll({'windowWidth': 1000, 'windowHeight': 700});
      expect(jsonDecode(preferences.stored!)['windowWidth'], 1000);
      expect(jsonDecode(preferences.stored!)['windowHeight'], 700);
    },
  );

  test('connections default to automatic startup', () async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    expect(settings.fields['autoStart'], true);
  });

  test('dashboard layout migration adds runtime resources only once', () async {
    final preferences = _Preferences()
      ..stored = jsonEncode(
        {
          ...SettingsService.defaults,
          'dashboardCards': ['status', 'currentOutbound', 'connections'],
        }..remove('dashboardLayoutVersion'),
      );
    final settings = SettingsService(preferences: preferences);
    await settings.initialize();
    expect(settings.fields['dashboardCards'], [
      'status',
      'currentOutbound',
      'runtimeResources',
      'connections',
    ]);
    await settings.set('dashboardCards', ['status']);
    final restored = SettingsService(preferences: preferences);
    await restored.initialize();
    expect(restored.fields['dashboardCards'], ['status']);

    await restored.restore({
      'dashboardCards': ['status', 'currentOutbound', 'connections'],
    });
    expect(restored.fields['dashboardCards'], [
      'status',
      'currentOutbound',
      'runtimeResources',
      'connections',
    ]);
  });

  test(
    'dashboard overview upgrades old defaults and preserves custom layouts',
    () async {
      const oldV1Default = [
        'status',
        'outboundMode',
        'currentProfile',
        'currentOutbound',
        'runtimeResources',
        'proxyGroups',
        'connections',
        'serviceStatus',
      ];
      const oldV2Default = [
        'status',
        'outboundMode',
        'runtimeResources',
        'currentProfile',
        'currentOutbound',
        'proxyGroups',
        'connections',
        'serviceStatus',
      ];
      for (final version in [null, 1]) {
        final preferences = _Preferences()
          ..stored = jsonEncode({
            'dashboardCards': oldV1Default,
            'dashboardLayoutVersion': ?version,
          });
        final settings = SettingsService(preferences: preferences);
        await settings.initialize();
        expect(
          settings.fields['dashboardCards'],
          SettingsService.defaults['dashboardCards'],
        );
        expect(settings.fields['dashboardLayoutVersion'], 3);
        await settings.set('ipv6', true);
        final restored = SettingsService(preferences: preferences);
        await restored.initialize();
        expect(
          restored.fields['dashboardCards'],
          SettingsService.defaults['dashboardCards'],
        );
      }
      final v2Preferences = _Preferences()
        ..stored = jsonEncode({
          'dashboardCards': oldV2Default,
          'dashboardLayoutVersion': 2,
        });
      final v2Settings = SettingsService(preferences: v2Preferences);
      await v2Settings.initialize();
      expect(
        v2Settings.fields['dashboardCards'],
        SettingsService.defaults['dashboardCards'],
      );
      expect(v2Settings.fields['dashboardLayoutVersion'], 3);

      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      for (final version in [1, 2, 3]) {
        for (final layout in [
          ['currentOutbound', 'status', 'currentProfile', 'connections'],
          ['connections', 'runtimeResources', 'status', 'proxyGroups'],
        ]) {
          await settings.restore({
            'dashboardLayoutVersion': version,
            'dashboardCards': layout,
          });
          expect(settings.fields['dashboardCards'], layout);
          expect(settings.fields['dashboardLayoutVersion'], 3);
          final exported = settings.export();
          await settings.restore(exported);
          expect(settings.fields['dashboardCards'], layout);
        }
      }
      await settings.restore({
        'dashboardLayoutVersion': 2,
        'dashboardCards': oldV1Default,
      });
      expect(settings.fields['dashboardCards'], oldV1Default);
      await settings.restore({
        'dashboardLayoutVersion': 3,
        'dashboardCards': oldV2Default,
      });
      expect(settings.fields['dashboardCards'], oldV2Default);
    },
  );

  test(
    'version three layouts are not rewritten during initialization',
    () async {
      const custom = [
        'recentEvents',
        'status',
        'healthSummary',
        'todayTraffic',
      ];
      final preferences = _Preferences()
        ..stored = jsonEncode({
          ...SettingsService.defaults,
          'dashboardLayoutVersion': 3,
          'dashboardCards': custom,
        });
      final settings = SettingsService(preferences: preferences);
      await settings.initialize();
      expect(settings.fields['dashboardCards'], custom);
      expect(settings.fields['dashboardLayoutVersion'], 3);
      final reopened = SettingsService(preferences: preferences);
      await reopened.initialize();
      expect(reopened.fields['dashboardCards'], custom);
      expect(reopened.fields['dashboardLayoutVersion'], 3);
    },
  );

  test('a pending restore wins over an older remote script refresh', () async {
    final preferences = _Preferences();
    final settings = SettingsService(preferences: preferences);
    await settings.initialize();
    final original = ScriptLibrary(
      scripts: [
        LibraryScript(
          id: 'remote',
          name: 'Remote',
          content: 'old',
          url: 'https://example.com/script.js',
        ),
      ],
    ).encode();
    final restored = ScriptLibrary(
      scripts: [
        LibraryScript(id: 'restored', name: 'Restored', content: 'backup'),
      ],
    ).encode();
    await settings.set('scripts', original);
    final download = Completer<String>();
    final service = ScriptLibraryService(
      settings,
      downloader: (_) => download.future,
    )..initialize();
    try {
      final refresh = service.refreshRemote('remote');
      final checkRefresh = expectLater(refresh, throwsStateError);
      preferences.gate = Completer<void>();
      final restore = settings.restore({'scripts': restored});
      await Future<void>.delayed(Duration.zero);
      download.complete('downloaded');
      await Future<void>.delayed(Duration.zero);
      expect(settings.fields['scripts'], original);
      preferences.gate!.complete();
      await restore;
      await checkRefresh;
      expect(settings.fields['scripts'], restored);
      expect(jsonDecode(preferences.stored!)['scripts'], restored);
      expect(service.scripts.single.id, 'restored');
    } finally {
      service.onClose();
    }
  });

  test(
    'queued writes publish only after persistence and preserve independent changes',
    () async {
      final preferences = _Preferences()..gate = Completer<void>();
      final settings = SettingsService(preferences: preferences);
      await settings.initialize();
      final first = settings.set('mixedPort', 8888);
      final second = settings.set('ipv6', true);
      await Future<void>.delayed(Duration.zero);
      expect(settings.fields['mixedPort'], 7890);
      expect(settings.fields['ipv6'], false);
      preferences.gate!.complete();
      await Future.wait([first, second]);
      expect(preferences.peak, 1);
      expect(settings.fields['mixedPort'], 8888);
      expect(settings.fields['ipv6'], true);
      expect((jsonDecode(preferences.stored!) as Map)['mixedPort'], 8888);
    },
  );

  test(
    'failed persistence leaves published state intact and later writes recover',
    () async {
      final preferences = _Preferences()..failNext = true;
      final settings = SettingsService(preferences: preferences);
      await settings.initialize();
      await expectLater(settings.set('mixedPort', 8888), throwsStateError);
      expect(settings.fields['mixedPort'], 7890);
      await settings.set('ipv6', true);
      expect(settings.fields['ipv6'], true);
      expect(settings.fields['mixedPort'], 7890);
    },
  );

  test('invalid imported settings are rejected atomically', () async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    for (final invalid in [
      {'mixedPort': 0},
      {'mixedPort': 19090},
      {'controllerPort': 65536},
      {'mode': 'invalid'},
      {'proxyLayout': 'masonry'},
      {'testTimeout': 0},
      {'testUrl': 'https://'},
      {'testUrl': 'https://user:password@example.com'},
      {
        'dashboardCards': ['status', 'status'],
      },
      {'dashboardCards': <String>[]},
      {
        'bypassDomains': [1],
      },
    ]) {
      await expectLater(settings.restore(invalid), throwsFormatException);
      expect(settings.fields['mixedPort'], 7890);
    }
    await settings.restore({'ipv6': true, 'unknownKey': 'ignored'});
    expect(settings.fields.containsKey('unknownKey'), false);
    expect(settings.fields['ipv6'], true);
  });

  test(
    'exports cannot mutate live lists and never contain secure credentials',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      await settings.writeSecret('webdavPassword', 'private-value');
      final backup = settings.export();
      (backup['bypassDomains'] as List).clear();
      expect((settings.fields['bypassDomains'] as List), isNotEmpty);
      expect(jsonEncode(backup), isNot(contains('private-value')));
      expect(await settings.readSecret('webdavPassword'), 'private-value');
    },
  );
}
