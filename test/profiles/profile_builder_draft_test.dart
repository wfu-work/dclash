import 'package:dclash_flutter/app/pages/profiles/builder/profile_builder_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const source = '''
custom-root: {keep: true}
dns: {enable: true, nameserver: [1.1.1.1]}
proxies:
  - {name: node, type: vmess, server: example.com, port: 443, uuid: id, ws-opts: {path: /old, headers: {Host: example.com, X-Unknown: keep}}, custom-node: keep}
proxy-groups:
  - {name: group, type: select, proxies: [node, DIRECT], custom-group: keep}
proxy-providers:
  remote: {type: http, url: 'https://example.com/proxies', path: ./remote.yaml, health-check: {enable: true, url: 'https://example.com/check', interval: 300, custom-health: keep}, custom-provider: keep}
rule-providers:
  domains: {type: http, behavior: domain, url: 'https://example.com/rules', path: ./domains.yaml}
rules: ['DOMAIN-SUFFIX,example.com,group', 'MATCH,DIRECT']
''';

  test('form leaf updates preserve unknown root, entry and nested fields', () {
    final draft = ProfileBuilderDraft.parse(source);
    final node = draft.entries(BuilderSection.proxies).single;
    final edited = applyBuilderEdits(node.data, {
      'port': 8443,
      'ws-opts.path': '/new',
    });
    draft.saveEntry(
      BuilderSection.proxies,
      originalName: node.name,
      name: node.name,
      data: edited,
    );
    final result = loadYaml(draft.toYaml());
    expect(result['custom-root']['keep'], true);
    expect(result['dns']['nameserver'], ['1.1.1.1']);
    expect(result['proxies'].single['custom-node'], 'keep');
    expect(result['proxies'].single['ws-opts']['headers']['X-Unknown'], 'keep');
    expect(result['proxies'].single['ws-opts']['path'], '/new');
    expect(result['proxies'].single['port'], 8443);
  });

  test('provider leaf updates keep unrelated health-check fields', () {
    final draft = ProfileBuilderDraft.parse(source);
    final entry = draft.entries(BuilderSection.proxyProviders).single;
    draft.saveEntry(
      BuilderSection.proxyProviders,
      originalName: entry.name,
      name: entry.name,
      data: applyBuilderEdits(entry.data, {'health-check.interval': 600}),
    );
    final result = loadYaml(draft.toYaml());
    expect(result['proxy-providers']['remote']['custom-provider'], 'keep');
    expect(
      result['proxy-providers']['remote']['health-check']['custom-health'],
      'keep',
    );
    expect(
      result['proxy-providers']['remote']['health-check']['interval'],
      600,
    );
  });

  test(
    'renaming updates members and policies; referenced entries cannot be deleted',
    () {
      final draft = ProfileBuilderDraft.parse(source);
      expect(
        () => draft.removeEntry(BuilderSection.proxies, 'node'),
        throwsFormatException,
      );
      final node = draft.entries(BuilderSection.proxies).single;
      draft.saveEntry(
        BuilderSection.proxies,
        originalName: 'node',
        name: 'renamed',
        data: {...node.data, 'name': 'renamed'},
      );
      expect(draft.entries(BuilderSection.groups).single.data['proxies'], [
        'renamed',
        'DIRECT',
      ]);
      final group = draft.entries(BuilderSection.groups).single;
      draft.saveEntry(
        BuilderSection.groups,
        originalName: 'group',
        name: 'route',
        data: {...group.data, 'name': 'route'},
      );
      expect(draft.rules.first, 'DOMAIN-SUFFIX,example.com,route');
      expect(
        () => draft.removeEntry(BuilderSection.groups, 'route'),
        throwsFormatException,
      );
    },
  );

  test('unknown node and rule types survive edits and rule reorder', () {
    final draft = ProfileBuilderDraft.parse(
      'custom-root: keep\nproxies: [{name: future, type: future-protocol, custom: {version: 3}}]\nrules: ["FUTURE,(value,other),DIRECT", "MATCH,DIRECT"]',
    );
    final node = draft.entries(BuilderSection.proxies).single;
    draft.saveEntry(
      BuilderSection.proxies,
      originalName: node.name,
      name: node.name,
      data: {...node.data, 'future-flag': true},
    );
    draft.move(BuilderSection.rules, 0, 2);
    final result = loadYaml(draft.toYaml());
    expect(result['custom-root'], 'keep');
    expect(result['proxies'].single['custom']['version'], 3);
    expect(result['rules'], ['MATCH,DIRECT', 'FUTURE,(value,other),DIRECT']);
    expect(BuilderRule.parse('FUTURE,(value,other),DIRECT').structured, false);
  });

  test(
    'structured rules convert MATCH, RULE-SET and no-resolve without losing raw fallbacks',
    () {
      expect(
        BuilderRule(type: 'MATCH', payload: '', policy: 'DIRECT').toRule(),
        'MATCH,DIRECT',
      );
      final rule = BuilderRule.parse('RULE-SET,domains,group,no-resolve');
      expect(rule.structured, true);
      expect(rule.payload, 'domains');
      expect(rule.noResolve, true);
      expect(rule.toRule(), 'RULE-SET,domains,group,no-resolve');
      expect(
        () => BuilderRule(
          type: 'DOMAIN',
          payload: 'example.com,other',
          policy: 'DIRECT',
        ).toRule(),
        throwsFormatException,
      );
    },
  );

  test(
    'entry YAML accepts group members and keeps optional leaf removal local',
    () {
      final group = parseBuilderEntryYaml(
        'name: group\ntype: select\nproxies: [node, DIRECT]\ncustom: {keep: true, remove: old}',
      );
      expect(group['proxies'], ['node', 'DIRECT']);
      final changed = applyBuilderEdits(group, {'custom.remove': null});
      expect(changed['custom'], {'keep': true});
      expect(changed['proxies'], ['node', 'DIRECT']);
      expect(
        () => parseBuilderEntryYaml('- not a mapping'),
        throwsFormatException,
      );
    },
  );

  test('duplicate policy names and group cycles leave the draft unchanged', () {
    final draft = ProfileBuilderDraft.parse(source);
    final node = draft.entries(BuilderSection.proxies).single;
    expect(
      () => draft.saveEntry(
        BuilderSection.proxies,
        originalName: node.name,
        name: 'group',
        data: node.data,
      ),
      throwsFormatException,
    );
    expect(
      () => draft.saveEntry(
        BuilderSection.groups,
        name: 'loop',
        data: {
          'name': 'loop',
          'type': 'select',
          'proxies': ['loop'],
        },
      ),
      throwsFormatException,
    );
    expect(draft.names(BuilderSection.groups), ['group']);
    expect(draft.names(BuilderSection.proxies), ['node']);
  });

  test('provider renames update group use and RULE-SET references', () {
    final draft = ProfileBuilderDraft.parse(source);
    final group = draft.entries(BuilderSection.groups).single;
    draft.saveEntry(
      BuilderSection.groups,
      originalName: group.name,
      name: group.name,
      data: {
        ...group.data,
        'use': ['remote'],
      },
    );
    final provider = draft.entries(BuilderSection.proxyProviders).single;
    draft.saveEntry(
      BuilderSection.proxyProviders,
      originalName: provider.name,
      name: 'new-provider',
      data: provider.data,
    );
    expect(draft.entries(BuilderSection.groups).single.data['use'], [
      'new-provider',
    ]);
    draft.saveRule('RULE-SET,domains,group,no-resolve');
    final rules = draft.entries(BuilderSection.ruleProviders).single;
    expect(
      () => draft.removeEntry(BuilderSection.ruleProviders, rules.name),
      throwsFormatException,
    );
    draft.saveEntry(
      BuilderSection.ruleProviders,
      originalName: rules.name,
      name: 'new-rules',
      data: rules.data,
    );
    expect(draft.rules.last, 'RULE-SET,new-rules,group,no-resolve');
  });

  test('sub-rules and src flags keep policy references valid', () {
    final draft = ProfileBuilderDraft.parse('''
