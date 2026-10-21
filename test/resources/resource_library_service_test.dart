import 'dart:async';

import 'package:dclash_flutter/domains/resource_item.dart';
import 'package:dclash_flutter/services/resource_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SettingsService> settingsWith(String raw) async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    await settings.set('resources', raw);
    return settings;
  }

  test('loads, creates, toggles, orders and removes resources', () async {
    final settings = await settingsWith('');
    final service = ResourceLibraryService(settings);
    await service.initialize();
    final first = await service.save(
      name: 'Rules',
      kind: ResourceKind.ruleProvider,
      sourceType: ResourceSourceType.inline,
      source: 'rules: []',
    );
    final second = await service.save(
      name: 'Filter',
      kind: ResourceKind.regexFilter,
      sourceType: ResourceSourceType.inline,
      source: 'example\\.com',
    );
    expect(service.items.map((item) => item.id), contains(first.id));
    expect(service.byKind(ResourceKind.regexFilter), hasLength(1));
    await service.setEnabled(first.id, false);
    expect(
      service.items.firstWhere((item) => item.id == first.id).enabled,
      false,
    );
    await service.reorder(second.id, 0);
    expect(service.items.first.id, second.id);
    await service.remove(first.id);
    expect(service.items.map((item) => item.id), isNot(contains(first.id)));
  });

  test(
    'rejects same-kind names but accepts names from different kinds',
    () async {
      final service = ResourceLibraryService(await settingsWith(''));
      await service.initialize();
      await service.save(
        name: 'Shared',
        kind: ResourceKind.proxy,
        sourceType: ResourceSourceType.inline,
        source: 'proxies: []',
      );
      await service.save(
        name: 'Shared',
        kind: ResourceKind.iconSet,
        sourceType: ResourceSourceType.inline,
        source: '{}',
      );
      await expectLater(
        service.save(
          name: 'shared',
          kind: ResourceKind.proxy,
          sourceType: ResourceSourceType.inline,
          source: 'proxies: []',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'refreshes URL and file resources and retains old cache on failure',
    () async {
      final settings = await settingsWith('');
      final calls = <Uri>[];
      var fileBody = 'rules: [DOMAIN-SUFFIX,example.com,DIRECT]';
      final service = ResourceLibraryService(
        settings,
        downloader: (uri) async {
          calls.add(uri);
          return 'rules: [MATCH,DIRECT]';
        },
        fileReader: (_) async => fileBody,
      );
      await service.initialize();
      final remote = await service.save(
        name: 'Remote',
        kind: ResourceKind.ruleProvider,
        sourceType: ResourceSourceType.url,
        source: 'https://example.com/rules.yaml',
      );
      final local = await service.save(
        name: 'Local',
        kind: ResourceKind.ruleProvider,
        sourceType: ResourceSourceType.file,
        source: '/tmp/rules.yaml',
      );
      expect((await service.refresh(remote.id)).content, contains('MATCH'));
      expect(calls.single.host, 'example.com');
      expect(
        (await service.refresh(local.id)).content,
        contains('example.com'),
      );
      fileBody = '[';
      await expectLater(service.refresh(local.id), throwsFormatException);
      expect(
        service.items.firstWhere((item) => item.id == local.id).content,
        contains('example.com'),
      );
    },
  );

  test(
    'a concurrent settings restore prevents stale resource writes',
    () async {
      final settings = await settingsWith('');
      final gate = Completer<void>();
      final service = ResourceLibraryService(
        settings,
        downloader: (_) async {
          await gate.future;
          return 'rules: [MATCH,DIRECT]';
        },
      );
      await service.initialize();
      final item = await service.save(
        name: 'Remote',
        kind: ResourceKind.ruleProvider,
        sourceType: ResourceSourceType.url,
        source: 'https://example.com/rules.yaml',
      );
      final refresh = service.refresh(item.id);
      await Future<void>.delayed(Duration.zero);
      final restored = ResourceEnvelope(
        items: [
          ResourceItem(
            id: 'restored',
            name: 'Restored',
            kind: ResourceKind.ruleProvider,
            sourceType: ResourceSourceType.inline,
            source: 'rules: []',
            content: null,
            enabled: true,
            order: 0,
            createdAt: DateTime.utc(2026, 10, 21),
            updatedAt: DateTime.utc(2026, 10, 21),
          ),
        ],
      ).encode();
      final restore = settings.set('resources', restored);
      gate.complete();
      await expectLater(refresh, throwsStateError);
      await restore;
      expect(service.items.single.id, 'restored');
    },
  );
}
