import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';
import 'app_icon.dart';

class AppNavigationItem extends StatelessWidget {
  const AppNavigationItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.vertical = false,
  });

  final String label;
  final IconData icon;
  final bool selected, vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    final symbol = AppIcon(icon, size: vertical ? 22 : 18, color: foreground);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          (vertical ? theme.textTheme.labelSmall : theme.textTheme.bodyMedium)
              ?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: selected ? colors.surfaceContainerHighest : Colors.transparent,
          shape: AppShapes.control,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? 4 : 12,
                vertical: vertical ? 8 : 12,
              ),
              child: ExcludeSemantics(
                child: vertical
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [symbol, const SizedBox(height: 4), text],
                      )
                    : Row(
                        children: [
                          symbol,
                          const SizedBox(width: 12),
                          Expanded(child: text),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
