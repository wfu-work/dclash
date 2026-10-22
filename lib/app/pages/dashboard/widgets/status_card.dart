import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/core_status.dart';
import '../../../../services/core_service.dart';
import '../../../widgets/app_widgets.dart';
import '../dashboard_controller.dart';
import '../../workspace/workspace_controller.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.controller,
    required this.compact,
  });
  final DashboardController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => Obx(() {
    final core = controller.core;
    final status = core.status.value;
    final active = core.running;
    return AppCard(child: _layout(context, core, status, active));
  });

  Widget _layout(
    BuildContext context,
    CoreService core,
    CoreStatus status,
    bool active,
  ) {
    final details = _details(context, core, status, active);
    final trailing = controller.profiles.active == null
        ? TextButton.icon(
            onPressed: () => Get.find<WorkspaceController>().select(2),
            icon: const AppIcon(AppIcons.addLink, size: 18),
            label: Text('browseProfiles'.tr),
          )
        : _connectionControls(context, active: active, status: status);
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          details,
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: details),
        const SizedBox(width: 16),
        trailing,
      ],
    );
  }

  Widget _details(
    BuildContext context,
    CoreService core,
    CoreStatus status,
    bool active,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('status'.tr, style: Theme.of(context).textTheme.titleSmall),
          AppPill(
            label: status.name.tr,
            color: status == CoreStatus.failed
                ? Theme.of(context).colorScheme.error
                : active
                ? const Color(0xFF23944D)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        active ? 'appTagline'.tr : 'brandName'.tr,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 6),
      Text(
        active ? controller.profiles.active?.name ?? 'dclash' : 'localMode'.tr,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (core.error.value case final message?) ...[
        const SizedBox(height: 12),
        _errorPanel(context, message),
      ],
      const SizedBox(height: 22),
      Text('uptime'.tr, style: Theme.of(context).textTheme.labelSmall),
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
  );

  Widget _connectionControls(
    BuildContext context, {
    required bool active,
    required CoreStatus status,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConnectButton(
          status: status,
          onPressed:
              status == CoreStatus.starting || status == CoreStatus.stopping
              ? null
              : () => _toggle(context),
        ),
        const SizedBox(height: 10),
        AppPill(
          label: active ? 'stop'.tr : 'start'.tr,
          color: status == CoreStatus.failed
              ? colors.error
              : active
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _errorPanel(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.error, size: 18, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'connectionError'.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  message,
                  maxLines: 5,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    try {
      await controller.toggle();
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}
