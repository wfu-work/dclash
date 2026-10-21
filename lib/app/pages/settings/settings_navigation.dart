import 'dart:io';

import 'package:flutter/material.dart';

import '../../../configs/theme/app_icons.dart';

/// Categories shown in the settings workspace.
///
/// Keeping the category identity separate from its translated title means the
/// desktop sidebar can switch content without creating a second route for
/// every setting group.
enum SettingsSection {
  general,
  network,
  access,
  advanced,
  appearance,
  backup,
  about,
}

extension SettingsSectionData on SettingsSection {
  String get key => name;

  String get titleKey => switch (this) {
    SettingsSection.general => 'general',
    SettingsSection.network => 'network',
    SettingsSection.access => 'accessControl',
    SettingsSection.advanced => 'advanced',
    SettingsSection.appearance => 'appearance',
    SettingsSection.backup => 'backup',
    SettingsSection.about => 'about',
  };

  IconData get icon => switch (this) {
    SettingsSection.general => AppIcons.sliders,
    SettingsSection.network => AppIcons.globe,
    SettingsSection.access => AppIcons.apps,
    SettingsSection.advanced => AppIcons.settings,
    SettingsSection.appearance => AppIcons.palette,
    SettingsSection.backup => AppIcons.cloudSync,
    SettingsSection.about => AppIcons.info,
  };

  bool get isAndroidOnly => this == SettingsSection.access;
}

class SettingsMenuGroup {
  const SettingsMenuGroup(this.titleKey, this.sections);

  final String titleKey;
  final List<SettingsSection> sections;
}

abstract final class SettingsNavigation {
  static const groups = <SettingsMenuGroup>[
    SettingsMenuGroup('settingsConnectionGroup', [
      SettingsSection.general,
      SettingsSection.network,
      SettingsSection.access,
    ]),
    SettingsMenuGroup('settingsSystemGroup', [
      SettingsSection.advanced,
      SettingsSection.appearance,
      SettingsSection.backup,
      SettingsSection.about,
    ]),
  ];

  static List<SettingsMenuGroup> get visibleGroups => [
    for (final group in groups)
      SettingsMenuGroup(group.titleKey, [
        for (final section in group.sections)
          if (!section.isAndroidOnly || Platform.isAndroid) section,
      ]),
  ].where((group) => group.sections.isNotEmpty).toList(growable: false);

  static SettingsSection resolve(String? value) {
    final normalized = switch (value) {
      'accessControl' => SettingsSection.access,
      'appPreferences' => SettingsSection.appearance,
      _ => value,
    };
    final section = SettingsSection.values.cast<SettingsSection?>().firstWhere(
      (candidate) => candidate?.key == normalized,
      orElse: () => null,
    );
    if (section == null || (section.isAndroidOnly && !Platform.isAndroid)) {
      return SettingsSection.general;
    }
    return section;
  }
}
