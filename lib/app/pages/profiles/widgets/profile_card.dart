import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../configs/theme/app_theme.dart';
import '../../../../domains/clash_profile.dart';
import '../../../widgets/app_widgets.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.active,
    required this.busy,
    required this.onActivate,
    required this.onAction,
  });
  final ClashProfile profile;
  final bool active, busy;
  final VoidCallback onActivate;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final used = profile.used;
    final fraction = profile.total > 0
        ? (used / profile.total).clamp(0.0, 1.0)
        : null;
    final expired = profile.expiresAt?.isBefore(DateTime.now()) ?? false;
    final iconColor = active ? colors.primary : colors.onSurfaceVariant;
    final cardColor = colors.surfaceContainerHigh;
    return Material(
      color: active
          ? Color.alphaBlend(colors.primary.withValues(alpha: .06), cardColor)
          : cardColor,
      shape: AppShapes.card.copyWith(
        side: BorderSide(
          color: active
              ? colors.primary.withValues(alpha: .65)
              : colors.outlineVariant,
          width: active ? 1 : .5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            mainAxisSize: box.hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: .1),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 36,
                      child: Center(
                        child: AppIcon(
                          profile.source == ProfileSource.remote
                              ? AppIcons.cloud
                              : AppIcons.profile,
                          color: iconColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'profileSource_${profile.source.name}'.tr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'featureMore'.tr,
                      icon: const AppIcon(AppIcons.more),
                      onSelected: onAction,
                      itemBuilder: (_) => [
                        if (profile.source == ProfileSource.remote)
                          _menu('refresh', AppIcons.refresh),
                        _menu('builder', AppIcons.tree),
                        _menu('edit', AppIcons.code),
                        _menu('effective', AppIcons.preview),
                        _menu('script', AppIcons.code),
                        _menu('settings', AppIcons.sliders),
                        _menu('duplicate', AppIcons.copy),
                        _menu('export', AppIcons.share),
                        _menu('effectiveExport', AppIcons.download),
                        _menu('remove', AppIcons.delete),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (profile.source == ProfileSource.remote) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatBytes(used)} / ${profile.total > 0 ? formatBytes(profile.total) : 'profileUnlimited'.tr}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (fraction != null)
                      Text(
                        '${(fraction * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                LinearProgressIndicator(
                  value: fraction ?? 0,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                  color: expired ? colors.error : colors.primary,
                  backgroundColor: colors.outlineVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  profile.expiresAt == null
                      ? 'profileNoExpiry'.tr
                      : 'profileExpires'.trParams({
                          'date': _date(profile.expiresAt!),
                        }),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: expired ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ] else
                Text(
                  'profileLocalDescription'.tr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              if (box.hasBoundedHeight) const Spacer(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.updatedAt == null
                          ? 'profileNeverUpdated'.tr
                          : 'profileUpdated'.trParams({
                              'date': _date(profile.updatedAt!),
                            }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (active)
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colors.primary.withValues(alpha: .1),
                        shape: AppShapes.pill,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppIcons.checkCircle,
                              size: 17,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'profileActive'.tr,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: busy ? null : onActivate,
                      icon: const AppIcon(AppIcons.playCircle, size: 17),
                      label: Text('profileActivate'.tr),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menu(String value, IconData icon) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        AppIcon(icon, size: 18),
        const SizedBox(width: 12),
        Text('profileAction_$value'.tr),
      ],
    ),
  );
  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
