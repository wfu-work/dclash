import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';

class AppWorkspaceSurface extends StatelessWidget {
  const AppWorkspaceSurface({
    required this.child,
    required this.desktop,
    super.key,
  });

  final Widget child;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: desktop
          ? const EdgeInsets.fromLTRB(0, 8, 8, 8)
          : EdgeInsets.zero,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: desktop
            ? AppShapes.workspace.copyWith(
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: .5,
                ),
              )
            : null,
        clipBehavior: desktop ? Clip.antiAlias : Clip.none,
        child: child,
      ),
    );
  }
}
