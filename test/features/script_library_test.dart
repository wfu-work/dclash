import 'dart:convert';

import 'package:dclash_flutter/domains/script_library.dart';
import 'package:dclash_flutter/services/config_builder.dart';
import 'package:dclash_flutter/services/script_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

LibraryScript script(String id, {bool enabled = true, String? url}) =>
    LibraryScript(
      id: id,
      name: 'Name $id',
      content: id,
      enabled: enabled,
      url: url,
    );

void main() {
  test('library preserves order and unknown JSON data', () {
    final decoded = ScriptLibrary.decode(
      jsonEncode({
        'version': 1,
        'futureRoot': {'value': 1},
        'scripts': [
          {
            ...script('second').toJson(),
            'futureEntry': [1, 2],
          },
          script('first', enabled: false).toJson(),
        ],
      }),
    );
    final roundTrip = jsonDecode(decoded.encode());
    expect(decoded.scripts.map((item) => item.id), ['second', 'first']);
    expect(roundTrip['futureRoot'], {'value': 1});
    expect(roundTrip['scripts'][0]['futureEntry'], [1, 2]);
    expect(ScriptLibrary.decode('').scripts, isEmpty);
  });

  test('corrupt types, unknown versions and duplicate ids are rejected', () {
    for (final raw in [
      '{',
      '[]',
      '{"version":2,"scripts":[]}',
      '{"version":1,"scripts":"bad"}',
      jsonEncode({
        'version': 1,
        'scripts': [script('same').toJson(), script('same').toJson()],
      }),
      jsonEncode({
        'version': 1,
        'scripts': [
          {...script('bad').toJson(), 'enabled': 'true'},
        ],
      }),
      jsonEncode({
        'version': 1,
        'scripts': [
          {...script('bad').toJson(), 'url': 'http://example.com/a.js'},
        ],
      }),
    ]) {
      expect(() => ScriptLibrary.decode(raw), throwsFormatException);
    }
  });

  test('service preserves corrupt storage until explicit reset', () async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    await settings.set('scripts', '{broken');
    final service = ScriptLibraryService(settings)..initialize();
    try {
      expect(service.error.value, isNotNull);
      await expectLater(
        service.createLocal('New', 'function main(c) { return c; }'),
        throwsFormatException,
      );
      expect(settings.fields['scripts'], '{broken');
      await service.reset();
      expect(settings.fields['scripts'], '');
      expect(service.error.value, isNull);
    } finally {
      service.onClose();
    }
  });

  test(
    'new and imported scripts remain disabled; changed refresh disables',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      var downloaded = 'function main(c) { c.remote = 1; return c; }';
      final requests = <Uri>[];
      final service = ScriptLibraryService(
        settings,
        downloader: (url) async {
          requests.add(url);
          return downloaded;
        },
      )..initialize();
      try {
        await service.createLocal('Local', 'function main(c) { return c; }');
        await service.importRemote('Remote', 'https://example.com/script.js');
        expect(service.scripts.every((item) => !item.enabled), true);
        final remoteId = service.scripts.last.id;
        await service.setEnabled(remoteId, true);
        await service.refreshRemote(remoteId);
        expect(service.scripts.last.enabled, true);
        downloaded = 'function main(c) { c.remote = 2; return c; }';
        await service.refreshRemote(remoteId);
        expect(service.scripts.last.enabled, false);
        expect(service.scripts.last.content, downloaded);
        await service.move(remoteId, -1);
        expect(
          ScriptLibrary.decode(
            settings.fields['scripts'] as String,
          ).scripts.first.id,
          remoteId,
        );
        expect(requests.length, 3);
        await expectLater(
          service.importRemote('Bad', 'http://example.com/script.js'),
          throwsFormatException,
        );
        expect(requests.length, 3);
      } finally {
        service.onClose();
      }
    },
  );

  test('failed refresh retains current content and enabled state', () async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    await settings.set(
      'scripts',
      ScriptLibrary(
        scripts: [script('remote', url: 'https://example.com/script.js')],
      ).encode(),
    );
    final service = ScriptLibraryService(
      settings,
      downloader: (_) => Future.error(StateError('download failed')),
    )..initialize();
    try {
      final before = settings.fields['scripts'];
      await expectLater(service.refreshRemote('remote'), throwsStateError);
      expect(settings.fields['scripts'], before);
      expect(service.scripts.single.enabled, true);
    } finally {
      service.onClose();
    }
  });

  test(
    'editing preserves unknown fields and invalidates enabled code',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      await settings.set(
        'scripts',
        jsonEncode({
          'version': 1,
          'future': {'kept': true},
          'scripts': [
            {...script('local').toJson(), 'futureEntry': 7},
          ],
        }),
      );
      final service = ScriptLibraryService(settings)..initialize();
      try {
        await service.save('local', 'Renamed', 'changed');
        final stored = jsonDecode(settings.fields['scripts'] as String);
        expect(stored['future'], {'kept': true});
        expect(stored['scripts'][0]['futureEntry'], 7);
        expect(service.scripts.single.enabled, false);
        await settings.set('scripts', '');
        expect(service.scripts, isEmpty);
      } finally {
        service.onClose();
      }
    },
  );

  test(
    'build runs enabled shared scripts in order before profile script',
    () async {
      final selected = <String>[];
      final result = loadYaml(
        await ConfigBuilder.build(
          'custom: []',
          {
            'scripts': ScriptLibrary(
              scripts: [
                script('second'),
                script('skip', enabled: false),
                script('first'),
              ],
            ).encode(),
          },
          script: 'profile',
          scriptEvaluator: ({required script, required config}) async {
            selected.add(script);
            final decoded = jsonDecode(config) as Map<String, dynamic>;
            (decoded['custom'] as List).add(script);
            return jsonEncode(decoded);
          },
        ),
      );
      expect(selected, ['second', 'first', 'profile']);
      expect(result['custom'], ['second', 'first', 'profile']);
    },
  );

  test(
    'script failures identify the library name and halt later scripts',
    () async {
      final selected = <String>[];
      await expectLater(
        ConfigBuilder.build(
          'custom: []',
          {
            'scripts': ScriptLibrary(
              scripts: [script('failing'), script('later')],
            ).encode(),
          },
          scriptEvaluator: ({required script, required config}) async {
            selected.add(script);
            throw StateError('SyntaxError');
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Name failing'),
          ),
        ),
      );
      expect(selected, ['failing']);
    },
  );

  test(
    'invalid library fails a config build before any code executes',
    () async {
      var calls = 0;
      await expectLater(
        ConfigBuilder.build(
          'proxies: []',
          {'scripts': '{broken'},
          scriptEvaluator: ({required script, required config}) async {
            calls++;
            return config;
          },
        ),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
}
