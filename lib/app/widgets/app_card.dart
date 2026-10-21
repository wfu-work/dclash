import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: Theme.of(context).cardTheme.shape ?? AppShapes.card,
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      AppCard(padding: EdgeInsets.zero, child: child),
    ],
  );
}

class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effective = color ?? colors.onSurfaceVariant;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShapes.pill,
        color: color == null
            ? colors.surfaceContainerLow
            : effective.withValues(alpha: .09),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: effective),
        ),
      ),
    );
  }
}
