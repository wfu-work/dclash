import 'package:dclash_flutter/app/pages/profiles/widgets/profile_settings_dialog.dart';
import 'package:dclash_flutter/configs/localization/feature_translations.dart';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/script_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Translations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': FeatureTranslations.en,
    'zh_CN': FeatureTranslations.zh,
  };
}

void main() {
  testWidgets('profile settings switches from library default to a fixed set', (
    tester,
  ) async {
    ClashProfile? result;
    final profile = const ClashProfile(
      id: 'profile',
      name: 'Profile',
      source: ProfileSource.custom,
      path: '/tmp/profile.yaml',
    );
    await tester.pumpWidget(
      GetMaterialApp(
        translations: _Translations(),
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<ClashProfile>(
                  context: context,
                  builder: (_) => ProfileSettingsDialog(
                    profile: profile,
                    scripts: [
                      LibraryScript(
                        id: 'first',
                        name: 'First',
                        content: 'function main(c) { return c; }',
                        enabled: true,
                      ),
                      LibraryScript(
                        id: 'disabled',
                        name: 'Disabled',
                        content: 'function main(c) { return c; }',
                        enabled: false,
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Shared scripts for this profile'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result?.sharedScriptIds, isEmpty);
  });

  testWidgets('profile settings saves standard rules and match target', (
    tester,
  ) async {
    ClashProfile? result;
    const profile = ClashProfile(
      id: 'profile',
      name: 'Profile',
      source: ProfileSource.custom,
      path: '/tmp/profile.yaml',
    );
    await tester.pumpWidget(
      GetMaterialApp(
        translations: _Translations(),
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<ClashProfile>(
                  context: context,
                  builder: (_) => const ProfileSettingsDialog(
                    profile: profile,
                    scripts: [],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard extension'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'DOMAIN-SUFFIX,ads.example,REJECT');
    await tester.enterText(fields.at(2), 'Proxy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result?.standardRules, ['DOMAIN-SUFFIX,ads.example,REJECT']);
    expect(result?.matchTarget, 'Proxy');
  });

  testWidgets('rule presets append without replacing existing rules', (
    tester,
  ) async {
    ClashProfile? result;
    const profile = ClashProfile(
      id: 'profile',
      name: 'Profile',
      source: ProfileSource.custom,
      path: '/tmp/profile.yaml',
      standardRules: ['DOMAIN-SUFFIX,existing.example,DIRECT'],
    );
    await tester.pumpWidget(
      GetMaterialApp(
        translations: _Translations(),
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<ClashProfile>(
                  context: context,
                  builder: (_) => const ProfileSettingsDialog(
                    profile: profile,
                    scripts: [],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Presets'));
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct localhost'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result?.standardRules, [
      'DOMAIN-SUFFIX,existing.example,DIRECT',
      'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
    ]);
  });
}
