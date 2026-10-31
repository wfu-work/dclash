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

  static const _gridPadding = EdgeInsets.all(18);
  static const _nameMaxLines = 2;
  static const _protocolGap = 7.0;
  static const _protocolPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 3,
  );

  static double gridMainAxisExtent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    double textHeight(TextStyle? style, int lines) {
      final painter = TextPainter(
        text: TextSpan(
          text: List.filled(lines, '国Ag').join('\n'),
          style: style,
        ),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Reserve two name lines and the padded badge, with room for font rounding.
    return (_gridPadding.vertical +
            textHeight(
              textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
              _nameMaxLines,
            ) +
            _protocolGap +
            _protocolPadding.vertical +
            textHeight(textTheme.labelSmall, 1) +
            8)
        .ceilToDouble();
  }

  static double compactMainAxisExtent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    double textHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return (const EdgeInsets.all(14).vertical +
            textHeight(
              textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
            ) +
            _protocolGap +
            _protocolPadding.vertical +
            textHeight(textTheme.labelSmall) +
            8)
        .ceilToDouble();
  }

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
          padding: compact ? const EdgeInsets.all(14) : _gridPadding,
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
                      maxLines: compact ? 1 : _nameMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: _protocolGap),
                    Semantics(
                      label: '${'proxyProtocol'.tr}: ${node.type}',
                      child: DecoratedBox(
                        key: ValueKey('proxyProtocol_${node.name}'),
                        decoration: ShapeDecoration(
                          color: selected
                              ? colors.primary.withValues(alpha: .10)
                              : colors.surfaceContainerLow,
                          shape: AppShapes.pill,
                        ),
                        child: Padding(
                          padding: _protocolPadding,
                          child: Text(
                            '${'proxyProtocol'.tr} · ${node.type}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
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
