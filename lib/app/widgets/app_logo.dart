import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconSize = size * .82;
    // The transparent source has a slightly taller upper contour. A small
    // optical correction keeps the mark centered inside the round badge.
    final opticalOffset = size * .012;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .7),
            width: .5,
          ),
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(0, opticalOffset),
            child: SizedBox.square(
              dimension: iconSize,
              child: Image.asset(
                isDark
                    ? 'assets/brand/app_logo_dark.png'
                    : 'assets/brand/app_logo.png',
                semanticLabel: 'dclash',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
