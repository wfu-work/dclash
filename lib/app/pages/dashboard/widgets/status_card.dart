import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/core_status.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/connect_button.dart';
import '../dashboard_controller.dart';
import '../../workspace/workspace_controller.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final core = controller.core;
    final status = core.status.value;
    final active = core.running;
    final color = active
        ? const Color(0xFF23944D)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      'status'.tr,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    AppPill(
                      label: status.name.tr,
                      color: status == CoreStatus.failed
                          ? Theme.of(context).colorScheme.error
                          : color,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  active ? 'appTagline'.tr : 'brandName'.tr,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  core.error.value ??
                      (active
                          ? controller.profiles.active?.name ?? 'dclash'
                          : 'localMode'.tr),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: status == CoreStatus.failed
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'uptime'.tr,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  formatDuration(controller.elapsed.value),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (controller.profiles.active == null)
            TextButton.icon(
              onPressed: () => Get.find<WorkspaceController>().select(2),
              icon: const AppIcon(AppIcons.addLink, size: 18),
              label: Text('browseProfiles'.tr),
            )
          else
            ConnectButton(
              status: status,
              onPressed: () async {
                try {
                  await controller.toggle();
                } on Object catch (error) {
                  if (context.mounted) showAppError(context, error);
                }
              },
            ),
        ],
      ),
    );
  });
}
