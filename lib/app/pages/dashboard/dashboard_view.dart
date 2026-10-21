import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../workspace/workspace_controller.dart';
import 'dashboard_controller.dart';
import 'dashboard_layout_view.dart';
import 'widgets/status_card.dart';
import 'widgets/traffic_card.dart';

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'dashboard'.tr,
    actions: [
      IconButton(
        tooltip: 'dashboardLayout'.tr,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DashboardLayoutView()),
        ),
        icon: const AppIcon(AppIcons.dashboardLayout),
      ),
      IconButton(
        tooltip: 'settings'.tr,
        onPressed: () => Get.find<WorkspaceController>().openSettings(context),
        icon: const AppIcon(AppIcons.settings),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final middle = box.maxWidth >= 580;
        Widget speeds() => Obx(
          () => Row(
            children: [
              Expanded(
                child: TrafficCard(
                  upload: true,
                  rate: controller.core.upload.value,
                  total: controller.core.totalUpload.value,
                  history: controller.uploadHistory.toList(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TrafficCard(
                  upload: false,
                  rate: controller.core.download.value,
                  total: controller.core.totalDownload.value,
                  history: controller.downloadHistory.toList(),
                ),
              ),
            ],
          ),
        );
        final status = wide
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: StatusCard(controller: controller, compact: false),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: speeds()),
                  ],
                ),
              )
            : Column(
                children: [
                  StatusCard(controller: controller, compact: true),
                  const SizedBox(height: 16),
                  speeds(),
                ],
              );
        final cards = <String, Widget Function()>{
          'status': () => status,
          'outboundMode': () => _mode(context, middle),
          'currentProfile': () => _profile(context),
          'currentOutbound': () => _outbound(context),
          'proxyGroups': () => _groups(context),
          'connections': () => _connections(context),
          'serviceStatus': () => _services(context),
        };
        const pairs = {
          'currentProfile',
          'currentOutbound',
          'proxyGroups',
          'connections',
        };
        return Obx(() {
          final keys = List<String>.from(
            controller.settings.fields['dashboardCards'] as List,
          );
          final children = <Widget>[];
          for (var i = 0; i < keys.length; i++) {
            final key = keys[i];
            if (middle &&
                pairs.contains(key) &&
                i + 1 < keys.length &&
                pairs.contains(keys[i + 1])) {
              children.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[key]!()),
                    const SizedBox(width: 16),
                    Expanded(child: cards[keys[++i]]!()),
                  ],
                ),
              );
            } else {
              children.add(cards[key]!());
            }
            children.add(const SizedBox(height: 16));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        });
      },
    ),
  );

  Widget _mode(BuildContext context, bool wide) {
    final modes = <String, (IconData, String)>{
      'rule': (AppIcons.rules, 'ruleModeHint'),
      'global': (AppIcons.globe, 'globalModeHint'),
      'direct': (AppIcons.navigation, 'directModeHint'),
    };
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Obx(() {
        final colors = Theme.of(context).colorScheme;
        final current = modes.containsKey(controller.settings.fields['mode'])
            ? controller.settings.fields['mode'] as String
            : 'rule';
        final options = [
          for (final entry in modes.entries)
            _modeOption(
              context,
              mode: entry.key,
              icon: entry.value.$1,
              hint: entry.value.$2,
              selected: current == entry.key,
            ),
        ];
        final operations = [
          _settingTile(
            context,
            key: 'systemProxy',
            icon: AppIcons.globe,
            subtitle: 'systemProxyHint',
          ),
          _settingTile(
            context,
            key: 'tunEnabled',
            icon: AppIcons.shield,
            title: 'tun',
            subtitle: 'tunHint',
          ),
          _settingTile(
            context,
            key: 'allowLan',
            icon: AppIcons.network,
            subtitle: 'allowLanHint',
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIcon(AppIcons.route, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'outboundMode'.tr,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                AppPill(label: current.tr, color: colors.primary),
              ],
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: options[i]),
                  ],
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    options[i],
                  ],
                ],
              ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.surfaceContainerLow,
                shape: AppShapes.control,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.info,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (modes[current]?.$2 ?? 'ruleModeHint').tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Divider(color: colors.outlineVariant, height: 1),
            const SizedBox(height: 12),
            if (wide)
              Row(
                children: [
                  for (var i = 0; i < operations.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: operations[i]),
                  ],
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < operations.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    operations[i],
                  ],
                ],
              ),
            const SizedBox(height: 10),
            _portSummary(context),
          ],
        );
      }),
    );
  }

  Widget _modeOption(
    BuildContext context, {
    required String mode,
    required IconData icon,
    required String hint,
    required bool selected,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurface;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: AppShapes.control.copyWith(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1 : .5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selected
            ? null
            : () => _run(context, () => controller.core.setMode(mode)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.tr,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                AppIcon(AppIcons.check, size: 18, color: colors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingTile(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String subtitle,
    String? title,
  }) {
    final colors = Theme.of(context).colorScheme;
    final enabled = controller.settings.fields[key] == true;
    final foreground = enabled ? colors.primary : colors.onSurfaceVariant;
    return Material(
      color: enabled ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: AppShapes.control.copyWith(
        side: BorderSide(
          color: enabled
              ? colors.primary.withValues(alpha: .5)
              : colors.outlineVariant,
          width: .5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _run(context, () => controller.changeSetting(key, !enabled)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 8, 5, 8),
          child: Row(
            children: [
              AppIcon(icon, size: 19, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (title ?? key).tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled ? colors.onSurface : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: enabled,
                semanticLabel: (title ?? key).tr,
                onChanged: (value) =>
                    _run(context, () => controller.changeSetting(key, value)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portSummary(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final port = controller.settings.fields['mixedPort'];
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: AppShapes.control,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            AppIcon(AppIcons.router, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'mixedPort'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: Text(
                '127.0.0.1:$port',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profile(BuildContext context) => AppCard(
    child: Obx(() {
      final profile = controller.profiles.active;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            context,
            'currentProfile',
            AppIcons.profile,
            () => Get.find<WorkspaceController>().select(2),
          ),
          const SizedBox(height: 16),
          Text(
            profile?.name ?? 'noProfile'.tr,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text(
            profile == null
                ? 'addProfileHint'.tr
                : '${'total'.tr} ${formatBytes(profile.used)}${profile.total > 0 ? ' / ${formatBytes(profile.total)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (profile != null && profile.total > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (profile.used / profile.total).clamp(0.0, 1.0),
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ],
      );
    }),
  );

  Widget _outbound(BuildContext context) => AppCard(
    child: Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            context,
            'currentOutbound',
            AppIcons.outbound,
            () => _run(context, controller.detectIp),
          ),
          const SizedBox(height: 16),
          Text(
            controller.outboundIp.isEmpty
                ? 'notDetected'.tr
                : controller.outboundIp.value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text('detectHint'.tr, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(
            children: [
              AppIcon(
                AppIcons.memory,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${'memory'.tr} ${formatBytes(controller.core.memory.value)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (controller.checking.value)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _groups(BuildContext context) => AppCard(
    child: Obx(() {
      final groups = controller.core.groups.take(4).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'proxyGroups',
            AppIcons.layers,
            () => Get.find<WorkspaceController>().select(1),
          ),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'emptyGroups'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                shape: AppShapes.control,
                tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                leading: const AppIcon(AppIcons.route, size: 19),
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  group.selected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Get.find<WorkspaceController>().select(1),
              ),
            ),
        ],
      );
    }),
  );

  Widget _connections(BuildContext context) => AppCard(
    child: Obx(() {
      final items = controller.core.connections.take(5).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'connections',
            AppIcons.connections,
            () => Get.find<WorkspaceController>().select(3),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 45),
              child: Column(
                children: [
                  AppIcon(
                    AppIcons.connections,
                    size: 28,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: .5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'noConnections'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  AppIcon(
                    item.network.toLowerCase() == 'udp'
                        ? AppIcons.network
                        : AppIcons.globe,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.host.isEmpty ? item.destination : item.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatBytes(item.download),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      );
    }),
  );

  Widget _services(BuildContext context) => AppCard(
    child: Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'serviceStatus',
            AppIcons.verified,
            () => _run(context, controller.checkServices),
          ),
          const SizedBox(height: 12),
          if (controller.checkingServices.value)
            const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final name in ['Google', 'GitHub', 'YouTube', 'ChatGPT'])
                Builder(
                  builder: (context) {
                    final item = controller.serviceChecks.firstWhereOrNull(
                      (item) =>
                          item['name'].toString().toLowerCase() ==
                          name.toLowerCase(),
                    );
                    return AppPill(
                      label:
                          '$name · ${item == null ? 'waiting'.tr : '${item['status']} ${item['delay']} ms'}',
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _heading(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback action,
  ) => Row(
    children: [
      AppIcon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title.tr, style: Theme.of(context).textTheme.titleSmall),
      ),
      IconButton(
        tooltip: 'viewAll'.tr,
        onPressed: action,
        visualDensity: VisualDensity.compact,
        icon: const AppIcon(AppIcons.chevronRight, size: 20),
      ),
    ],
  );

  Future<void> _run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}
