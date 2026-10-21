import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? 'assets/brand/app_icon_dark.png' : 'assets/brand/app_icon.png',
      width: size,
      height: size,
      semanticLabel: 'dclash',
      filterQuality: FilterQuality.medium,
    );
  }
}
