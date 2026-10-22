import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/proxy_group.dart';
import '../../widgets/app_widgets.dart';
import 'proxies_controller.dart';
import 'widgets/proxy_node_tile.dart';

class ProxiesView extends GetView<ProxiesController> {
  const ProxiesView({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'featureProxies'.tr,
    subtitle: 'proxySubtitle'.tr,
    scroll: false,
    actions: [
      Obx(() {
        final testing = controller.testingAll.value;
        final running = controller.core.running;
        final onPressed = testing
            ? null
            : () => _run(context, () async {
                if (!controller.core.running) {
                  throw StateError('featureStartCore'.tr);
                }
                await controller.testAll();
              });
        final compact =
            MediaQuery.sizeOf(context).width < 400 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        final icon = testing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppIcon(AppIcons.gauge, size: 18);
        return compact
            ? Tooltip(
                message: running ? 'proxyTestAll'.tr : 'featureStartCore'.tr,
                child: IconButton.filledTonal(onPressed: onPressed, icon: icon),
              )
            : FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: icon,
                label: Text(
                  'proxyTestAll'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
      }),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modeBar(context),
        const SizedBox(height: 12),
        Obx(() {
          final searchOpen = controller.searchOpen.value;
          return LayoutBuilder(
            builder: (context, constraints) {
              final search = searchOpen
                  ? Row(
                      children: [
                        Expanded(
                          child: AppSearchField(
                            onChanged: (value) =>
                                controller.query.value = value,
                            hint: 'proxySearch'.tr,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'close'.tr,
                          onPressed: controller.toggleSearch,
                          icon: const AppIcon(AppIcons.close, size: 19),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: IconButton.filledTonal(
                        tooltip: 'proxySearchOpen'.tr,
                        onPressed: controller.toggleSearch,
                        icon: const AppIcon(AppIcons.search, size: 19),
                      ),
                    );
              return constraints.maxWidth < 560
                  ? search
                  : Row(children: [Expanded(child: search)]);
            },
          );
        }),
        const SizedBox(height: 12),
        Expanded(
          child: Obx(() {
            final groups = controller.groups;
            final group = controller.group;
            if (controller.previewLoading.value && groups.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (groups.isEmpty || group == null) {
              return AppEmpty(
                icon: AppIcons.connections,
                title: 'proxyEmpty'.tr,
                message: controller.core.running
                    ? 'proxyEmptyRunning'.tr
                    : controller.hasActiveProfile
                    ? 'proxyEmptyConfig'.tr
                    : 'featureStartCore'.tr,
              );
            }
            final expanded = controller.isExpanded(group);
            final nodes = controller.visibleNodes;
            final grid = controller.grid.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: groups
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(item.name),
                              selected: item.name == group.name,
                              onSelected: (_) =>
                                  controller.selectedGroup.value = item.name,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _groupHeader(context, group),
                const SizedBox(height: 12),
                if (expanded)
                  Expanded(child: _nodes(context, group, nodes, grid))
                else
                  Expanded(
                    child: Center(
                      child: Text(
                        'proxyGroupCollapsed'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    ),
  );

  Widget _modeBar(BuildContext context) => Obx(() {
    final current = switch (controller.settings.fields['mode']) {
      'global' => 'global',
      'direct' => 'direct',
      _ => 'rule',
    };
    final selector = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 'rule',
          icon: const AppIcon(AppIcons.rules, size: 17),
          label: Text('rule'.tr),
        ),
        ButtonSegment(
          value: 'global',
          icon: const AppIcon(AppIcons.globe, size: 17),
          label: Text('global'.tr),
        ),
        ButtonSegment(
          value: 'direct',
          icon: const AppIcon(AppIcons.navigation, size: 17),
          label: Text('direct'.tr),
        ),
      ],
      selected: {current},
      onSelectionChanged: (values) {
        final mode = values.firstOrNull;
        if (mode == null || mode == current) return;
        _run(context, () => controller.core.setMode(mode));
      },
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final denseText = MediaQuery.textScalerOf(context).scale(14) > 19;
          final title = Row(
            children: [
              AppIcon(
                AppIcons.route,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'outboundMode'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
          if (denseText) {
            return Row(
              children: [
                Expanded(child: title),
                DropdownButton<String>(
                  value: current,
                  isDense: true,
                  items: [
                    for (final mode in ['rule', 'global', 'direct'])
                      DropdownMenuItem(value: mode, child: Text(mode.tr)),
                  ],
                  onChanged: (mode) {
                    if (mode == null || mode == current) return;
                    _run(context, () => controller.core.setMode(mode));
                  },
                ),
              ],
            );
          }
          return constraints.maxWidth < 560
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: selector,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    selector,
                  ],
                );
        },
      ),
    );
  });

  Widget _groupHeader(BuildContext context, ProxyGroup group) => AppCard(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colors = Theme.of(context).colorScheme;
          final groupPills = Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              AppPill(label: group.type),
              AppPill(
                label: 'proxyNodeCount'.trParams({
                  'count': '${group.nodes.length}',
                }),
              ),
            ],
          );
          final identity = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.layers, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              groupPills,
            ],
          );
          final compactIdentity = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppIcon(AppIcons.layers, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: groupPills,
              ),
            ],
          );
          final selected = group.selected.isEmpty
              ? null
              : Text(
                  group.selected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                );
          final heading = constraints.maxWidth < 600
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    compactIdentity,
                    if (selected != null) ...[
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: selected,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _groupToolbar(context, group),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    if (selected != null) ...[
                      const SizedBox(width: 12),
                      Flexible(child: selected),
                    ],
                    const SizedBox(width: 12),
                    _groupToolbar(context, group),
                  ],
                );
          return heading;
        },
      ),
    ),
  );

  Widget _groupToolbar(BuildContext context, ProxyGroup group) => Obx(() {
    final testing = controller.testingGroups.contains(group.name);
    final expanded = controller.isExpanded(group);
    final hideUnavailable = controller.hideUnavailable;
    final grid = controller.grid.value;
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'proxyGroupTest'.tr,
          onPressed: testing
              ? null
              : () => _run(context, () async {
                  if (!controller.core.running) {
                    throw StateError('featureStartCore'.tr);
                  }
                  await controller.testGroup(group);
                }),
          icon: testing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppIcon(AppIcons.gauge, size: 19),
        ),
        PopupMenuButton<String>(
          tooltip: '${'featureSort'.tr} · ${'proxySort_${controller.sort}'.tr}',
          initialValue: controller.sort,
          onSelected: (value) => _run(context, () => controller.setSort(value)),
          itemBuilder: (_) => ['default', 'name', 'delay']
              .map(
                (value) => AppCheckedMenuItem(
                  value: value,
                  checked: controller.sort == value,
                  child: Text('proxySort_$value'.tr),
                ),
              )
              .toList(),
          icon: const AppIcon(AppIcons.sort, size: 19),
        ),
        IconButton(
          tooltip: 'proxyHideUnavailable'.tr,
          isSelected: hideUnavailable,
          onPressed: () => _run(
            context,
            () => controller.setHideUnavailable(!hideUnavailable),
          ),
          icon: const AppIcon(AppIcons.filterOff, size: 19),
          selectedIcon: const AppIcon(AppIcons.filter, size: 19),
        ),
        IconButton(
          tooltip: 'proxySearchOpen'.tr,
          isSelected: controller.searchOpen.value,
          onPressed: controller.toggleSearch,
          icon: const AppIcon(AppIcons.search, size: 19),
        ),
        IconButton(
          tooltip: grid ? 'proxyList'.tr : 'proxyGrid'.tr,
          onPressed: () => _run(context, controller.toggleLayout),
          icon: AppIcon(grid ? AppIcons.list : AppIcons.grid, size: 19),
        ),
        IconButton(
          tooltip: expanded ? 'proxyCollapse'.tr : 'proxyExpand'.tr,
          onPressed: () => controller.toggleGroup(group),
          icon: AppIcon(
            expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
            size: 19,
          ),
        ),
      ],
    );
  });

  Widget _nodes(
    BuildContext context,
    ProxyGroup group,
    List<ProxyNode> nodes,
    bool grid,
  ) {
    if (nodes.isEmpty) {
      return AppEmpty(
        icon: AppIcons.searchOff,
        title: 'featureNoResults'.tr,
        message: 'proxyNoResults'.tr,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget tile(int index) {
          final node = nodes[index];
          return Obx(
            () => ProxyNodeTile(
              node: node,
              selected: node.name == group.selected,
              delay: controller.delay(node),
              testing: controller.testing.contains(node.name),
              compact: !grid,
              onSelect: group.selectable && controller.core.running
                  ? () => _run(context, () => controller.select(node))
                  : null,
              onTest: () => _run(context, () async {
                if (!controller.core.running) {
                  throw StateError('featureStartCore'.tr);
                }
                await controller.test(node);
              }),
            ),
          );
        }

        return grid
            ? GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (constraints.maxWidth / 300).floor().clamp(
                    1,
                    5,
                  ),
                  mainAxisExtent:
                      100 +
                      (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                              .clamp(0, 2) *
                          60,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: nodes.length,
                itemBuilder: (_, index) => tile(index),
              )
            : ListView.separated(
                itemCount: nodes.length,
                itemBuilder: (_, index) => tile(index),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              );
      },
    );
  }
}
