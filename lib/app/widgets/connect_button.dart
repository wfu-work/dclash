import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domains/core_status.dart';
import 'app_icon.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.onPressed,
  });
  final CoreStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = status == CoreStatus.starting || status == CoreStatus.stopping;
    final running = status == CoreStatus.running;
    final enabled = onPressed != null && !busy;
    final foreground = !enabled
        ? colors.onSurfaceVariant
        : running
        ? colors.onPrimary
        : colors.primary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: (running ? 'stop' : 'start').tr,
      child: Tooltip(
        message: (running ? 'stop' : 'start').tr,
        child: SizedBox.square(
          dimension: 80,
          child: Material(
            color: !enabled
                ? colors.surfaceContainerHighest
                : running
                ? colors.primary
                : colors.primaryContainer,
            shape: CircleBorder(
              side: BorderSide(
                color: colors.primary.withValues(alpha: .16),
                width: .5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 26,
                        child: CircularProgressIndicator(
                          color: foreground,
                          strokeWidth: 1.5,
                        ),
                      )
                    : AppIcon(AppIcons.power, size: 32, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
