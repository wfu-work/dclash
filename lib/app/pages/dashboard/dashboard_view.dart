import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../services/diagnostic_report_service.dart';
import '../../../services/health_history_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../services/traffic_statistics_service.dart';
import '../../widgets/app_widgets.dart';
import '../tools/network_health_history_view.dart';
import '../tools/network_health_view.dart';
import '../tools/network_timeline_view.dart';
import '../tools/traffic_statistics_view.dart';
import '../workspace/workspace_controller.dart';
import 'dashboard_controller.dart';
import 'dashboard_layout_view.dart';
import 'widgets/dashboard_insights.dart';
import 'widgets/dashboard_summary.dart';
import 'widgets/network_overview.dart';
import 'widgets/runtime_resources.dart';
import 'widgets/status_card.dart';
import 'widgets/traffic_card.dart';

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'dashboard'.tr,
    actionsInlineOnCompact: true,
    actions: [
      IconButton(
        key: const ValueKey('dashboardLayoutAction'),
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          backgroundColor: Colors.transparent,
        ),
        tooltip: 'dashboardLayout'.tr,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DashboardLayoutView()),
        ),
        icon: const AppIcon(AppIcons.dashboardLayout),
      ),
      IconButton(
        key: const ValueKey('dashboardSettingsAction'),
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          backgroundColor: Colors.transparent,
        ),
        tooltip: 'settings'.tr,
        onPressed: () => Get.find<WorkspaceController>().openSettings(context),
        icon: const AppIcon(AppIcons.settings),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
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
          'outboundMode': () => _mode(context),
          'runtimeResources': () =>
              DashboardRuntimeResources(controller: controller),
          'serviceStatus': () => _services(context),
        };
        const summaries = {'currentProfile', 'currentOutbound'};
        const network = {'proxyGroups', 'connections'};
        const insights = {'healthSummary', 'todayTraffic', 'recentEvents'};
        return Obx(() {
          final keys = List<String>.from(
            controller.settings.fields['dashboardCards'] as List,
          );
          final children = <Widget>[];
          for (var i = 0; i < keys.length; i++) {
            final key = keys[i];
            final family = summaries.contains(key) ? summaries : network;
            if (family.contains(key)) {
              final sections = [key];
              if (i + 1 < keys.length && family.contains(keys[i + 1])) {
                sections.add(keys[++i]);
              }
              children.add(
                summaries.contains(key)
                    ? DashboardSummary(
                        key: ValueKey(sections.join(':')),
                        controller: controller,
                        sections: sections,
                        onOpenProfiles: () =>
                            Get.find<WorkspaceController>().select(2),
                      )
                    : DashboardNetworkOverview(
                        key: ValueKey(sections.join(':')),
                        controller: controller,
                        sections: sections,
                        onOpenGroups: () =>
                            Get.find<WorkspaceController>().select(1),
                        onOpenConnections: () =>
                            Get.find<WorkspaceController>().select(3),
                      ),
              );
            } else if (insights.contains(key)) {
              final sections = [key];
              if (key == 'healthSummary' &&
                  i + 1 < keys.length &&
                  keys[i + 1] == 'todayTraffic') {
                sections.add(keys[++i]);
              }
              final history = Get.isRegistered<HealthHistoryService>()
                  ? Get.find<HealthHistoryService>()
                  : null;
              final traffic = Get.isRegistered<TrafficStatisticsService>()
                  ? Get.find<TrafficStatisticsService>()
                  : null;
              final timeline = Get.isRegistered<NetworkTimelineService>()
                  ? Get.find<NetworkTimelineService>()
                  : null;
              children.add(
                DashboardInsightPair(
                  key: ValueKey(sections.join(':')),
                  children: [
                    for (final section in sections)
                      if (section == 'healthSummary')
                        DashboardHealthSummary(
                          history: history,
                          onRunCheck: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  NetworkHealthView(history: history),
                            ),
                          ),
                          onOpenReport: (entry) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  NetworkHealthReportView(entry: entry),
                            ),
                          ),
                        )
                      else if (section == 'todayTraffic')
                        DashboardTodayTraffic(
                          statistics: traffic,
                          onOpen: traffic == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TrafficStatisticsView(
                                      statistics: traffic,
                                    ),
                                  ),
                                ),
                        )
                      else
                        DashboardRecentEvents(
                          timeline: timeline,
                          onOpen:
                              timeline == null ||
                                  !Get.isRegistered<DiagnosticReportService>()
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => NetworkTimelineView(
                                      timeline: timeline,
                                      report:
                                          Get.isRegistered<
                                            DiagnosticReportService
                                          >()
                                          ? Get.find<DiagnosticReportService>()
                                          : null,
                                    ),
                                  ),
                                ),
                        ),
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

  Widget _mode(BuildContext context) {
    const modes = <String, (IconData, String)>{
      'rule': (AppIcons.rules, 'ruleModeHint'),
      'global': (AppIcons.globe, 'globalModeHint'),
      'direct': (AppIcons.navigation, 'directModeHint'),
    };
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, box) => Obx(() {
          final colors = Theme.of(context).colorScheme;
          final compact =
              box.maxWidth < 660 ||
              MediaQuery.textScalerOf(context).scale(14) > 19;
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'outboundMode'.tr,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.surfaceContainerLow,
                  shape: AppShapes.card,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < options.length; i++) ...[
                              if (i > 0) const SizedBox(height: 4),
                              options[i],
                            ],
                          ],
                        )
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < options.length; i++) ...[
                                if (i > 0) const SizedBox(width: 4),
                                Expanded(child: options[i]),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.surfaceContainerLow,
                  shape: AppShapes.card,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < operations.length; i++) ...[
                              if (i > 0) const Divider(height: 12),
                              operations[i],
                            ],
                          ],
                        )
                      : Row(
                          children: [
                            for (var i = 0; i < operations.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: operations[i]),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _portSummary(context),
            ],
          );
        }),
      ),
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
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : Colors.transparent,
        shape: AppShapes.control.copyWith(
          side: BorderSide(
            color: selected
                ? colors.primary.withValues(alpha: .35)
                : Colors.transparent,
            width: .5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected
              ? null
              : () => _run(context, () => controller.core.setMode(mode)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                AppIcon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        mode.tr,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? colors.primary : colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint.tr,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (selected)
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colors.primary,
                      shape: AppShapes.pill,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.onPrimary,
                      ),
                    ),
                  )
                else
                  const SizedBox.square(dimension: 18),
              ],
            ),
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
      color: Colors.transparent,
      shape: AppShapes.control,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _run(context, () => controller.changeSetting(key, !enabled)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          child: Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: enabled
                      ? colors.primary.withValues(alpha: .12)
                      : colors.surfaceContainerHigh,
                  shape: AppShapes.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: AppIcon(icon, size: 18, color: foreground),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      (title ?? key).tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.tr,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final port = controller.settings.fields['mixedPort'];
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.router, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text('mixedPort'.tr, style: theme.textTheme.labelSmall),
        ),
      ],
    );
    final address = DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: AppShapes.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          '127.0.0.1:$port',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurface,
            fontFamily: 'JetBrainsMono',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 420
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: address),
              ],
            )
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                address,
              ],
            ),
    );
  }

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
    IconData icon, [
    VoidCallback? action,
  ]) => Row(
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
      if (action != null)
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
