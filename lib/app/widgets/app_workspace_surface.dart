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
        // On desktop, the rounded work area is the primary canvas. Give the
        // panel the bright elevated surface so it clearly separates from the
        // softer window and navigation backgrounds around it. Mobile keeps
        // its edge-to-edge page surface.
        color: desktop
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : Theme.of(context).colorScheme.surface,
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