proxies: [{name: node, type: http, server: example.com, port: 80}]
sub-rules:
  branch: ['MATCH,node', 'IP-CIDR,10.0.0.0/8,node,no-resolve,src']
rules: ['SUB-RULE,(NETWORK,TCP),branch', 'IP-CIDR,10.0.0.0/8,node,src']
''');
    expect(
      () => draft.removeEntry(BuilderSection.proxies, 'node'),
      throwsFormatException,
    );
    draft.saveEntry(
      BuilderSection.proxies,
      originalName: 'node',
      name: 'branch',
      data: draft.entries(BuilderSection.proxies).single.data,
    );
    final result = loadYaml(draft.toYaml());
    expect(result['sub-rules']['branch'], [
      'MATCH,branch',
      'IP-CIDR,10.0.0.0/8,branch,no-resolve,src',
    ]);
    expect(result['rules'], [
      'SUB-RULE,(NETWORK,TCP),branch',
      'IP-CIDR,10.0.0.0/8,branch,src',
    ]);
    // A branch can share a node name; renaming the node must not rename it.
    draft.saveEntry(
      BuilderSection.proxies,
      originalName: 'branch',
      name: 'renamed',
      data: draft.entries(BuilderSection.proxies).single.data,
    );
    expect(draft.rules.first, 'SUB-RULE,(NETWORK,TCP),branch');
  });

  test('nested logical RULE-SET references are renamed and protected', () {
    final draft = ProfileBuilderDraft.parse('''
rule-providers:
  domains: {type: inline, behavior: domain, payload: [example.com]}
sub-rules:
  branch: ['AND,((RULE-SET,domains),(OR,((RULE-SET,domains),(NETWORK,TCP)))),DIRECT']
rules: ['SUB-RULE,(RULE-SET,domains),branch']
''');
    expect(
      () => draft.removeEntry(BuilderSection.ruleProviders, 'domains'),
      throwsFormatException,
    );
    draft.saveEntry(
      BuilderSection.ruleProviders,
      originalName: 'domains',
      name: 'renamed',
      data: draft.entries(BuilderSection.ruleProviders).single.data,
    );
    final result = loadYaml(draft.toYaml());
    expect(result['rules'], ['SUB-RULE,(RULE-SET,renamed),branch']);
    expect(result['sub-rules']['branch'], [
      'AND,((RULE-SET,renamed),(OR,((RULE-SET,renamed),(NETWORK,TCP)))),DIRECT',
    ]);
    expect(
      () => draft.removeEntry(BuilderSection.ruleProviders, 'renamed'),
      throwsFormatException,
    );
  });

  test('an imported custom GLOBAL group remains editable', () {
    final draft = ProfileBuilderDraft.parse(
      'proxy-groups: [{name: GLOBAL, type: select, proxies: [DIRECT]}]',
    );
    draft.saveEntry(
      BuilderSection.groups,
      originalName: 'GLOBAL',
      name: 'GLOBAL',
      data: {
        'type': 'select',
        'proxies': ['DIRECT', 'REJECT'],
      },
    );
    expect(draft.entries(BuilderSection.groups).single.data['proxies'], [
      'DIRECT',
      'REJECT',
    ]);
  });
}
