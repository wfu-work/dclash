import 'package:flutter/material.dart';

abstract final class AppTypography {
  static TextTheme resolve(Color foreground, Color secondary) {
    TextStyle style(
      double size,
      FontWeight weight,
      double height, {
      double letterSpacing = 0,
      Color? color,
    }) => TextStyle(
      color: color ?? foreground,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );

    return TextTheme(
      displayLarge: style(32, FontWeight.w600, 1.18, letterSpacing: -.4),
      displayMedium: style(28, FontWeight.w600, 1.2, letterSpacing: -.3),
      displaySmall: style(26, FontWeight.w600, 1.25, letterSpacing: -.2),
      headlineLarge: style(28, FontWeight.w600, 1.26, letterSpacing: -.2),
      headlineMedium: style(26, FontWeight.w600, 1.3, letterSpacing: -.1),
      headlineSmall: style(24, FontWeight.w600, 1.3),
      titleLarge: style(18, FontWeight.w500, 1.4),
      titleMedium: style(16, FontWeight.w500, 1.4),
      titleSmall: style(14, FontWeight.w500, 1.4),
      bodyLarge: style(15, FontWeight.w400, 1.5),
      bodyMedium: style(14, FontWeight.w400, 1.5),
      bodySmall: style(13, FontWeight.w400, 1.45, color: secondary),
      labelLarge: style(14, FontWeight.w500, 1.3),
      labelMedium: style(13, FontWeight.w400, 1.3),
      labelSmall: style(12, FontWeight.w400, 1.25, color: secondary),
    );
  }
}
