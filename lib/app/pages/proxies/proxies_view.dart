import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
      Obx(
        () => FilledButton.tonalIcon(
          onPressed: !controller.core.running || controller.testingAll.value
              ? null
              : () => _run(context, controller.testAll),
          icon: controller.testingAll.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppIcon(AppIcons.gauge, size: 18),
          label: Text('proxyTestAll'.tr),
        ),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final filters = Obx(
              () => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip:
                        '${'featureSort'.tr} · ${'proxySort_${controller.sort}'.tr}',
                    initialValue: controller.sort,
                    onSelected: (value) =>
                        _run(context, () => controller.setSort(value)),
                    itemBuilder: (_) => ['default', 'name', 'delay']
                        .map(
                          (value) => AppCheckedMenuItem(
                            value: value,
                            checked: controller.sort == value,
                            child: Text('proxySort_$value'.tr),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const AppIcon(AppIcons.sort, size: 20),
                          if (constraints.maxWidth >= 600) ...[
                            const SizedBox(width: 6),
                            Text('proxySort_${controller.sort}'.tr),
                          ],
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'proxyHideUnavailable'.tr,
                    isSelected: controller.hideUnavailable,
                    onPressed: () => _run(
                      context,
                      () => controller.setHideUnavailable(
                        !controller.hideUnavailable,
                      ),
                    ),
                    icon: const AppIcon(AppIcons.filterOff),
                    selectedIcon: const AppIcon(AppIcons.filter),
                  ),
                  IconButton(
                    tooltip: controller.grid.value
                        ? 'proxyList'.tr
                        : 'proxyGrid'.tr,
                    onPressed: () => _run(context, controller.toggleLayout),
                    icon: AppIcon(
                      controller.grid.value ? AppIcons.list : AppIcons.grid,
                    ),
                  ),
                ],
              ),
            );
            final search = AppSearchField(
              onChanged: (value) => controller.query.value = value,
              hint: 'proxySearch'.tr,
            );
            return constraints.maxWidth < 560
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      Align(alignment: Alignment.centerRight, child: filters),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 12),
                      filters,
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Obx(() {
            final groups = controller.groups;
            final group = controller.group;
            final grid = controller.grid.value;
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
            final nodes = controller.visibleNodes;
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    AppPill(label: group.type),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${group.selected} · ${'proxyNodeCount'.trParams({'count': '${group.nodes.length}'})}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: nodes.isEmpty
                      ? AppEmpty(
                          icon: AppIcons.searchOff,
                          title: 'featureNoResults'.tr,
                          message: 'proxyNoResults'.tr,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            Widget tile(int index) {
                              final node = nodes[index];
                              return Obx(
                                () => ProxyNodeTile(
                                  node: node,
                                  selected: node.name == group.selected,
                                  delay: controller.delay(node),
                                  testing: controller.testing.contains(
                                    node.name,
                                  ),
                                  compact: !grid,
                                  onSelect:
                                      group.selectable &&
                                          controller.core.running
                                      ? () => _run(
                                          context,
                                          () => controller.select(node),
                                        )
                                      : null,
                                  onTest: controller.core.running
                                      ? () => _run(
                                          context,
                                          () => controller.test(node),
                                        )
                                      : null,
                                ),
                              );
                            }

                            return grid
                                ? GridView.builder(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount:
                                              (constraints.maxWidth / 300)
                                                  .floor()
                                                  .clamp(1, 5),
                                          mainAxisExtent:
                                              100 +
                                              (MediaQuery.textScalerOf(
                                                                context,
                                                              ).scale(14) /
                                                              14 -
                                                          1)
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
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                  );
                          },
                        ),
                ),
              ],
            );
          }),
        ),
      ],
    ),
  );
}
