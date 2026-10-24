import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../configs/theme/app_theme.dart';
import '../../../../domains/clash_connection.dart';
import '../../../widgets/app_widgets.dart';

class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.connection,
    required this.busy,
    required this.onTap,
    required this.onClose,
  });
  final ClashConnection connection;
  final bool busy;
  final VoidCallback onTap, onClose;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: AppShapes.card.copyWith(
        side: BorderSide(color: colors.outlineVariant, width: .5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final wide =
                  constraints.maxWidth >= 760 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 19;
              final identity = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AppIcon(
                      AppIcons.network,
                      size: 20,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connection.host.isEmpty
                              ? connection.destination
                              : connection.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${connection.network.toUpperCase()} · ${connection.source}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final traffic = Row(
                children: [
                  Expanded(
                    child: Text(
                      '↑ ${formatBytes(connection.upload)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '↓ ${formatBytes(connection.download)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              );
              final close = IconButton(
                tooltip: 'connectionClose'.tr,
                onPressed: busy ? null : onClose,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppIcons.close, size: 18),
              );
              final route = Text(
                connection.chains.reversed.join(' → '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              );
              return wide
                  ? Row(
                      children: [
                        Expanded(flex: 5, child: identity),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connection.rule,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium,
                              ),
                              const SizedBox(height: 5),
                              route,
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 224,
                          child: Row(
                            children: [
                              Expanded(child: traffic),
                              const SizedBox(width: 8),
                              close,
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: identity),
                            close,
                          ],
                        ),
                        const SizedBox(height: 12),
                        route,
                        const SizedBox(height: 12),
                        traffic,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}
