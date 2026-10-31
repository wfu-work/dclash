import 'dart:convert';

import 'package:dclash_flutter/domains/script_library.dart';
import 'package:dclash_flutter/services/config_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

LibraryScript script(String id, {bool enabled = true}) =>
    LibraryScript(id: id, name: 'Name $id', content: id, enabled: enabled);

void main() {
  for (final entry in {
    'dns': 'dnsOverride',
    'tun': 'tunOverride',
    'sniffer': 'snifferOverride',
    'ntp': 'ntpOverride',
  }.entries) {
    test(
      '${entry.key} overrides recursively preserve nested fields and replace lists',
      () async {
        final content = jsonEncode({
          entry.key: {
            'custom': {
              'kept': {'setting': 'original'},
              'changed': ['old', 'remove'],
              'scalar': 'before',
            },
          },
        });
        final result = loadYaml(
          await ConfigBuilder.build(content, {
            entry.value: jsonEncode({
              'custom': {
                'changed': ['new'],
                'scalar': {'nested': 'after'},
              },
            }),
          }),
        );
        expect(result[entry.key]['custom']['kept']['setting'], 'original');
        expect(result[entry.key]['custom']['changed'], ['new']);
        expect(result[entry.key]['custom']['scalar']['nested'], 'after');
      },
    );
  }
  test(
    'sniffer HTTP port overrides retain TLS and other HTTP fields',
    () async {
      final result = loadYaml(
        await ConfigBuilder.build(
          '''
sniffer:
  sniff:
    HTTP:
      ports: [80, 8080]
      override-destination: false
    TLS:
      ports: [443]
''',
          {'snifferOverride': 'sniff:\n  HTTP:\n    ports: [8888]'},
        ),
      );
      expect(result['sniffer']['sniff']['HTTP']['ports'], [8888]);
      expect(result['sniffer']['sniff']['HTTP']['override-destination'], false);
      expect(result['sniffer']['sniff']['TLS']['ports'], [443]);
    },
  );
  const profile = '''
proxies: []
proxy-groups: []
rules: [MATCH,DIRECT]
external-controller: 0.0.0.0:9090
secret: subscription-secret
mixed-port: 1234
tun: {enable: true, stack: system}
''';
  test(
    'managed fields win over scripts and profile controller settings',
    () async {
      final result = loadYaml(
        await ConfigBuilder.build(profile, {
          'mode': 'global',
          'mixedPort': 7889,
          'allowLan': false,
          'tunEnabled': false,
          'controllerEnabled': true,
          'controllerPort': 19091,
          'controllerSecret': 'private-runtime-secret',
          'tunOverride': 'enable: true\nstack: system',
        }),
      );
      expect(result['mode'], 'global');
      expect(result['mixed-port'], 7889);
      expect(result['external-controller'], '127.0.0.1:19091');
      expect(result['secret'], 'private-runtime-secret');
      expect(result['tun']['enable'], false);
    },
  );
  test('managed runtime enables proxy selection persistence', () async {
    final result = loadYaml(
      await ConfigBuilder.build(
        'profile: {store-selected: false}\nproxies: []',
        const {},
      ),
    );
    expect(result['profile']['store-selected'], true);
  });
  test('provider file paths cannot escape app storage', () async {
    expect(
      () => ConfigBuilder.build(
        'proxy-providers:\n  bad:\n    type: file\n    path: ../../private.key',
        {},
      ),
      throwsException,
    );
    expect(
      () => ConfigBuilder.build(
        'proxy-providers:\n  bad:\n    type: file\n    path: /etc/passwd',
        {},
      ),
      throwsException,
    );
  });
  test(
    'disabled controller removes all subscription controller endpoints',
    () async {
      final result = loadYaml(
        await ConfigBuilder.build(profile, {'controllerEnabled': false}),
      );
      expect(result.containsKey('external-controller'), false);
      expect(result.containsKey('secret'), false);
    },
  );
  test(
    'per-profile shared script selection keeps library order and skips disabled entries',
    () async {
      final selected = <String>[];
      final scripts = ScriptLibrary(
        scripts: [
          script('first'),
          script('second'),
          script('disabled', enabled: false),
        ],
      ).encode();
      final result = loadYaml(
        await ConfigBuilder.build(
          'custom: []',
          {'scripts': scripts},
          sharedScriptIds: const ['second', 'disabled', 'missing', 'first'],
          scriptEvaluator: ({required script, required config}) async {
            selected.add(script);
            final decoded = jsonDecode(config) as Map<String, dynamic>;
            (decoded['custom'] as List).add(script);
            return jsonEncode(decoded);
          },
        ),
      );
      expect(selected, ['first', 'second']);
      expect(result['custom'], ['first', 'second']);
    },
  );
  test('an empty per-profile selection disables shared scripts', () async {
    final selected = <String>[];
    await ConfigBuilder.build(
      'custom: []',
      {
        'scripts': ScriptLibrary(scripts: [script('first')]).encode(),
      },
      sharedScriptIds: const [],
      scriptEvaluator: ({required script, required config}) async {
        selected.add(script);
        return config;
      },
    );
    expect(selected, isEmpty);
  });
  test(
    'standard extension rules are prepended and MATCH uses profile target',
    () async {
      final result = loadYaml(
        await ConfigBuilder.build(
          '''
rules:
  - DOMAIN-SUFFIX,subscription.example,DIRECT
''',
          {'addedRules': '- DOMAIN,global.example,REJECT'},
          profileRules: const [
            'DOMAIN-SUFFIX,profile.example,REJECT',
            'MATCH,MATCH',
          ],
          matchTarget: 'Proxy',
        ),
      );
      expect(result['rules'], [
        'DOMAIN-SUFFIX,profile.example,REJECT',
        'MATCH,Proxy',
        'DOMAIN,global.example,REJECT',
        'DOMAIN-SUFFIX,subscription.example,DIRECT',
      ]);
    },
  );
  test(
    'standard extension rejects malformed rules before managed settings',
    () async {
      await expectLater(
        ConfigBuilder.build(
          'rules: [MATCH,DIRECT]',
          {},
          profileRules: const ['broken,rule,with,too,many,parts'],
        ),
        throwsFormatException,
      );
    },
  );
  test('MATCH target also applies to global added rules', () async {
    final result = loadYaml(
      await ConfigBuilder.build('rules: [MATCH,DIRECT]', {
        'addedRules': '- MATCH,MATCH',
      }, matchTarget: 'Auto'),
    );
    expect(result['rules'].first, 'MATCH,Auto');
  });
  test(
    'TUN receives working DNS defaults and managed performance flags',
    () async {
      final result = loadYaml(
        await ConfigBuilder.build('proxies: []\ndns: {enable: false}', {
          'tunEnabled': true,
          'unifiedDelay': false,
          'tcpConcurrent': true,
        }),
      );
      expect(result['dns']['enable'], true);
      expect(result['dns']['nameserver'], isNotEmpty);
      expect(result['tun']['dns-hijack'], contains('any:53'));
      expect(result['unified-delay'], false);
      expect(result['tcp-concurrent'], true);
    },
  );
  test(
    'rejects malformed root and override types with useful errors',
    () async {
      expect(() => ConfigBuilder.build('- invalid', {}), throwsException);
      expect(() => ConfigBuilder.build('proxies: wrong', {}), throwsException);
      expect(
        () => ConfigBuilder.build('proxies: []', {'dnsOverride': '[invalid]'}),
        throwsException,
      );
    },
  );
  test('added rules precede subscription rules and hosts merge', () async {
    final result = loadYaml(
      await ConfigBuilder.build(
        'rules: ["MATCH,DIRECT"]\nhosts: {old.test: 1.1.1.1}',
        {
          'addedRules': '- DOMAIN,example.com,REJECT',
          'hosts': 'new.test: 127.0.0.1',
        },
      ),
    );
    expect(result['rules'].first, 'DOMAIN,example.com,REJECT');
    expect(result['hosts']['old.test'], '1.1.1.1');
    expect(result['hosts']['new.test'], '127.0.0.1');
  });
}
