import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/cloudrift_app.dart';
import 'app/widgets/app_icon.dart';
import 'app/widgets/app_message.dart';
import 'app/widgets/app_system_ui.dart';
import 'configs/app_initializer.dart';
import 'configs/app_startup.dart';
import 'configs/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSystemUi.initialize();
  try {
    final services = await AppInitializer.init(
      preview: const bool.fromEnvironment('DC_PREVIEW'),
    );
    runApp(CloudriftApp(services: services));
    final core = services.core;
    if (shouldConnectOnLaunch(
      preview: const bool.fromEnvironment('DC_PREVIEW'),
      autoStart: core.settings.fields['autoStart'] == true,
      hasActiveProfile: core.profiles.active != null,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          core.start().catchError((Object error) {
            final context = Get.context;
            if (context != null && context.mounted) {
              AppMessage.error(context, error);
            }
          }),
        );
      });
    }
  } on Object catch (error) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.resolve(Brightness.light, 'blue'),
        builder: (_, child) => AppSystemUi(child: child!),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(AppIcons.cloudOff, size: 48),
                      const SizedBox(height: 20),
                      const Text('dclash 启动失败 / dclash could not start'),
                      const SizedBox(height: 12),
                      SelectableText('$error'),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () async {
                          Get.reset();
                          await main();
                        },
                        child: const Text('重试 / Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
