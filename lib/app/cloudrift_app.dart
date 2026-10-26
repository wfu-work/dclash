import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../configs/localization/app_translations.dart';
import '../configs/theme/app_theme.dart';
import '../configs/app_services.dart';
import '../configs/app_services_bridge.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'widgets/app_system_ui.dart';
import 'widgets/app_window_frame.dart';

class CloudriftApp extends StatelessWidget {
  const CloudriftApp({super.key, this.services});

  /// Optional only for legacy tests and embedded callers. The production
  /// entry point always supplies the composition-root dependencies.
  final AppServices? services;

  @override
  Widget build(BuildContext context) => Obx(() {
    final dependencies = services ?? appServicesFromGetX();
    final settings = dependencies.settings;
    final accent = settings.fields['accent'] as String? ?? 'blue';
    final pureBlack = settings.fields['pureBlack'] == true;
    final fontFamily = settings.fields['fontFamily'] as String? ?? 'system';
    final locale = (settings.fields['locale'] as String? ?? 'zh_CN').split('_');
    return GetMaterialApp(
      title: 'dclash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(Brightness.light, accent, fontFamily: fontFamily),
      darkTheme: AppTheme.resolve(
        Brightness.dark,
        accent,
        pureBlack: pureBlack,
        fontFamily: fontFamily,
      ),
      themeMode: switch (settings.fields['themeMode']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      translations: AppTranslations(),
      locale: Locale(locale[0], locale[1]),
      fallbackLocale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (_, child) => AppWindowFrame(child: AppSystemUi(child: child!)),
      initialRoute: AppRoutes.workspace,
      getPages: AppPages.forServices(dependencies),
    );
  });
}
