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
        icon: const AppIcon(AppIcons.sliders),
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
                    Expanded(child: StatusCard(controller: controller)),
                    const SizedBox(width: 16),
                    Expanded(child: speeds()),
                  ],
                ),
              )
            : Column(
                children: [
                  StatusCard(controller: controller),
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
    final mode = Obx(
      () => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in {
            'rule': AppIcons.rules,
            'global': AppIcons.globe,
            'direct': AppIcons.navigation,
          }.entries)
            ChoiceChip(
              avatar: AppIcon(entry.value, size: 16),
              label: Text(entry.key.tr),
              selected: controller.settings.fields['mode'] == entry.key,
              onSelected: (_) =>
                  _run(context, () => controller.core.setMode(entry.key)),
            ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (wide)
            Row(
              children: [
                Text(
                  'outboundMode'.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                mode,
              ],
            )
          else
            mode,
          const SizedBox(height: 8),
          Obx(
            () => Row(
              children: [
                Expanded(
                  child: _switch(context, 'systemProxy', AppIcons.globe),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _switch(
                    context,
                    'tunEnabled',
                    AppIcons.shield,
                    title: 'tun',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch(
    BuildContext context,
    String key,
    IconData icon, {
    String? title,
  }) => Row(
    children: [
      AppIcon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          (title ?? key).tr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      AppSwitch(
        value: controller.settings.fields[key] == true,
        onChanged: (value) =>
            _run(context, () => controller.changeSetting(key, value)),
      ),
    ],
  );

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
