import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import '../dashboard_controller.dart';

class DashboardNetworkOverview extends StatefulWidget {
  const DashboardNetworkOverview({
    super.key,
    required this.controller,
    required this.sections,
    required this.onOpenGroups,
    required this.onOpenConnections,
  });

  final DashboardController controller;
  final List<String> sections;
  final VoidCallback onOpenGroups, onOpenConnections;

  @override
  State<DashboardNetworkOverview> createState() =>
      _DashboardNetworkOverviewState();
}

class _DashboardNetworkOverviewState extends State<DashboardNetworkOverview> {
  late String _selected = widget.sections.first;

  @override
  void didUpdateWidget(covariant DashboardNetworkOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.sections.contains(_selected)) _selected = widget.sections.first;
  }

  String _label(String section) =>
      (section == 'connections' ? 'dashboardRecentConnections' : 'proxyGroups')
          .tr;

  VoidCallback get _open => _selected == 'proxyGroups'
      ? widget.onOpenGroups
      : widget.onOpenConnections;

  @override
  Widget build(BuildContext context) => AppCard(
    key: const ValueKey('dashboardNetworkOverview'),
    child: LayoutBuilder(
      builder: (context, box) {
        final compact =
            box.maxWidth < 530 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        final heading = widget.sections.length == 1
            ? Text(
                _label(_selected),
                style: Theme.of(context).textTheme.titleSmall,
              )
            : Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final section in widget.sections)
                    Semantics(
                      selected: _selected == section,
                      child: TextButton(
                        key: ValueKey('dashboardNetworkTab:$section'),
                        onPressed: () => setState(() => _selected = section),
                        style: TextButton.styleFrom(
                          foregroundColor: _selected == section
                              ? null
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          shape: const RoundedRectangleBorder(),
                          side: BorderSide.none,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                width: 2,
                                color: _selected == section
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_label(section)),
                          ),
                        ),
                      ),
                    ),
                ],
              );
        final action = TextButton.icon(
          key: const ValueKey('dashboardNetworkViewAll'),
          onPressed: _open,
          icon: const AppIcon(AppIcons.chevronRight, size: 16),
          iconAlignment: IconAlignment.end,
          label: Text('viewAll'.tr),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              heading,
              Align(alignment: Alignment.centerRight, child: action),
            ] else
              Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  action,
                ],
              ),
            const SizedBox(height: 8),
            Obx(() {
              final List<Widget> items;
              if (_selected == 'proxyGroups') {
                items = [
                  for (final group in widget.controller.core.groups.take(3))
                    _PreviewRow(
                      icon: AppIcons.route,
                      title: group.name,
                      detail: group.selected,
                      compact: compact,
                      onTap: widget.onOpenGroups,
                    ),
                ];
              } else {
                final connections = widget.controller.core.connections.toList()
                  ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
                items = [
                  for (final connection in connections.take(3))
                    _PreviewRow(
                      icon: connection.network.toLowerCase() == 'udp'
                          ? AppIcons.network
                          : AppIcons.globe,
                      title: connection.host.isEmpty
                          ? connection.destination
                          : connection.host,
                      detail:
                          '${connection.network.toUpperCase()} · ↓ ${formatBytes(connection.download)}',
                      compact: compact,
                      onTap: widget.onOpenConnections,
                    ),
                ];
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        (_selected == 'proxyGroups'
                                ? 'emptyGroups'
                                : 'noConnections')
                            .tr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    items[i],
                  ],
                ],
              );
            }),
          ],
        );
      },
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.compact,
    required this.onTap,
  });
  final IconData icon;
  final String title, detail;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = Tooltip(
      message: title,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
    );
    final value = Tooltip(
      message: detail,
      child: Text(
        detail,
        maxLines: compact ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: compact ? TextAlign.start : TextAlign.end,
        style: theme.textTheme.bodySmall,
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            AppIcon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [name, const SizedBox(height: 5), value],
                    )
                  : Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 20),
                        Expanded(child: value),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
