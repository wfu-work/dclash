import 'dart:io';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ProfileService profiles;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'cloudrift_profiles_test_',
    );
    profiles = ProfileService(directory: directory);
    await profiles.initialize();
  });
  tearDown(() async {
    profiles.onClose();
    await directory.delete(recursive: true);
  });
  test(
    'duplicating preserves the override script in the committed copy',
    () async {
      final original = await profiles.saveContent(
        name: 'Original',
        content: 'proxies: []',
      );
      const script = 'function main(config) { return config; }';
      await profiles.update(original.copyWith(script: script));
      final duplicate = await profiles.duplicate(original.id);
      final reopened = ProfileService(directory: directory);
      await reopened.initialize();
      addTearDown(reopened.onClose);
      expect(
        reopened.profiles
            .firstWhere((value) => value.id == duplicate.id)
            .script,
        script,
      );
    },
  );
  test(
    'duplicating and reopening preserve per-profile shared script selection',
    () async {
      final original = await profiles.saveContent(
        name: 'Original',
        content: 'proxies: []',
      );
      await profiles.update(
        original.copyWith(sharedScriptIds: const ['second', 'first']),
      );
      final duplicate = await profiles.duplicate(original.id);
      final reopened = ProfileService(directory: directory);
      await reopened.initialize();
      addTearDown(reopened.onClose);
      expect(
        reopened.profiles
            .firstWhere((value) => value.id == original.id)
            .sharedScriptIds,
        ['second', 'first'],
      );
      expect(
        reopened.profiles
            .firstWhere((value) => value.id == duplicate.id)
            .sharedScriptIds,
        ['second', 'first'],
      );
    },
  );
  test('duplicating and reopening preserve standard extension rules', () async {
    final original = await profiles.saveContent(
      name: 'Original',
      content: 'rules: [MATCH,DIRECT]',
    );
    await profiles.update(
      original.copyWith(
        standardRules: const ['DOMAIN-SUFFIX,lan.example,DIRECT'],
        matchTarget: 'Proxy',
      ),
    );
    final duplicate = await profiles.duplicate(original.id);
    final reopened = ProfileService(directory: directory);
    await reopened.initialize();
    addTearDown(reopened.onClose);
    for (final id in [original.id, duplicate.id]) {
      final restored = reopened.profiles.firstWhere((value) => value.id == id);
      expect(restored.standardRules, ['DOMAIN-SUFFIX,lan.example,DIRECT']);
      expect(restored.matchTarget, 'Proxy');
    }
  });
  test(
    'private profile content and index use owner-only permissions',
    () async {
      if (Platform.isWindows) return;
      final profile = await profiles.saveContent(
        name: 'Private',
        content: 'proxies: []',
      );
      expect((await File(profile.path).stat()).mode & 0x1ff, 0x180);
      expect(
        (await File('${directory.path}/profiles/index.json').stat()).mode &
            0x1ff,
        0x180,
      );
    },
  );
  test(
    'authenticated redirects cannot forward credentials to another origin',
    () async {
      final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var targetRequests = 0;
      final targetSubscription = target.listen((request) async {
        targetRequests++;
        request.response.write('proxies: []');
        await request.response.close();
      });
      final sourceSubscription = source.listen((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${target.port}/profile',
        );
        await request.response.close();
      });
      try {
        await expectLater(
          profiles.importUrl(
            'http://user:password@127.0.0.1:${source.port}/profile',
          ),
          throwsException,
        );
        expect(targetRequests, 0);
        expect(profiles.profiles, isEmpty);
      } finally {
        await sourceSubscription.cancel();
        await targetSubscription.cancel();
        await source.close(force: true);
        await target.close(force: true);
      }
    },
  );
  test('invalid edit leaves the last valid persisted content intact', () async {
    final original = await profiles.saveContent(
      name: '../safe',
      content: 'proxies: []',
    );
    await profiles.activate(original.id);
    await expectLater(
      profiles.saveContent(
        id: original.id,
        name: 'edited',
        content: 'proxies: invalid',
      ),
      throwsException,
    );
    final reopened = ProfileService(directory: directory);
    await reopened.initialize();
    expect(reopened.activeId.value, original.id);
    expect(await reopened.readContent(reopened.active!), 'proxies: []');
    expect(reopened.active!.name.contains('/'), false);
  });
  test('failed index replacement keeps previous committed revision', () async {
    final original = await profiles.saveContent(
      name: 'first',
      content: 'proxies: []',
    );
    final index = File('${directory.path}/profiles/index.json');
    final bytes = await index.readAsBytes();
    await index.delete();
    await Directory(index.path).create();
    await expectLater(
      profiles.saveContent(
        id: original.id,
        name: 'changed',
        content: 'rules: []',
      ),
      throwsException,
    );
    expect(profiles.profiles.single.name, 'first');
    expect(await profiles.readContent(profiles.profiles.single), 'proxies: []');
    await Directory(index.path).delete();
    await index.writeAsBytes(bytes);
  });
  test(
    'removing active profile deterministically selects remaining profile',
    () async {
      final a = await profiles.saveContent(name: 'A', content: 'proxies: []');
      final b = await profiles.saveContent(name: 'B', content: 'proxies: []');
      await profiles.activate(a.id);
      await profiles.remove(a.id);
      expect(profiles.activeId.value, b.id);
    },
  );
  test(
    'same URL refreshes one record and failed refresh preserves content',
    () async {
      var valid = true;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.set(
          'subscription-userinfo',
          'upload=2; download=3; total=100; expire=1900000000',
        );
        request.response.write(valid ? 'proxies: []' : 'proxies: invalid');
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/subscription';
        final first = await profiles.importUrl(url);
        final second = await profiles.importUrl(url, name: 'Renamed');
        expect(first.id, second.id);
        expect(profiles.profiles.length, 1);
        expect(second.used, 5);
        valid = false;
        await expectLater(profiles.refresh(first.id), throwsException);
        expect(
          await profiles.readContent(profiles.profiles.single),
          'proxies: []',
        );
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
  test('restoring a malformed snapshot is all or nothing', () async {
    final first = await profiles.saveContent(
      name: 'Original',
      content: 'proxies: []',
    );
    final snapshot = await profiles.exportSnapshot();
    final entries = snapshot['profiles'] as List;
    (entries.single as Map)['content'] = 'proxies: bad';
    await expectLater(profiles.restoreSnapshot(snapshot), throwsException);
    expect(profiles.profiles.single.id, first.id);
    expect(await profiles.readContent(first), 'proxies: []');
  });
}
