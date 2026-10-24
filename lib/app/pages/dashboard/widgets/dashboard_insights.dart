import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/network_health.dart';
import '../../../../domains/network_health_report.dart';
import '../../../../domains/network_timeline.dart';
import '../../../../domains/traffic_statistics.dart';
import '../../../../services/health_history_service.dart';
import '../../../../services/network_timeline_service.dart';
import '../../../../services/traffic_statistics_service.dart';
import '../../../widgets/app_widgets.dart';

/// Adjacent summary cards share a row when space and text size allow it.
class DashboardInsightPair extends StatelessWidget {
  const DashboardInsightPair({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final paired =
          children.length == 2 &&
          box.maxWidth >= 840 &&
          MediaQuery.textScalerOf(context).scale(14) <= 19;
      if (paired) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 16),
            Expanded(child: children[1]),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      );
    },
  );
}

class DashboardHealthSummary extends StatelessWidget {
  const DashboardHealthSummary({
    super.key,
    this.history,
    required this.onRunCheck,
    required this.onOpenReport,
  });

  final HealthHistoryService? history;
  final VoidCallback onRunCheck;
  final ValueChanged<HealthReportEntry> onOpenReport;

  @override
  Widget build(BuildContext context) => history == null
      ? _content(context, null)
      : Obx(
          () => _content(
            context,
            history!.entries.isEmpty ? null : history!.entries.first,
          ),
        );

