import 'package:dclash_flutter/app/pages/settings/access/installed_apps_controller.dart';
import 'package:dclash_flutter/app/pages/settings/access/installed_apps_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'installed_apps_test.dart' show FakeInstalledApps;

void main() {
  tearDown(Get.reset);

  testWidgets(
    'phone application picker preserves missing apps and edits selection',
    (tester) async {
      Get.testMode = true;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<String>? saved;
      final controller = Get.put(
        InstalledAppsController(
          selected: ['org.missing'],
          catalog: FakeInstalledApps(),
          persist: (packages) async => saved = packages,
        ),
      );
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('en', 'US'),
          home: const InstalledAppsView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.textContaining('Not installed'), findsOneWidget);
      expect(find.text('Allow application access'), findsOneWidget);
      await tester.tap(find.text('Browser'));
      await tester.pump();
      expect(controller.selected, containsAll(['org.browser', 'org.missing']));
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(saved, ['org.browser', 'org.missing']);
      expect(tester.takeException(), isNull);
    },
  );
}
