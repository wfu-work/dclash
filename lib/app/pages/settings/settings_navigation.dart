import 'dart:io';

import 'package:flutter/material.dart';

import '../../../configs/theme/app_icons.dart';

enum SettingsSection {
  appearance,
  startup,
  dashboard,
  shortcuts,
  notifications,
  general,
  network,
  advanced,
  access,
  kernel,
  backup,
  privacy,
  performance,
  about,
  licenses,
  updates,
}

extension SettingsSectionData on SettingsSection {
  String get key => name;
  String get titleKey => switch (this) {
    SettingsSection.appearance => 'appearance',
    SettingsSection.startup => 'settingsStartup',
    SettingsSection.dashboard => 'settingsDashboard',
    SettingsSection.shortcuts => 'settingsShortcuts',
    SettingsSection.notifications => 'settingsNotifications',
    SettingsSection.general => 'settingsProxy',
    SettingsSection.network => 'settingsDnsTun',
    SettingsSection.advanced => 'settingsAdvanced',
    SettingsSection.access => 'accessControl',
    SettingsSection.kernel => 'settingsKernel',
    SettingsSection.backup => 'backup',
    SettingsSection.privacy => 'settingsPrivacy',
    SettingsSection.performance => 'settingsPerformance',
    SettingsSection.about => 'aboutMenu',
    SettingsSection.licenses => 'thirdPartyLicenses',
    SettingsSection.updates => 'settingsUpdates',
  };
  IconData get icon => switch (this) {
    SettingsSection.appearance => AppIcons.palette,
    SettingsSection.startup => AppIcons.power,
    SettingsSection.dashboard => AppIcons.dashboardLayout,
    SettingsSection.shortcuts => AppIcons.key,
    SettingsSection.notifications => AppIcons.info,
    SettingsSection.general => AppIcons.globe,
    SettingsSection.network => AppIcons.router,
    SettingsSection.advanced => AppIcons.code,
    SettingsSection.access => AppIcons.apps,
    SettingsSection.kernel => AppIcons.server,
    SettingsSection.backup => AppIcons.cloudSync,
    SettingsSection.privacy => AppIcons.shield,
    SettingsSection.performance => AppIcons.gauge,
    SettingsSection.about => AppIcons.info,
    SettingsSection.licenses => AppIcons.verified,
    SettingsSection.updates => AppIcons.cloudDownload,
  };
  bool get visible => switch (this) {
    SettingsSection.access => Platform.isAndroid,
    SettingsSection.startup || SettingsSection.shortcuts =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux,
    _ => true,
  };
}

class SettingsMenuGroup {
  const SettingsMenuGroup(this.titleKey, this.sections);
  final String titleKey;
  final List<SettingsSection> sections;
}

abstract final class SettingsNavigation {
  static const groups = <SettingsMenuGroup>[
    SettingsMenuGroup('settingsCommonGroup', [
      SettingsSection.appearance,
      SettingsSection.startup,
      SettingsSection.dashboard,
      SettingsSection.shortcuts,
      SettingsSection.notifications,
    ]),
    SettingsMenuGroup('settingsConnectionGroup', [
      SettingsSection.general,
      SettingsSection.network,
      SettingsSection.advanced,
      SettingsSection.access,
    ]),
    SettingsMenuGroup('settingsSystemGroup', [
      SettingsSection.kernel,
      SettingsSection.backup,
      SettingsSection.privacy,
      SettingsSection.performance,
    ]),
    SettingsMenuGroup('settingsAboutGroup', [
      SettingsSection.about,
      SettingsSection.licenses,
      SettingsSection.updates,
    ]),
  ];
  static List<SettingsMenuGroup> get visibleGroups => [
    for (final group in groups)
      SettingsMenuGroup(group.titleKey, [
        for (final section in group.sections)
          if (section.visible) section,
      ]),
  ].where((group) => group.sections.isNotEmpty).toList(growable: false);

  static SettingsSection resolve(String? value) {
    final normalized = switch (value) {
      'accessControl' => 'access',
      'appPreferences' => 'appearance',
      _ => value,
    };
    return SettingsSection.values.firstWhere(
      (section) => section.key == normalized && section.visible,
      orElse: () => SettingsSection.appearance,
    );
  }
}
