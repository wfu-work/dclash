import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import 'connections_controller.dart';
import 'widgets/connection_details.dart';
import 'widgets/connection_tile.dart';

class ConnectionsView extends GetView<ConnectionsController> {
  const ConnectionsView({super.key});
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
    title: 'featureConnections'.tr,
    subtitle: 'connectionSubtitle'.tr,
    scroll: false,
    actions: [
      Obx(
        () => OutlinedButton.icon(
          onPressed:
              controller.core.connections.isEmpty || controller.closingAll.value
              ? null
              : () async {
                  final confirmed = await AppDialogs.confirm(
                    context,
                    title: 'connectionCloseAll'.tr,
                    message: 'connectionCloseAllConfirm'.tr,
                  );
                  if (confirmed && context.mounted) {
                    await _run(context, controller.closeAll);
                  }
                },
          icon: const AppIcon(AppIcons.close, size: 18),
          label: Text('connectionCloseAll'.tr),
        ),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppSearchField(
                onChanged: (value) => controller.query.value = value,
                hint: 'connectionSearch'.tr,
              ),
            ),
            const SizedBox(width: 8),
            Obx(
              () => PopupMenuButton<String>(
                tooltip: 'featureSort'.tr,
                initialValue: controller.sort.value,
                onSelected: (value) => controller.sort.value = value,
                itemBuilder: (_) => ['recent', 'download', 'upload']
                    .map(
                      (value) => AppCheckedMenuItem(
                        value: value,
                        checked: controller.sort.value == value,
                        child: Text('connectionSort_$value'.tr),
                      ),
                    )
                    .toList(),
                icon: const AppIcon(AppIcons.sort),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Obx(
          () => Text(
            'connectionCount'.trParams({
              'count': '${controller.core.connections.length}',
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Obx(() {
            final list = controller.visibleConnections;
            if (list.isEmpty) {
              return AppEmpty(
                icon: AppIcons.network,
                title: controller.query.value.isNotEmpty
                    ? 'featureNoResults'.tr
                    : 'connectionEmpty'.tr,
                message: controller.core.running
                    ? 'connectionEmptyHint'.tr
                    : 'featureStartCore'.tr,
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final connection = list[index];
                return Obx(
                  () => ConnectionTile(
                    connection: connection,
                    busy: controller.closing.contains(connection.id),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => ConnectionDetails(connection: connection),
                    ),
                    onClose: () => _run(
                      context,
                      () => controller.closeConnection(connection.id),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    ),
  );
}
