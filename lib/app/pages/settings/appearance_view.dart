import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'settings_controller.dart';

class AppearanceView extends GetView<SettingsController> {
  const AppearanceView({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final page = AppPage(
      maxContentWidth: 820,
      title: 'appearance'.tr,
      automaticallyImplyLeading: !embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: 'theme'.tr,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Obx(
                () => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final mode in ['system', 'light', 'dark'])
                      ChoiceChip(
                        avatar: AppIcon(switch (mode) {
                          'light' => AppIcons.sun,
                          'dark' => AppIcons.moon,
                          _ => AppIcons.themeSystem,
                        }, size: 18),
                        label: Text(mode.tr),
                        selected:
                            controller.settings.fields['themeMode'] == mode,
                        onSelected: (_) => _set(context, 'themeMode', mode),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AppSection(
            title: 'accent'.tr,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Obx(
                () => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in AppTheme.accents.entries)
                      ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: entry.value,
                          radius: 8,
                        ),
                        label: Text(entry.key.tr),
                        selected:
                            controller.settings.fields['accent'] == entry.key,
                        onSelected: (_) => _set(context, 'accent', entry.key),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AppSection(
            title: 'display'.tr,
            child: Obx(
              () => Column(
                children: [
                  AppSettingsRow(
                    title: 'pureBlack'.tr,
                    subtitle: 'pureBlackHint'.tr,
                    icon: AppIcons.contrast,
                    trailing: AppSwitch(
                      value: controller.settings.fields['pureBlack'] == true,
                      onChanged: (value) => _set(context, 'pureBlack', value),
                    ),
                  ),
                  for (final font in ['system', 'JetBrainsMono'])
                    AppSettingsRow(
                      title: font == 'system'
                          ? 'systemFont'.tr
                          : 'JetBrains Mono',
                      icon: AppIcons.typography,
                      trailing: controller.settings.fields['fontFamily'] == font
                          ? AppIcon(
                              AppIcons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : const SizedBox(width: 24),
                      onTap: () => _set(context, 'fontFamily', font),
                    ),
                ],
              ),
            ),
          ),
          AppSection(
            title: 'language'.tr,
            child: Obx(
              () => Column(
                children: [
                  for (final locale in ['zh_CN', 'en_US'])
                    AppSettingsRow(
                      title: locale.tr,
                      trailing: controller.settings.fields['locale'] == locale
                          ? AppIcon(
                              AppIcons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : const SizedBox(width: 24),
                      onTap: () => _set(context, 'locale', locale),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return embedded ? page : Scaffold(body: SafeArea(child: page));
  }

  Future<void> _set(BuildContext context, String key, dynamic value) async {
    try {
      await controller.set(key, value);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}
