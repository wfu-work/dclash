import 'package:dclash_flutter/app/pages/tools/resource_library_controller.dart';
import 'package:dclash_flutter/app/pages/tools/resource_library_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/services/resource_library_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  Future<void> register() async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    final service = ResourceLibraryService(settings);
    await service.initialize();
    Get.put(service);
    Get.put(ResourceLibraryController(service));
  }

  Widget app() => GetMaterialApp(
    translations: AppTranslations(),
    locale: const Locale('zh', 'CN'),
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const ResourceLibraryView(),
  );

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('resource library fits ${size.width}px', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await register();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('资源库'), findsOneWidget);
      expect(find.text('添加资源'), findsWidgets);
      expect(find.text('还没有资源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
