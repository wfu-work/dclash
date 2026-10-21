import 'package:dclash_flutter/app/pages/profiles/builder/profile_builder_draft.dart';
import 'package:dclash_flutter/app/pages/profiles/builder/resource_picker_dialog.dart';
import 'package:dclash_flutter/domains/resource_item.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/services/resource_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yaml/yaml.dart';

void main() {
  ProfileBuilderDraft draft() => ProfileBuilderDraft.parse('''
proxies:
  - name: Keep
    type: ss
    server: keep.example
    port: 443
    cipher: aes-128-gcm
    password: secret
    unknown-field: keep-me
  - name: Drop
    type: ss
    server: drop.example
    port: 443
    cipher: aes-128-gcm
    password: secret
proxy-groups:
  - name: Main
    type: select
    proxies: [Keep, Drop, DIRECT]
rule-providers: {}
proxy-providers: {}
rules: [MATCH,DIRECT]
''');

  ResourceItem item({
    required String id,
    required ResourceKind kind,
    required ResourceSourceType sourceType,
    required String source,
  }) => ResourceItem(
    id: id,
    name: 'Reusable',
    kind: kind,
    sourceType: sourceType,
    source: source,
    content: null,
    enabled: true,
    order: 0,
    createdAt: DateTime.utc(2026, 10, 21),
    updatedAt: DateTime.utc(2026, 10, 21),
  );

  test('imports proxy records and preserves unknown fields', () {
    final value = draft();
    value.importProxyResource('''
proxies:
  - name: Keep
    type: ss
    server: imported.example
    port: 443
    cipher: aes-128-gcm
    password: secret
    imported-option: true
''');
    final config = loadYaml(value.toYaml()) as YamlMap;
    final proxies = config['proxies'] as YamlList;
    expect(proxies.length, 3);
    expect(proxies.last['name'], 'Keep 2');
    expect(proxies.last['imported-option'], true);
    expect(proxies.first['unknown-field'], 'keep-me');
  });

  test('adds URL and inline rule providers with safe paths', () {
    final value = draft();
    value.addProviderResource(
      BuilderSection.ruleProviders,
      item(
        id: 'url',
        kind: ResourceKind.ruleProvider,
        sourceType: ResourceSourceType.url,
        source: 'https://example.com/rules.yaml',
      ),
    );
    value.addProviderResource(
      BuilderSection.ruleProviders,
      item(
        id: 'inline',
        kind: ResourceKind.ruleProvider,
        sourceType: ResourceSourceType.inline,
        source: 'rules: [DOMAIN-SUFFIX,example.com,DIRECT]',
      ),
    );
    final config = loadYaml(value.toYaml()) as YamlMap;
    final providers = config['rule-providers'] as YamlMap;
    expect(providers.length, 2);
    expect(providers['Reusable']['url'], 'https://example.com/rules.yaml');
    expect(providers['Reusable 2']['type'], 'inline');
  });

  test('filters proxies, keeps builtins, and applies icon mappings', () {
    final value = draft();
    value.applyRegexFilter('Keep');
    value.applyIconSet(
      'Keep: https://example.com/keep.svg\nMain: https://example.com/main.svg',
    );
    final config = loadYaml(value.toYaml()) as YamlMap;
    final proxies = config['proxies'] as YamlList;
    final groups = config['proxy-groups'] as YamlList;
    expect(proxies.length, 1);
    expect(proxies.first['unknown-field'], 'keep-me');
    expect(groups.first['proxies'], ['Keep', 'DIRECT']);
    expect(proxies.first['icon'], 'https://example.com/keep.svg');
    expect(groups.first['icon'], 'https://example.com/main.svg');
  });

  test('rejects filters that match no proxy', () {
    expect(() => draft().applyRegexFilter('missing'), throwsFormatException);
  });

  testWidgets('picker shows only enabled resources and returns selection', (
    tester,
  ) async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    final service = ResourceLibraryService(settings);
    await service.initialize();
    final enabled = await service.save(
      name: 'Enabled',
      kind: ResourceKind.iconSet,
      sourceType: ResourceSourceType.inline,
      source: 'Keep: https://example.com/icon.svg',
    );
    await service.save(
      name: 'Disabled',
      kind: ResourceKind.iconSet,
      sourceType: ResourceSourceType.inline,
      source: 'Drop: https://example.com/icon.svg',
      enabled: false,
    );
    ResourceItem? selected;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selected = await showDialog<ResourceItem>(
                context: context,
                builder: (_) => ResourcePickerDialog(
                  service: service,
                  kind: ResourceKind.iconSet,
                  onSelected: (_) {},
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Disabled'), findsNothing);
    await tester.tap(find.text('Enabled'));
    await tester.pumpAndSettle();
    expect(selected?.id, enabled.id);
  });
}
