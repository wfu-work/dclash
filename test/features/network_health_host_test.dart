import 'package:dclash_flutter/platform/network_health_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS reads effective proxies without scoped interface overrides',
    () async {
      final calls = <(String, List<String>)>[];
      final host = IoNetworkHealthHost(
        operatingSystem: 'macos',
        commandRunner: (command, args) async {
          calls.add((command, args));
          return '''
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
  HTTPSEnable : 1
  HTTPSProxy : localhost
  HTTPSPort : 7890
  __SCOPED__ : <dictionary> {
    en9 : <dictionary> {
      HTTPEnable : 1
      HTTPProxy : 192.168.1.1
      HTTPPort : 3128
    }
  }
}
''';
        },
      );
      final result = (await host.systemProxy())!;
      expect(result.matches(7890), isTrue);
      expect(result.http.host, '127.0.0.1');
      expect(calls, hasLength(1));
      expect(calls.single.$1, '/usr/sbin/scutil');
      expect(calls.single.$2, ['--proxy']);
    },
  );

  test('automatic macOS proxy never claims a matching manual route', () async {
    final host = IoNetworkHealthHost(
      operatingSystem: 'macos',
      commandRunner: (_, args) async => '''
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : 7890
  ProxyAutoConfigEnable : 1
}
''',
    );
    final result = (await host.systemProxy())!;
    expect(result.enabled, isTrue);
    expect(result.matches(7890), isFalse);
    expect(result.automatic, isTrue);
  });

  test('invalid macOS output is an inspection failure', () async {
    final host = IoNetworkHealthHost(
      operatingSystem: 'macos',
      commandRunner: (_, args) async => 'permission denied',
    );
    await expectLater(host.systemProxy(), throwsFormatException);
  });

  for (final server in [
    '127.0.0.1:7890',
    'http=127.0.0.1:7890;https=localhost:7890;socks=127.0.0.1:7890',
    '[::1]:7890',
  ]) {
    test(
      'Windows reads WinINet shared / per-protocol server $server',
      () async {
        final host = IoNetworkHealthHost(
          operatingSystem: 'windows',
          commandRunner: (command, args) async {
            expect(command, 'powershell.exe');
            expect(args, contains('-NonInteractive'));
            expect(args.last, contains('Get-ItemProperty'));
            expect(args.last, isNot(contains('Set-ItemProperty')));
            return '{"ProxyEnable":1,"ProxyServer":"$server","AutoDetect":0}';
          },
        );
        final result = (await host.systemProxy())!;
        expect(result.matches(7890), isTrue);
        expect(result.matches(8888), isFalse);
      },
    );
  }

  test('Windows respects disabled proxy and warns about PAC', () async {
    for (final autoUrl in ['', 'https://example.com/proxy.pac']) {
      final host = IoNetworkHealthHost(
        operatingSystem: 'windows',
        commandRunner: (_, args) async =>
            '{"ProxyEnable":0,"ProxyServer":"127.0.0.1:7890","AutoConfigURL":"$autoUrl"}',
      );
      final result = (await host.systemProxy())!;
      expect(result.matches(7890), isFalse);
      expect(result.enabled, autoUrl.isNotEmpty);
    }
  });

  for (final desktop in ['GNOME', 'MATE']) {
    test(
      'Linux $desktop inspects proxy settings with read-only gsettings',
      () async {
        final host = IoNetworkHealthHost(
          operatingSystem: 'linux',
          desktop: desktop,
          commandRunner: (command, args) async {
            expect(command, 'gsettings');
            expect(args.first, 'get');
            expect(
              args[1],
              startsWith('org.${desktop.toLowerCase()}.system.proxy'),
            );
            return switch (args.last) {
              'mode' => "'manual'\n",
              'host' => "'127.0.0.1'\n",
              'port' => '7890\n',
              _ => throw StateError('unexpected key'),
            };
          },
        );
        expect((await host.systemProxy())!.matches(7890), isTrue);
      },
    );
  }

  test(
    'Linux disabled and automatic modes do not use saved addresses',
    () async {
      for (final mode in ['none', 'auto']) {
        final host = IoNetworkHealthHost(
          operatingSystem: 'linux',
          desktop: 'GNOME',
          commandRunner: (_, args) async {
            expect(args.last, 'mode');
            return "'$mode'";
          },
        );
        final result = (await host.systemProxy())!;
        expect(result.matches(7890), isFalse);
        expect(result.automatic, mode == 'auto');
      }
    },
  );

  test('unsupported platforms / desktops do not invoke commands', () async {
    for (final platform in ['android', 'ios', 'linux']) {
      final host = IoNetworkHealthHost(
        operatingSystem: platform,
        desktop: 'KDE',
        commandRunner: (_, args) async => fail('must not run commands'),
      );
      expect(await host.systemProxy(), isNull);
    }
  });
}
