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
