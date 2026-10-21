import 'package:dclash_flutter/app/pages/profiles/widgets/profile_editor.dart';
import 'package:dclash_flutter/app/pages/settings/scripts/script_library_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/domains/script_library.dart';
import 'package:dclash_flutter/services/script_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  late SettingsService settings;
  late ScriptLibraryService library;
  setUp(() {
    Get.testMode = true;
  });
  tearDown(Get.reset);

  Future<void> initializeLibrary() async {
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    library = ScriptLibraryService(settings)..initialize();
    Get.put(library);
  }

  Widget app() => GetMaterialApp(
    translations: AppTranslations(),
    locale: const Locale('en', 'US'),
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const ScriptLibraryView(),
  );

  testWidgets('local creation uses editor and saves disabled', (tester) async {
    // Keep the write queue in the same fakeAsync zone as the UI save callback.
    await initializeLibrary();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local script'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(library.scripts.single.name, 'Local');
    expect(library.scripts.single.enabled, false);
    expect(find.text('1. Local'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote card fits narrow width and source is read-only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await initializeLibrary();
      await settings.set(
        'scripts',
        ScriptLibrary(
          scripts: [
            LibraryScript(
              id: 'remote',
              name:
                  'A long remote script name that should wrap across the card',
              content: 'function main(config) { return config; }',
              url: 'https://example.com/a/long/path/to/the/shared-script.js',
            ),
          ],
        ).encode(),
      );
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit script'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ProfileCodeEditor>(find.byType(ProfileCodeEditor)).readOnly,
      true,
    );
    expect(tester.takeException(), isNull);
  });
}
