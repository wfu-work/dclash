import 'dart:convert';
import 'dart:io';

import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;
  late List<Map<String, dynamic>> sent;
  late CoreRpc rpc;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('dclash_rpc_');
    sent = [];
    rpc = CoreRpc(
      homeDirectory: home.path,
      timeout: const Duration(seconds: 1),
      setupConfigTimeout: const Duration(seconds: 2),
      send: (bytes) => sent.add(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
      ),
    );
  });
  tearDown(() async {
    await rpc.close();
    await home.delete(recursive: true);
  });
  List<int> response(Map<String, dynamic> data) =>
      utf8.encode(jsonEncode(data));

  test('correlates out of order replies and bounded event batches', () async {
    final first = rpc.invoke('first'), second = rpc.invoke('second');
    await rpc.receive(response({'id': sent[1]['id'], 'result': 2}));
    await rpc.receive(response({'id': sent[0]['id'], 'result': 1}));
    expect(await first, 1);
    expect(await second, 2);
    expect(rpc.pendingCount, 0);
    final events = <Map<String, dynamic>>[];
    final subscription = rpc.events.listen(events.add);
    await rpc.receive(
      response({
        'method': 'message',
        'arguments': List.generate(
          300,
          (_) => {'type': 'log', 'data': 'fixture'},
        ),
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(256));
    await subscription.cancel();
  });
  test('timeout removes pending request and ignores late reply', () async {
    await expectLater(rpc.invoke('slow'), throwsA(isA<CoreException>()));
    expect(rpc.pendingCount, 0);
    await rpc.receive(response({'id': sent.single['id'], 'result': 'late'}));
    expect(rpc.pendingCount, 0);
  });
  test('setupConfig uses the extended first-run timeout', () async {
    final request = rpc.invoke('setupConfig');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await rpc.receive(response({'id': sent.single['id'], 'result': 'ready'}));
    expect(await request, 'ready');
  });
  test(
    'serviceCheck allows the core budget for multiple requests and retries',
    () async {
      final request = rpc.invoke('serviceCheck', {
        'names': ['netflix'],
        'timeout': 5000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await rpc.receive(response({'id': sent.single['id'], 'result': []}));
      expect(await request, isEmpty);
      expect(rpc.pendingCount, 0);
    },
  );
  test('disconnect fails all correlated requests', () async {
    final request = rpc.invoke('pending');
    final expectation = expectLater(request, throwsA(isA<CoreException>()));
    await rpc.close();
    await expectation;
    expect(rpc.pendingCount, 0);
  });
  test('reads a correlated spill and removes it', () async {
    final request = rpc.invoke('large');
    final directory = await Directory(p.join(home.path, 'responses')).create();
    final file = File(p.join(directory.path, 'large.json'));
    await file.writeAsString(
      jsonEncode({
        'id': sent.single['id'],
        'result': {'text': 'large'},
      }),
    );
    await rpc.receive(response({'id': sent.single['id'], 'file': file.path}));
    expect(await request, {'text': 'large'});
    expect(await file.exists(), false);
  });
  test(
    'refuses spill outside response directory without deleting it',
    () async {
      final file = File(p.join(home.path, 'profile.yaml'));
      await file.writeAsString('private profile');
      final request = rpc.invoke('escape');
      final expectation = expectLater(request, throwsA(isA<CoreException>()));
      await rpc.receive(response({'id': sent.single['id'], 'file': file.path}));
      await expectation;
      expect(await file.readAsString(), 'private profile');
    },
  );
}
