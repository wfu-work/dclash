import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/proxy_group.dart';
import '../../../services/core_ports.dart';
import '../../../services/settings_service.dart';
import '../../widgets/app_widgets.dart';
import 'proxies_controller.dart';
import 'proxies_dependencies.dart';
import 'widgets/proxy_node_tile.dart';

class ProxiesView extends GetView<ProxiesController> {
  const ProxiesView({super.key, this.dependencies});

  final ProxiesDependencies? dependencies;

  CoreProxyPort get _core => dependencies?.core ?? controller.core;
  SettingsService get _settings =>
      dependencies?.settings ?? controller.settings;

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
    actionsInlineOnCompact: true,
    actions: [
      Obx(() {
        final testing = controller.testingAll.value;
        final running = _core.running;
        final onPressed = testing
            ? null
            : () => _run(context, () async {
                if (!_core.running) {
                  throw StateError('featureStartCore'.tr);
                }
                await controller.testAll();
              });
        // On phones this stays a small title-bar action. A labeled button
        // beneath the subtitle leaves an awkward empty action row and competes
        // with the proxy-group controls below.
        final compact =
            MediaQuery.sizeOf(context).width < 600 ||
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
                child: IconButton(
                  key: const ValueKey('proxyTestAllAction'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    backgroundColor: Colors.transparent,
                  ),
                  onPressed: onPressed,
                  icon: icon,
                ),
              )
            : FilledButton.tonalIcon(
                key: const ValueKey('proxyTestAllAction'),
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
                message: _core.running
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
                _groupHeader(context, group, nodes, grid),
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
    final current = switch (_settings.fields['mode']) {
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
        _run(context, () => _core.setMode(mode));
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
                    _run(context, () => _core.setMode(mode));
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

  Widget _groupHeader(
    BuildContext context,
    ProxyGroup group,
    List<ProxyNode> nodes,
    bool grid,
  ) => AppCard(
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
          final controls = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (selected != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth >= 840 ? 240 : 120,
                  ),
                  child: selected,
                ),
              _groupToolbar(context, group, nodes, grid),
            ],
          );
          final heading =
              constraints.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    compactIdentity,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: controls),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    controls,
                  ],
                );
          return heading;
        },
      ),
    ),
  );

  Widget _groupToolbar(
    BuildContext context,
    ProxyGroup group,
    List<ProxyNode> nodes,
    bool grid,
  ) => Obx(() {
    final testing = controller.testingGroups.contains(group.name);
    final expanded = controller.isExpanded(group);
    final hideUnavailable = controller.hideUnavailable;
    final toolbarButtonStyle = IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 2,
      children: [
        IconButton(
          style: toolbarButtonStyle,
          tooltip: 'proxyGroupTest'.tr,
          onPressed: testing
              ? null
              : () => _run(context, () async {
                  if (!_core.running) {
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
        IconButton(
          style: toolbarButtonStyle,
          key: const ValueKey('proxyLocateSelectedAction'),
          tooltip: 'proxyLocateSelected'.tr,
          onPressed: group.selected.isEmpty
              ? null
              : () => _run(
                  context,
                  () => _locateSelected(context, group, nodes, grid),
                ),
          icon: const AppIcon(AppIcons.locate, size: 19),
        ),
        PopupMenuButton<String>(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
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
          style: toolbarButtonStyle,
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
          style: toolbarButtonStyle,
          tooltip: grid ? 'proxyList'.tr : 'proxyGrid'.tr,
          onPressed: () => _run(context, controller.toggleLayout),
          icon: AppIcon(grid ? AppIcons.list : AppIcons.grid, size: 19),
        ),
        IconButton(
          style: toolbarButtonStyle,
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

  Future<void> _locateSelected(
    BuildContext context,
    ProxyGroup group,
    List<ProxyNode> nodes,
    bool grid,
  ) async {
    final index = nodes.indexWhere((node) => node.name == group.selected);
    if (index < 0) throw StateError('proxySelectedHidden'.tr);

    final key = controller.nodeKeyFor(group.name, group.selected);
    final currentContext = key.currentContext;
    if (currentContext != null) {
      await Scrollable.ensureVisible(
        currentContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: .35,
      );
      return;
    }

    final scroll = controller.scrollControllerFor(group.name);
    if (!scroll.hasClients) return;
    final columns = grid ? controller.gridColumnsFor(group.name, 1) : 1;
    final row = grid ? index ~/ columns : index;
    final extent = grid
        ? ProxyNodeTile.gridMainAxisExtent(context)
        : ProxyNodeTile.compactMainAxisExtent(context);
    final spacing = grid ? 12.0 : 8.0;
    final target = (row * (extent + spacing)).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    await scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final builtContext = key.currentContext;
    if (builtContext != null) {
      await Scrollable.ensureVisible(
        builtContext,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: .35,
      );
    }
  }

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
        final columns = grid
            ? (constraints.maxWidth / 300).floor().clamp(1, 5)
            : 1;
        controller.setGridColumns(group.name, columns);

        Widget tile(int index) {
          final node = nodes[index];
          return Obx(
            () => ProxyNodeTile(
              node: node,
              selected: node.name == group.selected,
              delay: controller.delay(node),
              testing: controller.testing.contains(node.name),
              compact: !grid,
              onSelect: group.selectable && _core.running
                  ? () => _run(context, () => controller.select(node))
                  : null,
              onTest: () => _run(context, () async {
                if (!_core.running) {
                  throw StateError('featureStartCore'.tr);
                }
                await controller.test(node);
              }),
            ),
          );
        }

        return grid
            ? GridView.builder(
                controller: controller.scrollControllerFor(group.name),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: ProxyNodeTile.gridMainAxisExtent(context),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: nodes.length,
                itemBuilder: (_, index) => KeyedSubtree(
                  key: controller.nodeKeyFor(group.name, nodes[index].name),
                  child: tile(index),
                ),
              )
            : ListView.separated(
                controller: controller.scrollControllerFor(group.name),
                itemCount: nodes.length,
                itemBuilder: (_, index) => KeyedSubtree(
                  key: controller.nodeKeyFor(group.name, nodes[index].name),
                  child: tile(index),
                ),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              );
      },
    );
  }
}
