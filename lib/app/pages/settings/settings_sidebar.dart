import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'settings_navigation.dart';

/// Desktop settings navigation matching the workspace's compact sidebar.
class SettingsSidebar extends StatelessWidget {
  const SettingsSidebar({
    required this.selected,
    required this.onSelected,
    required this.onBack,
    super.key,
  });

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = theme.extension<AppSurfaces>()!;
    return Material(
      color: surfaces.sidebar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'back'.tr,
                  onPressed: onBack,
                  icon: const AppIcon(AppIcons.arrowLeft),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'settings'.tr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final group in SettingsNavigation.visibleGroups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        group.titleKey.tr,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final section in group.sections) ...[
                      _MenuItem(
                        section: section,
                        selected: section == selected,
                        onTap: () => onSelected(section),
                      ),
                      const SizedBox(height: 3),
                    ],
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
            const Divider(),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'dclash 0.1.0',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: section.titleKey.tr,
      child: Material(
        color: selected ? colors.surfaceContainerHighest : Colors.transparent,
        shape: AppShapes.control,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AppIcon(section.icon, size: 18, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.titleKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
