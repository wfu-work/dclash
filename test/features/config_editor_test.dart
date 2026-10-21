import 'package:dclash_flutter/app/pages/settings/config_editor/config_draft.dart';
import 'package:dclash_flutter/app/pages/settings/config_editor/config_field_row.dart';
import 'package:dclash_flutter/app/pages/settings/settings_controller.dart';
import 'package:dclash_flutter/app/pages/settings/structured_config_editor_view.dart';
import 'package:dclash_flutter/configs/localization/feature_translations.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Translations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': FeatureTranslations.en,
  };
}

void main() {
  test('structured edits round trip unknown nested fields', () {
    final draft = ConfigDraft.parse('''
enable: true
sniff:
  TLS:
    ports: [443]
    custom-flag: true
  CUSTOM:
    ports: [1234]
custom-extension:
  mode: keep
''');
    draft.write(['sniff', 'TLS', 'ports'], [443, '8443-8445']);
    draft.remove(['enable']);
    final restored = ConfigDraft.parse(draft.encode());
    expect(restored.read(['sniff', 'TLS', 'ports']), [443, '8443-8445']);
    expect(restored.read(['sniff', 'TLS', 'custom-flag']), true);
    expect(restored.read(['sniff', 'CUSTOM', 'ports']), [1234]);
    expect(restored.read(['custom-extension', 'mode']), 'keep');
    expect(restored.contains(['enable']), false);
  });

  test(
    'reset removes empty managed parents while preserving unknown siblings',
    () {
      final draft = ConfigDraft.parse(
        'sniff:\n  TLS:\n    ports: [443]\n  custom: keep',
      );
      draft.remove(['sniff', 'TLS', 'ports']);
      expect(draft.read(['sniff']), {'custom': 'keep'});
      expect(ConfigDraft.parse('{}').encode(), '');
      expect(
        () => ConfigDraft.parse('- list\n- instead'),
        throwsFormatException,
      );
      expect(() => ConfigDraft.parse('enable: ['), throwsA(isA<Exception>()));
    },
  );

  test(
    'an incompatible nested value is preserved until explicitly edited in YAML',
    () {
      final draft = ConfigDraft.parse('sniff:\n  TLS: custom-value');
      expect(
        () => draft.write(['sniff', 'TLS', 'ports'], [443]),
        throwsFormatException,
      );
      expect(draft.read(['sniff', 'TLS']), 'custom-value');
    },
  );

  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    await settings.set(
      'dnsOverride',
      'enable: true\ncustom-option: keep\nnameserver-policy:\n  example.com: 1.1.1.1',
    );
    Get.put(
      SettingsController(
        settings,
        CoreService(ProfileService(), settings, preview: true),
      ),
    );
  });
  tearDown(Get.reset);

  testWidgets(
    'form edits preserve unknown YAML and invalid source stays editable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GetMaterialApp(
          translations: _Translations(),
          locale: const Locale('en', 'US'),
          home: const StructuredConfigEditorView(
            setting: 'dnsOverride',
            title: 'DNS',
            example: 'enable: true',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final enabledRow = find.byKey(const ValueKey('enable'));
      await tester.tap(
        find.descendant(
          of: enabledRow,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('YAML'));
      await tester.pumpAndSettle();
      final source = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      final parsed = ConfigDraft.parse(source);
      expect(parsed.read(['enable']), false);
      expect(parsed.read(['custom-option']), 'keep');
      expect(parsed.read(['nameserver-policy', 'example.com']), '1.1.1.1');
      await tester.enterText(find.byType(TextField), 'enable: [');
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ConfigFieldRow), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
