import 'package:flutter/material.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.scroll = true,
    this.maxContentWidth = 1200,
  });
  final String title;
  final Widget? leading;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxContentWidth),
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 600;
          final padding = compact ? 16.0 : 24.0;
          final wrapActions =
              actions.isNotEmpty &&
              ((box.maxWidth < 500) ||
                  MediaQuery.textScalerOf(context).scale(14) > 19);
          final pageLeading =
              leading ?? AppPageLeading.maybeOf(context)?.leading;
          final headingContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
          final heading = pageLeading == null
              ? headingContent
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pageLeading,
                    const SizedBox(width: 2),
                    Expanded(child: headingContent),
                  ],
                );
          final controls = Wrap(spacing: 6, runSpacing: 4, children: actions);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  compact ? 18 : 24,
                  padding,
                  20,
                ),
                child: wrapActions
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: 12),
                          controls,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          if (actions.isNotEmpty) ...[
                            const SizedBox(width: 16),
                            controls,
                          ],
                        ],
                      ),
              ),
              Expanded(
                child: scroll
                    ? SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          padding,
                          0,
                          padding,
                          padding,
                        ),
                        child: child,
                      )
                    : Padding(
                        padding: EdgeInsets.fromLTRB(
                          padding,
                          0,
                          padding,
                          padding,
                        ),
                        child: child,
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Supplies a leading control to a nested [AppPage] without coupling feature
/// pages to the route that opened them.
class AppPageLeading extends InheritedWidget {
  const AppPageLeading({
    super.key,
    required this.leading,
    required super.child,
  });

  final Widget leading;

  static AppPageLeading? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPageLeading>();

  @override
  bool updateShouldNotify(AppPageLeading oldWidget) =>
      leading != oldWidget.leading;
}
