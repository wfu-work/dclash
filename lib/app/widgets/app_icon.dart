import 'package:flutter/material.dart';

import '../../configs/theme/app_icon_paths.dart';
import '../../configs/theme/app_icons.dart';

export '../../configs/theme/app_icons.dart';

/// Lucide vectors share the same theme and semantics contract as Flutter Icon.
class AppIcon extends Icon {
  const AppIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    super.blendMode,
    this.strokeWidth = 1.25,
  });

  /// Stroke width in the original 24-unit Lucide grid.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final geometry = AppIconPaths.resolve(icon);
    if (geometry == null) return super.build(context);
    final theme = IconTheme.of(context);
    final direction = textDirection ?? Directionality.of(context);
    final baseSize = size ?? theme.size ?? 20;
    final extent = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(baseSize)
        : baseSize;
    final foreground =
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final effectiveColor = foreground.withValues(
      alpha: foreground.a * (theme.opacity ?? 1),
    );
    return Semantics(
      label: semanticLabel,
      textDirection: direction,
      child: ExcludeSemantics(
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
            dimension: extent,
            child: CustomPaint(
              painter: _AppIconPainter(
                geometry,
                effectiveColor,
                strokeWidth,
                direction == TextDirection.rtl &&
                    (icon!.matchTextDirection ||
                        [
                          AppIcons.arrowLeft,
                          AppIcons.chevronLeft,
                          AppIcons.chevronRight,
                        ].contains(icon)),
                blendMode ?? BlendMode.srcOver,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter(
    this.geometry,
    this.color,
    this.strokeWidth,
    this.mirrored,
    this.blendMode,
  );

  final AppIconGeometry geometry;
  final Color color;
  final double strokeWidth;
  final bool mirrored;
  final BlendMode blendMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    if (mirrored) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..blendMode = blendMode;
    if (geometry.fill != null) canvas.drawPath(geometry.fill!, paint);
    canvas.drawPath(
      geometry.outline,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppIconPainter oldDelegate) =>
      geometry != oldDelegate.geometry ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      mirrored != oldDelegate.mirrored ||
      blendMode != oldDelegate.blendMode;
}
