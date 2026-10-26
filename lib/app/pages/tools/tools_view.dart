import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../domains/network_health.dart';
import '../../../domains/traffic_statistics.dart';
import '../../../services/health_history_service.dart';
import '../../widgets/app_widgets.dart';
import '../connections/connections_view.dart';
import '../connections/feed_view.dart';
import '../logs/logs_view.dart';
import '../settings/providers_view.dart';
import '../settings/scripts/script_library_view.dart';
import 'resource_library_view.dart';
import 'network_diagnostics_view.dart';
import 'network_health_view.dart';
import 'network_health_history_view.dart';
import 'network_timeline_view.dart';
import 'route_explanation_view.dart';
import 'node_quality_view.dart';
import 'dns_observatory_view.dart';
import 'connection_governance_view.dart';
import 'traffic_statistics_view.dart';
import 'tools_dependencies.dart';

/// A task workspace for diagnosis and runtime observation.
///
/// Settings own persistent configuration. This page surfaces actions, status,
/// and the records useful while investigating a connection problem.
class ToolsView extends StatelessWidget {
  const ToolsView({super.key, this.dependencies});
  final ToolsDependencies? dependencies;

  ToolsDependencies get _services =>
      dependencies ?? ToolsDependencies.fromGetX();

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  String _healthSummary(BuildContext context, HealthHistoryService? history) {
    final reports = history?.entries;
    if (reports == null || reports.isEmpty) return 'toolsHealthNoReport'.tr;
    final latest = reports.first;
    final failed = latest.results.values
        .where((result) => result.status == HealthStatus.failed)
        .length;
    final warnings = latest.results.values
        .where((result) => result.status == HealthStatus.warning)
        .length;
    final state = failed == 0 && warnings == 0
        ? 'toolsHealthPassed'.tr
        : 'healthCounts'.trParams({
            'failed': '$failed',
            'warnings': '$warnings',
          });
    final at = latest.checkedAt.toLocal();
    final timestamp =
        '${MaterialLocalizations.of(context).formatShortDate(at)} ${TimeOfDay.fromDateTime(at).format(context)}';
    return '$state · ${'toolsLastChecked'.trParams({'time': timestamp})}';
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final core = services.core;
    final history = services.healthHistory;
    final traffic = services.trafficStatistics;
    final timeline = services.timeline;
    final report = services.diagnostics;
    final nodeQuality = services.nodeQuality;
    return AppPage(
      maxContentWidth: 980,
      title: 'tools'.tr,
      subtitle: 'toolsWorkspaceHelp'.tr,
      child: Obx(() {
        final running = core.running;
        final connections = core.connections.length;
        final requests = core.requests.length;
        final dnsQueries = core.dnsQueries.length;
        final logs = core.logs.length;
        final healthSummary = _healthSummary(context, history);
        final trafficRevision = traffic?.revision.value ?? 0;
        final nodeQualityRevision = nodeQuality?.revision.value ?? 0;
        final todayTraffic = traffic?.usage(TrafficPeriod.today).total ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PrimaryHealthCard(
              key: const ValueKey('toolsHealthCard'),
              summary: healthSummary,
              onOpen: () => _open(
                context,
                NetworkHealthView(core: core, history: history),
              ),
              onHistory: history == null
                  ? null
                  : () => _open(
                      context,
                      NetworkHealthHistoryView(history: history),
                    ),
            ),
            const SizedBox(height: 16),
            _Heading('toolsQuickActions'.tr),
            const SizedBox(height: 10),
            _ResponsiveGrid(
              minCellWidth: 260,
              spacing: 36,
              runSpacing: 30,
              children: [
                _ToolCard(
                  key: ValueKey('toolsTrafficCard_$trafficRevision'),
                  icon: AppIcons.swap,
                  title: 'trafficStatistics'.tr,
                  subtitle: 'toolsTrafficToday'.trParams({
                    'amount': formatBytes(todayTraffic),
                  }),
                  onTap: () => _open(
                    context,
                    TrafficStatisticsView(statistics: traffic),
                  ),
                ),
                _ToolCard(
                  key: const ValueKey('toolsUrlCard'),
                  icon: AppIcons.globe,
                  title: 'diagnosticUrl'.tr,
                  subtitle: running
                      ? 'toolsUrlReady'.tr
                      : 'diagnosticConnectFirst'.tr,
                  onTap: () => _open(context, UrlDiagnosticsView(core: core)),
                ),
                _ToolCard(
                  key: const ValueKey('toolsRouteExplainCard'),
                  icon: AppIcons.route,
                  title: 'routeExplain'.tr,
                  subtitle: running
                      ? 'toolsRouteExplainReady'.tr
                      : 'diagnosticConnectFirst'.tr,
                  onTap: () => _open(context, RouteExplanationView(core: core)),
                ),
                _ToolCard(
                  key: const ValueKey('toolsServicesCard'),
                  icon: AppIcons.verified,
                  title: 'diagnosticServices'.tr,
                  subtitle: running
                      ? 'toolsServicesReady'.tr
                      : 'diagnosticConnectFirst'.tr,
                  onTap: () =>
                      _open(context, ServiceDiagnosticsView(core: core)),
                ),
                if (timeline != null)
                  _ToolCard(
                    key: const ValueKey('toolsTimelineCard'),
                    icon: AppIcons.terminal,
                    title: 'timelineTitle'.tr,
                    subtitle: 'toolsTimelineCount'.trParams({
                      'count': '${timeline.entries.length}',
                    }),
                    onTap: () => _open(
                      context,
                      NetworkTimelineView(timeline: timeline, report: report),
                    ),
                  ),
                if (report != null)
                  _ToolCard(
                    key: const ValueKey('toolsReportCard'),
                    icon: AppIcons.share,
                    title: 'diagnosticReportTitle'.tr,
                    subtitle: 'toolsReportHelp'.tr,
                    onTap: () =>
                        _open(context, DiagnosticReportView(report: report)),
                  ),
                if (nodeQuality != null)
                  _ToolCard(
                    key: ValueKey('toolsNodeQualityCard_$nodeQualityRevision'),
                    icon: AppIcons.gauge,
                    title: 'nodeQuality'.tr,
                    subtitle: 'toolsNodeQualityCount'.trParams({
                      'count':
                          '${nodeQuality.summaries(const Duration(days: 1)).length}',
                    }),
                    onTap: () =>
                        _open(context, NodeQualityView(quality: nodeQuality)),
                  ),
                _ToolCard(
                  key: const ValueKey('toolsDnsObservatoryCard'),
                  icon: AppIcons.server,
                  title: 'dnsObservatory'.tr,
                  subtitle: 'toolsDnsObservatoryCount'.trParams({
                    'count': '$dnsQueries',
                  }),
                  onTap: () => _open(context, DnsObservatoryView(core: core)),
                ),
                _ToolCard(
                  key: const ValueKey('toolsGovernanceCard'),
                  icon: AppIcons.connections,
                  title: 'connectionGovernance'.tr,
                  subtitle: 'toolsGovernanceCount'.trParams({
                    'count': '$connections',
                  }),
                  onTap: () =>
                      _open(context, ConnectionGovernanceView(core: core)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Heading('toolsLiveActivity'.tr),
            const SizedBox(height: 10),
            _ActivityPanel(
              items: [
                _ActivityItemData(
                  key: const ValueKey('toolsConnectionsCard'),
                  icon: AppIcons.connections,
                  title: 'connections'.tr,
                  value: '$connections',
                  label: 'toolsActiveConnections'.tr,
                  onTap: () => _open(
                    context,
                    const _FeatureRoute(
                      title: 'connections',
                      child: ConnectionsView(),
                    ),
                  ),
                ),
                _ActivityItemData(
                  key: const ValueKey('toolsRequestsCard'),
                  icon: AppIcons.swap,
                  title: 'requests'.tr,
                  value: '$requests',
                  label: 'toolsRequestRecords'.tr,
                  onTap: () => _open(
                    context,
                    _FeatureRoute(
                      title: 'requests',
                      child: FeedView(dns: false, core: core),
                    ),
                  ),
                ),
                _ActivityItemData(
                  key: const ValueKey('toolsDnsCard'),
                  icon: AppIcons.server,
                  title: 'dnsQueries'.tr,
                  value: '$dnsQueries',
                  label: 'toolsDnsRecords'.tr,
                  onTap: () => _open(
                    context,
                    _FeatureRoute(
                      title: 'dnsQueries',
                      child: FeedView(dns: true, core: core),
                    ),
                  ),
                ),
                _ActivityItemData(
                  key: const ValueKey('toolsLogsCard'),
                  icon: AppIcons.terminal,
                  title: 'logs'.tr,
                  value: '$logs',
                  label: 'toolsLogRecords'.tr,
                  onTap: () => _open(
                    context,
                    const _FeatureRoute(title: 'logs', child: LogsView()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Heading('resources'.tr),
            const SizedBox(height: 10),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ResourceRow(
                    title: 'resourceLibrary'.tr,
                    icon: AppIcons.layers,
                    onTap: () => _open(context, const ResourceLibraryView()),
                  ),
                  const Divider(height: 1),
                  _ResourceRow(
                    title: 'providers'.tr,
                    icon: AppIcons.cloud,
                    onTap: () => _open(context, ProvidersView(core: core)),
                  ),
                  const Divider(height: 1),
                  _ResourceRow(
                    title: 'scriptLibrary'.tr,
                    icon: AppIcons.code,
                    onTap: () => _open(
                      context,
                      ScriptLibraryView(service: services.scripts),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
  );
}

class _PrimaryHealthCard extends StatelessWidget {
  const _PrimaryHealthCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.onHistory,
  });
  final String summary;
  final VoidCallback onOpen;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      shape: AppShapes.card.copyWith(
        side: BorderSide(color: colors.outlineVariant, width: .6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: LayoutBuilder(
            builder: (context, box) {
              final compact =
                  box.maxWidth < 560 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              final information = Row(
                children: [
                  _IconBadge(
                    icon: AppIcons.checkList,
                    color: colors.primary,
                    background: colors.surfaceContainerHigh,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'healthTitle'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onHistory != null)
                    OutlinedButton(
                      onPressed: onHistory,
                      child: Text('healthHistory'.tr),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('toolsRunHealth'),
                    onPressed: onOpen,
                    icon: const AppIcon(AppIcons.checkList, size: 17),
                    label: Text('toolsRunHealth'.tr),
                  ),
                ],
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        information,
                        const SizedBox(height: 16),
                        actions,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: information),
                        actions,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.minCellWidth,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
  });
  final double minCellWidth;
  final List<Widget> children;
  final double spacing, runSpacing;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + spacing) / (minCellWidth + spacing))
          .floor()
          .clamp(1, 4);
      final width = (box.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.primary.withValues(alpha: .055),
        focusColor: colors.primary.withValues(alpha: .075),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 148),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconBadge(icon: icon, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const AppIcon(AppIcons.chevronRight, size: 16),
                    label: Text('toolsOpen'.tr),
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

class _ActivityItemData {
  const _ActivityItemData({
    required this.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.label,
    required this.onTap,
  });
  final Key key;
  final IconData icon;
  final String title, value, label;
  final VoidCallback onTap;
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.items});
  final List<_ActivityItemData> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: AppShapes.card.copyWith(
        side: BorderSide(color: colors.outlineVariant, width: .6),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 600;
          if (compact) {
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ActivityItem(data: items[index]),
                  if (index + 1 < items.length) const Divider(height: 1),
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Expanded(child: _ActivityItem(data: items[index])),
                  if (index + 1 < items.length) const VerticalDivider(width: 1),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.data});
  final _ActivityItemData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: data.key,
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(data.icon, size: 18, color: colors.primary),
              const SizedBox(height: 14),
              Text(
                data.value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(data.label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(data.title, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.background});
  final IconData icon;
  final Color color;
  final Color? background;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: background ?? color.withValues(alpha: .10),
      shape: AppShapes.control,
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: AppIcon(icon, size: 20, color: color),
    ),
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.title,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      AppSettingsRow(title: title, icon: icon, onTap: onTap);
}

class _FeatureRoute extends StatelessWidget {
  const _FeatureRoute({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPageLeading(
        leading: IconButton(
          tooltip: 'back'.tr,
          onPressed: () => Navigator.pop(context),
          icon: const AppIcon(AppIcons.arrowLeft),
        ),
        child: child,
      ),
    ),
  );
}
