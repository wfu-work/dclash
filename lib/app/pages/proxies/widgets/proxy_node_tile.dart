import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../configs/theme/app_theme.dart';
import '../../../../domains/proxy_group.dart';
import '../../../widgets/app_icon.dart';

class ProxyNodeTile extends StatelessWidget {
  const ProxyNodeTile({
    super.key,
    required this.node,
    required this.selected,
    required this.delay,
    required this.testing,
    required this.compact,
    required this.onSelect,
    required this.onTest,
  });

  final ProxyNode node;
  final bool selected, testing, compact;
  final int? delay;
  final VoidCallback? onSelect, onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unavailable = delay == null ? !node.alive : delay! < 0;
    final delayColor = unavailable
        ? colors.error
        : delay == null
        ? colors.onSurfaceVariant
        : delay! < 300
        ? const Color(0xff16876c)
        : delay! < 700
        ? const Color(0xffb37519)
        : colors.error;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
      shape: AppShapes.card.copyWith(
        side: BorderSide(
          color: selected
              ? colors.primary.withValues(alpha: .5)
              : colors.outlineVariant,
          width: .5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Row(
            children: [
              AppIcon(
                selected ? AppIcons.checkCircle : AppIcons.globe,
                size: 20,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      node.name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      node.type,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'proxyTestNode'.tr,
                child: InkWell(
                  onTap: onTest,
                  customBorder: AppShapes.control,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                    child: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            unavailable
                                ? 'proxyTimeout'.tr
                                : delay == null
                                ? '—'
                                : '$delay ms',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: delayColor,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
