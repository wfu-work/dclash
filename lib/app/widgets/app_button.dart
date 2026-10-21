import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';
import 'app_icon.dart';

/// The shared high contrast action button used for page-level primary actions.
///
/// It intentionally uses a black/white contrast pair instead of the accent
/// color so the same action remains legible across all theme colors. Set
/// [interactive] to false when the button is used as the visual child of a
/// popup trigger.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.interactive = true,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool interactive;
  final bool expand;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.black : Colors.white;
    final background = dark ? Colors.white : Colors.black;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: foreground);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          AppIcon(icon!, size: 18, color: foreground),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
      ],
    );

    final child = interactive
        ? SizedBox(
            width: expand ? double.infinity : null,
            height: 40,
            child: FilledButton(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                backgroundColor: background,
                foregroundColor: foreground,
                disabledBackgroundColor: colors.onSurface.withValues(
                  alpha: .12,
                ),
                disabledForegroundColor: colors.onSurfaceVariant,
                shape: AppShapes.control,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: content,
            ),
          )
        : DecoratedBox(
            decoration: ShapeDecoration(
              color: background,
              shape: AppShapes.control,
            ),
            child: SizedBox(
              width: expand ? double.infinity : null,
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: content),
              ),
            ),
          );

    final result = Semantics(
      button: true,
      enabled: interactive && onPressed != null && !busy,
      label: label,
      child: child,
    );
    return tooltip == null ? result : Tooltip(message: tooltip!, child: result);
  }
}