  Widget _content(BuildContext context, HealthReportEntry? report) {
    final theme = Theme.of(context);
    final failed =
        report?.results.values
            .where((item) => item.status == HealthStatus.failed)
            .length ??
        0;
    final warnings =
        report?.results.values
            .where((item) => item.status == HealthStatus.warning)
            .length ??
        0;
    final passed =
        report?.results.values
            .where((item) => item.status == HealthStatus.passed)
            .length ??
        0;
    final allPassed = passed == HealthCheck.values.length;
    final status = report == null
        ? 'toolsHealthNoReport'
        : failed > 0 || warnings > 0
        ? 'dashboardHealthAttention'
        : allPassed
        ? 'toolsHealthPassed'
        : 'dashboardHealthPartial';
    final color = failed > 0
        ? theme.colorScheme.error
        : warnings > 0
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    return AppCard(
      key: const ValueKey('dashboardHealthSummary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InsightHeading(title: 'healthSummary'.tr, icon: AppIcons.checkList),
          const SizedBox(height: 16),
          Text(
            status.tr,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
          const SizedBox(height: 6),
          Text(
            report == null
                ? 'healthHistoryEmptyHelp'.tr
                : 'dashboardHealthSnapshot'.trParams({
                    'time': _timestamp(context, report.checkedAt),
                  }),
            style: theme.textTheme.bodySmall,
          ),
          if (report != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final check in HealthCheck.values)
                  AppPill(
                    label:
                        '${'healthCheck_${check.name}'.tr} · ${report.results[check] == null ? 'dashboardNoResult'.tr : 'healthStatus_${report.results[check]!.status.name}'.tr}',
                    color: switch (report.results[check]?.status) {
                      HealthStatus.failed => theme.colorScheme.error,
                      HealthStatus.warning => theme.colorScheme.secondary,
                      HealthStatus.passed => theme.colorScheme.primary,
                      _ => null,
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('dashboardRunHealthCheck'),
                onPressed: onRunCheck,
                icon: const AppIcon(AppIcons.checkList, size: 16),
                label: Text('toolsRunHealth'.tr),
              ),
              if (report != null)
                TextButton(
                  key: const ValueKey('dashboardOpenHealthReport'),
                  onPressed: () => onOpenReport(report),
                  child: Text('dashboardViewReport'.tr),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardTodayTraffic extends StatelessWidget {
  const DashboardTodayTraffic({super.key, this.statistics, this.onOpen});
  final TrafficStatisticsService? statistics;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => statistics == null
      ? _content(context)
      : Obx(() {
          statistics!.revision.value;
          return _content(context);
        });

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final service = statistics;
    final usage = service?.usage(TrafficPeriod.today) ?? TrafficAmount.zero;
    final days =
        service?.dailyUsage(TrafficPeriod.week).reversed.toList() ??
        <DailyTrafficUsage>[];
    final state = service == null
        ? 'dashboardStatisticsUnavailable'
        : service.core.preview
        ? 'trafficPreview'
        : service.core.running
        ? 'trafficCollecting'
        : 'trafficStopped';
    return AppCard(
      key: const ValueKey('dashboardTodayTraffic'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InsightHeading(
            title: 'todayTraffic'.tr,
            icon: AppIcons.swap,
            action: onOpen,
            actionKey: 'dashboardOpenTraffic',
          ),
          const SizedBox(height: 12),
          Text(
            formatBytes(usage.total),
            key: const ValueKey('dashboardTodayTrafficTotal'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                '${'upload'.tr} ↑ ${formatBytes(usage.upload)}',
                key: const ValueKey('dashboardTodayUpload'),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${'download'.tr} ↓ ${formatBytes(usage.download)}',
                key: const ValueKey('dashboardTodayDownload'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('dashboardDailyTrend'.tr, style: theme.textTheme.labelMedium),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DailyBars(days: days),
          ],
          const SizedBox(height: 10),
          Text(state.tr, style: theme.textTheme.bodySmall),
          if (service?.saveError.value == true) ...[
            const SizedBox(height: 8),
            Text(
              'trafficSaveFailed'.tr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ] else if (days.isNotEmpty &&
              days.every((day) => day.usage.total == 0)) ...[
            const SizedBox(height: 8),
            Text('trafficEmpty'.tr, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<DailyTrafficUsage> days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxUsage = days.fold(
      1,
      (value, day) => math.max(value, day.usage.total),
    );
    String date(DateTime at) =>
        MaterialLocalizations.of(context).formatShortDate(at);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Semantics(
                      label:
                          '${date(days[index].date)}, ${'upload'.tr} ${formatBytes(days[index].usage.upload)}, ${'download'.tr} ${formatBytes(days[index].usage.download)}',
                      child: Tooltip(
                        message:
                            '${date(days[index].date)} · ${formatBytes(days[index].usage.total)}',
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            heightFactor: days[index].usage.total / maxUsage,
                            child: DecoratedBox(
                              key: ValueKey('dashboardDailyBar:$index'),
                              decoration: BoxDecoration(
                                color: index == days.length - 1
                                    ? colors.primary
                                    : colors.primary.withValues(alpha: .3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                date(days.first.date),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'trafficPeriod_today'.tr,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class DashboardRecentEvents extends StatelessWidget {
  const DashboardRecentEvents({super.key, this.timeline, this.onOpen});
  final NetworkTimelineService? timeline;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => timeline == null
      ? _content(context, const [])
      : Obx(() => _content(context, timeline!.entries.take(3).toList()));

  Widget _content(BuildContext context, List<NetworkTimelineEvent> events) =>
      AppCard(
        key: const ValueKey('dashboardRecentEvents'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InsightHeading(
              title: 'recentEvents'.tr,
              icon: AppIcons.list,
              action: onOpen,
              actionKey: 'dashboardOpenTimeline',
            ),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'timelineEmpty'.tr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (var index = 0; index < events.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _EventPreview(event: events[index], onTap: onOpen),
            ],
          ],
        ),
      );
}

class _EventPreview extends StatelessWidget {
  const _EventPreview({required this.event, this.onTap});
  final NetworkTimelineEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = Map<String, String>.from(event.params);
    for (final key in ['status', 'state', 'mode']) {
      if (params[key] case final value?) params[key] = value.tr;
    }
    final color = switch (event.severity) {
      TimelineSeverity.error => theme.colorScheme.error,
      TimelineSeverity.warning => theme.colorScheme.secondary,
      TimelineSeverity.info => theme.colorScheme.primary,
    };
    final icon = switch (event.kind) {
      TimelineKind.core => AppIcons.power,
      TimelineKind.health => AppIcons.checkList,
      TimelineKind.route => AppIcons.route,
      TimelineKind.settings => AppIcons.settings,
      TimelineKind.error => AppIcons.warning,
      TimelineKind.traffic => AppIcons.swap,
    };
    return InkWell(
      key: ValueKey('dashboardEvent:${event.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    event.titleKey.trParams(params),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timestamp(context, event.occurredAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              AppIcon(
                AppIcons.chevronRight,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightHeading extends StatelessWidget {
  const _InsightHeading({
    required this.title,
    required this.icon,
    this.action,
    this.actionKey,
  });
  final String title;
  final IconData icon;
  final VoidCallback? action;
  final String? actionKey;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AppIcon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      if (action != null)
        IconButton(
          key: ValueKey(actionKey ?? title),
          tooltip: 'viewAll'.tr,
          onPressed: action,
          visualDensity: VisualDensity.compact,
          icon: const AppIcon(AppIcons.chevronRight, size: 20),
        ),
    ],
  );
}

String _timestamp(BuildContext context, DateTime value) {
  final at = value.toLocal();
  return '${MaterialLocalizations.of(context).formatShortDate(at)} ${TimeOfDay.fromDateTime(at).format(context)}';
}
