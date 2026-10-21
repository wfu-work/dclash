import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dclash_flutter/services/backup_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/resource_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/domains/resource_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ProfileService profiles;
  late SettingsService settings;
  late BackupService backups;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cloudrift_backup_test_');
    profiles = ProfileService(directory: directory);
    await profiles.initialize();
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    backups = BackupService(profiles, settings);
  });
  tearDown(() async {
    profiles.onClose();
    await directory.delete(recursive: true);
  });
  test(
    'backup round trip preserves content without secure passwords',
    () async {
      final original = await profiles.saveContent(
        name: 'Original',
        content: 'proxies: []',
      );
      await settings.writeSecret('webdavPassword', 'do-not-back-up');
      final archive = await backups.exportArchive();
      final decoded = ZipDecoder().decodeBytes(archive).files.single.content;
      expect(utf8.decode(decoded).contains('do-not-back-up'), false);
      await profiles.remove(original.id);
      await backups.importArchive(archive);
      expect(profiles.activeId.value, original.id);
      expect(await profiles.readContent(profiles.active!), 'proxies: []');
    },
  );
  test('backup round trip preserves resource library data', () async {
    final resources = ResourceLibraryService(settings);
    await resources.initialize();
    final item = await resources.save(
      name: 'Inline rules',
      kind: ResourceKind.ruleProvider,
      sourceType: ResourceSourceType.inline,
      source: 'rules: [MATCH,DIRECT]',
      enabled: false,
    );
    final archive = await backups.exportArchive();
    await settings.set('resources', '');
    await backups.importArchive(archive);
    final restored = ResourceEnvelope.decode(
      settings.fields['resources'] as String,
    ).items.single;
    expect(restored.id, item.id);
    expect(restored.source, 'rules: [MATCH,DIRECT]');
    expect(restored.enabled, false);
    resources.onClose();
  });
  test(
    'rejects traversal entries before any settings or profiles change',
    () async {
      await profiles.saveContent(name: 'Original', content: 'proxies: []');
      final archive = Archive()
        ..add(ArchiveFile.string('../backup.json', '{}'));
      await expectLater(
        backups.importArchive(ZipEncoder().encode(archive)),
        throwsException,
      );
      expect(profiles.profiles.single.name, 'Original');
      expect(settings.fields['mode'], 'rule');
      expect(
        await File('${directory.parent.path}/backup.json').exists(),
        false,
      );
    },
  );
  test(
    'invalid settings and config are validated before applying anything',
    () async {
      final snapshot = await profiles.exportSnapshot();
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'backup.json',
            jsonEncode({
              'format': 'cloudrift',
              'version': 1,
              'settings': {'mixedPort': 0},
              'profiles': snapshot,
            }),
          ),
        );
      await expectLater(
        backups.importArchive(ZipEncoder().encode(archive)),
        throwsException,
      );
      expect(settings.fields['mixedPort'], 7890);
    },
  );
  test(
    'invalid resource envelope is rejected before applying settings',
    () async {
      final original = ResourceEnvelope(
        items: [
          ResourceItem(
            id: 'keep',
            name: 'Keep',
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
      await settings.set('resources', original);
      final snapshot = await profiles.exportSnapshot();
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'backup.json',
            jsonEncode({
              'format': 'cloudrift',
              'version': 1,
              'settings': {'resources': '{"version":2,"items":[]}'},
              'profiles': snapshot,
            }),
          ),
        );
      await expectLater(
        backups.importArchive(ZipEncoder().encode(archive)),
        throwsFormatException,
      );
      expect(settings.fields['resources'], original);
    },
  );
  test('profile commit failure rolls settings back', () async {
    await profiles.saveContent(name: 'Original', content: 'proxies: []');
    await settings.set('mode', 'global');
    final archive = await backups.exportArchive();
    await settings.set('mode', 'direct');
    final index = File('${directory.path}/profiles/index.json');
    await index.delete();
    await Directory(index.path).create();
    await expectLater(backups.importArchive(archive), throwsException);
    expect(settings.fields['mode'], 'direct');
    expect(profiles.profiles.single.name, 'Original');
  });
}
