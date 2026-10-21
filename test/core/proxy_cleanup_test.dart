import 'dart:io';

import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:dclash_flutter/platform/core_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';

class _PartialProxy extends Proxy {
  int stops = 0;

  @override
  Future<bool> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async => false;

  @override
  Future<bool> stopProxy() async => ++stops > 1;
}

String _reply(List<String> arguments) => switch (arguments.first) {
  '-listallnetworkservices' =>
    'An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n',
  '-getwebproxy' =>
    'Enabled: Yes\nServer: proxy.before\nPort: 8080\nAuthenticated Proxy Enabled: 0\n',
  '-getsecurewebproxy' =>
    'Enabled: No\nServer: secure.before\nPort: 8443\nAuthenticated Proxy Enabled: 0\n',
  '-getsocksfirewallproxy' =>
    'Enabled: No\nServer: \nPort: 0\nAuthenticated Proxy Enabled: 0\n',
  '-getproxybypassdomains' => 'example.org\n*.internal\n',
  _ => '',
};

void main() {
  test(
    'partial proxy activation retains cleanup ownership for retry',
    () async {
      final proxy = _PartialProxy();
      final runtime = DesktopCoreRuntime(proxy: proxy);
      await expectLater(
        runtime.setSystemProxy(true, {'mixedPort': 7890}),
        throwsA(isA<CoreException>()),
      );
      expect(proxy.stops, 1);
      await runtime.close();
      expect(proxy.stops, 2);
    },
  );

  test(
    'macOS partial activation restores the original proxy and bypass',
    () async {
      final calls = <List<String>>[];
      var failed = false;
      final proxy = MacosProxy(
        commandRunner: ProxyCommandRunner((
          executable,
          arguments, {
          runInShell = false,
        }) async {
          calls.add(arguments);
          if (arguments.first == '-setsocksfirewallproxy' && !failed) {
            failed = true;
            return ProcessResult(1, 1, '', 'denied');
          }
          return ProcessResult(1, 0, _reply(arguments), '');
        }),
      );
      expect(await proxy.start(7890, ['localhost']), isFalse);
      expect(
        calls,
        contains(equals(['-setwebproxy', 'Wi-Fi', 'proxy.before', '8080'])),
      );
      expect(calls, contains(equals(['-setwebproxystate', 'Wi-Fi', 'on'])));
      expect(
        calls,
        contains(equals(['-setsecurewebproxystate', 'Wi-Fi', 'off'])),
      );
      expect(
        calls,
        contains(equals(['-setsocksfirewallproxystate', 'Wi-Fi', 'off'])),
      );
      expect(
        calls,
        contains(
          equals([
            '-setproxybypassdomains',
            'Wi-Fi',
            'example.org',
            '*.internal',
          ]),
        ),
      );
      final beforeStop = calls.length;
      expect(await proxy.stop(), isTrue);
      expect(calls.length, beforeStop);
      expect(calls.any((args) => args.first == '-setautoproxystate'), isFalse);
    },
  );

  test(
    'macOS rollback tries every proxy state and preserves failed work for retry',
    () async {
      final calls = <List<String>>[];
      var refuseRestore = true;
      final proxy = MacosProxy(
        commandRunner: ProxyCommandRunner((
          executable,
          arguments, {
          runInShell = false,
        }) async {
          calls.add(arguments);
          final denied =
              arguments.first == '-setwebproxy' &&
              arguments.contains('proxy.before') &&
              refuseRestore;
          return ProcessResult(1, denied ? 1 : 0, _reply(arguments), '');
        }),
      );
      expect(await proxy.start(7890, []), isTrue);
      expect(await proxy.stop(), isFalse);
      expect(
        calls,
        contains(equals(['-setsocksfirewallproxystate', 'Wi-Fi', 'off'])),
      );
      expect(
        calls.lastWhere((args) => args.first == '-setwebproxystate').last,
        'off',
      );
      refuseRestore = false;
      expect(await proxy.stop(), isTrue);
      expect(calls.where((args) => args.first == '-getwebproxy'), hasLength(1));
    },
  );
}
