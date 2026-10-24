import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import '../dashboard_controller.dart';

class DashboardRuntimeResources extends StatelessWidget {
  const DashboardRuntimeResources({super.key, required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) => AppCard(
    key: const ValueKey('dashboardRuntimeResources'),
    child: LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = box.maxWidth >= 660 * scale
            ? 4
            : box.maxWidth >= 330 * scale
            ? 2
            : 1;
        return Obx(() {
          final core = controller.core;
          final unavailable = 'runtimeNotRunning'.tr;
          final metrics = <(String, IconData, String)>[
            (
              'memory',
              AppIcons.memory,
              core.running ? formatBytes(core.memory.value) : unavailable,
            ),
            (
              'activeConnections',
              AppIcons.connections,
              core.running ? '${core.connections.length}' : unavailable,
            ),
            (
              'uptime',
              AppIcons.status,
              core.running
                  ? formatDuration(controller.elapsed.value)
                  : unavailable,
            ),
            (
              'coreVersion',
              AppIcons.terminal,
              core.version.value.isEmpty ? unavailable : core.version.value,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'runtimeResources'.tr,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 18),
              for (var start = 0; start < metrics.length; start += columns) ...[
                if (start > 0) const Divider(height: 28),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start; i < start + columns; i++) ...[
                        if (i > start) const VerticalDivider(width: 32),
                        Expanded(
                          child: _Metric(
                            key: ValueKey('dashboardMetric:${metrics[i].$1}'),
                            label: metrics[i].$1.tr,
                            icon: metrics[i].$2,
                            value: metrics[i].$3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        });
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
  });
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: theme.textTheme.labelSmall)),
          ],
        ),
        const SizedBox(height: 8),
        Tooltip(
          message: value,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
