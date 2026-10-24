import 'package:dclash_flutter/app/pages/settings/settings_controller.dart';
import 'package:dclash_flutter/app/pages/settings/settings_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  Future<void> initializeServices() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    Get.put(settings);
    final core = CoreService(ProfileService(), settings, preview: true);
    core.error.value =
        'A long readable failure message: ${'network error ' * 20}';
    Get.put(core);
    Get.put(SettingsController(settings, core));
    final updates = UpdateService(
      settings,
      version: () async => '0.1.0',
      fetch: () async => null,
    );
    Get.put(updates);
  }

  tearDown(Get.reset);

  for (final size in [
    const Size(320, 768),
    const Size(390, 844),
    const Size(1240, 850),
  ]) {
    testWidgets('new settings sections fit $size with enlarged text', (
      tester,
    ) async {
      await initializeServices();
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.binding.setSurfaceSize(null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      for (final language in ['zh', 'en']) {
        for (final section in [
          'startup',
          'shortcuts',
          'notifications',
          'general',
          'network',
          'advanced',
          'kernel',
          'privacy',
          'performance',
          'updates',
        ]) {
          await tester.pumpWidget(
            GetMaterialApp(
              translations: AppTranslations(),
              locale: Locale(language, language == 'zh' ? 'CN' : 'US'),
              theme: AppTheme.resolve(Brightness.dark, 'blue'),
              home: SettingsView(
                key: ValueKey('$language:$section'),
                section: section,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$language $section');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('performance switch and interval change persist from the page', (
    tester,
  ) async {
    await initializeServices();
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        theme: AppTheme.resolve(Brightness.light, 'blue'),
        home: const SettingsView(section: 'performance'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Background refresh interval'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      Get.find<SettingsService>().fields['reduceBackgroundRefresh'],
      isFalse,
    );
    expect(find.text('Background refresh interval'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
