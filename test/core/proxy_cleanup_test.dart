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

class _RecoveryProxy extends Proxy {
  final recoveredPorts = <int>[];
  bool succeeds = true;

  @override
  Future<bool> recoverStaleProxy(int port) async {
    recoveredPorts.add(port);
    return succeeds;
  }
}

class _RecoveryRuntime extends DesktopCoreRuntime {
  _RecoveryRuntime(Proxy proxy) : super(proxy: proxy);

  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) async => true;
}

class _ProxySetting {
  _ProxySetting(this.host, this.port, {this.enabled = true});
  final String host;
  final int port;
  bool enabled;

  String get output =>
      'Enabled: ${enabled ? 'Yes' : 'No'}\n'
      'Server: $host\nPort: $port\nAuthenticated Proxy Enabled: 0\n';
}

class _MacNetwork {
  final services = ['Wi-Fi', 'USB LAN'];
  late final states = {
    for (final service in services)
      service: {
        for (final kind in ['web', 'secureweb', 'socksfirewall'])
          kind: _ProxySetting('127.0.0.1', 7890),
      },
  };
  final calls = <List<String>>[];
  String? refusedKind;
  String? unreadableKind;
  bool ignoreWrites = false;
  bool listFails = false;

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) async {
    calls.add(arguments);
    final command = arguments.first;
    if (command == '-listallnetworkservices') {
      return ProcessResult(1, listFails ? 1 : 0, services.join('\n'), '');
    }
    if (command.startsWith('-get') && command.endsWith('proxy')) {
      final kind = command.substring(4, command.length - 5);
      return ProcessResult(
        1,
        kind == unreadableKind ? 1 : 0,
        states[arguments[1]]![kind]!.output,
        '',
      );
    }
    if (command.startsWith('-set') && command.endsWith('proxystate')) {
      final kind = command.substring(4, command.length - 10);
      if (kind == refusedKind) return ProcessResult(1, 1, '', 'denied');
      if (!ignoreWrites) states[arguments[1]]![kind]!.enabled = false;
      return ProcessResult(1, 0, '', '');
    }
    throw StateError(
      'Recovery must not alter other network settings: $arguments',
    );
  }

  MacosProxy proxy({ProxyEndpointChecker? endpointInUse}) => MacosProxy(
    commandRunner: ProxyCommandRunner(run),
    endpointInUse: endpointInUse ?? (_, _) async => false,
  );
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
  test('unowned system proxy is checked on disconnect and close', () async {
    final proxy = _RecoveryProxy();
    final runtime = _RecoveryRuntime(proxy);
    await runtime.start({'mixedPort': 17890, 'systemProxy': false});
    await runtime.stop();
    await runtime.close();
    expect(proxy.recoveredPorts, [17890, 17890]);
  });

  test('failed residual cleanup remains retryable', () async {
    final proxy = _RecoveryProxy()..succeeds = false;
    final runtime = _RecoveryRuntime(proxy);
    await runtime.start({'mixedPort': 7890, 'systemProxy': false});
    await expectLater(runtime.close(), throwsA(isA<CoreException>()));
    proxy.succeeds = true;
    await runtime.close();
    expect(proxy.recoveredPorts, [7890, 7890]);
  });

  group('macOS abandoned proxy recovery', () {
    test(
      'clears dead local proxies on every network service without a snapshot',
      () async {
        final network = _MacNetwork();
        expect(await network.proxy().recoverStale(7890), isTrue);
        expect(
          network.states.values
              .expand((states) => states.values)
              .every((state) => !state.enabled),
          isTrue,
        );
        expect(
          network.calls.where((args) => args.first.startsWith('-set')),
          hasLength(6),
        );
      },
    );

    test(
      'preserves live proxies, other ports, remote proxies and disabled states',
      () async {
        final network = _MacNetwork();
        network.states['Wi-Fi']!['web'] = _ProxySetting('proxy.office', 8080);
        network.states['Wi-Fi']!['secureweb'] = _ProxySetting(
          '127.0.0.1',
          8888,
        );
        network.states['Wi-Fi']!['socksfirewall'] = _ProxySetting(
          '127.0.0.1',
          7890,
          enabled: false,
        );
        expect(
          await network
              .proxy(endpointInUse: (_, _) async => true)
              .recoverStale(7890),
          isTrue,
        );
        expect(
          network.calls.any((args) => args.first.startsWith('-set')),
          isFalse,
        );
      },
    );

    test('recognizes IPv6 and localhost loopback proxies', () async {
      final network = _MacNetwork();
      network.states['Wi-Fi']!['web'] = _ProxySetting('::1', 7890);
      network.states['Wi-Fi']!['secureweb'] = _ProxySetting('localhost', 7890);
      network.states['Wi-Fi']!['socksfirewall'] = _ProxySetting('[::1]', 7890);
      expect(await network.proxy().recoverStale(7890), isTrue);
      expect(
        network.states['Wi-Fi']!.values.every((state) => !state.enabled),
        isTrue,
      );
    });

    test(
      'tries other protocols and services after a failure, and can retry',
      () async {
        final network = _MacNetwork()..refusedKind = 'web';
        final proxy = network.proxy();
        expect(await proxy.recoverStale(7890), isFalse);
        expect(network.states['Wi-Fi']!['web']!.enabled, isTrue);
        expect(network.states['USB LAN']!['socksfirewall']!.enabled, isFalse);
        network.refusedKind = null;
        expect(await proxy.recoverStale(7890), isTrue);
        expect(network.states['Wi-Fi']!['web']!.enabled, isFalse);
      },
    );

    test(
      'verifies state instead of trusting a successful process exit',
      () async {
        final network = _MacNetwork()..ignoreWrites = true;
        expect(await network.proxy().recoverStale(7890), isFalse);
      },
    );

    test('reports failed network settings queries', () async {
      final network = _MacNetwork()..listFails = true;
      expect(await network.proxy().recoverStale(7890), isFalse);
      network.listFails = false;
      network.unreadableKind = 'web';
      expect(await network.proxy().recoverStale(7890), isFalse);
      expect(network.states['Wi-Fi']!['web']!.enabled, isTrue);
      expect(network.states['USB LAN']!['socksfirewall']!.enabled, isFalse);
    });

    test(
      'actual socket probe preserves a listener and detects its exit',
      () async {
        final listener = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(listener.close);
        final network = _MacNetwork();
        network.services.remove('USB LAN');
        for (final kind in ['web', 'secureweb', 'socksfirewall']) {
          network.states['Wi-Fi']![kind] = _ProxySetting(
            '127.0.0.1',
            listener.port,
          );
        }
        final port = listener.port;
        final proxy = MacosProxy(
          commandRunner: ProxyCommandRunner(network.run),
        );
        expect(await proxy.recoverStale(port), isTrue);
        expect(network.states['Wi-Fi']!['web']!.enabled, isTrue);
        await listener.close();
        expect(await proxy.recoverStale(port), isTrue);
        expect(network.states['Wi-Fi']!['web']!.enabled, isFalse);
      },
      skip: !Platform.isMacOS,
    );
  });

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
