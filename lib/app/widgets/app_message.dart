import 'package:flutter/material.dart';

import 'app_icon.dart';

/// The tone used by a transient application message.
enum AppMessageTone { info, success, warning, error }

/// Shared content and presentation for short-lived feedback messages.
///
/// Messages are shown through the nearest [ScaffoldMessenger], so the same
/// presentation works from pages, dialogs, and nested desktop layouts. The
/// visual treatment itself comes from [SnackBarThemeData], which keeps it in
/// sync with the codexc-inspired light and dark themes.
class AppMessage extends StatelessWidget {
  const AppMessage({
    super.key,
    required this.message,
    this.tone = AppMessageTone.info,
    this.showIcon = false,
  });

  final String message;
  final AppMessageTone tone;
  final bool showIcon;

  /// Shows one message and replaces an older message that is still visible.
  static void show(
    BuildContext context,
    String message, {
    AppMessageTone tone = AppMessageTone.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    bool showIcon = false,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AppMessage(message: text, tone: tone, showIcon: showIcon),
          duration: duration,
          action: action,
        ),
      );
  }

  static void info(BuildContext context, String message) =>
      show(context, message, tone: AppMessageTone.info);

  static void success(BuildContext context, String message) =>
      show(context, message, tone: AppMessageTone.success);

  static void warning(BuildContext context, String message) =>
      show(context, message, tone: AppMessageTone.warning);

  static void error(BuildContext context, Object error) =>
      show(context, formatError(error), tone: AppMessageTone.error);

  /// Removes the exception class prefix that is useful in logs but noisy in
  /// user-facing feedback.
  static String formatError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final text = Text(message, maxLines: 3, overflow: TextOverflow.ellipsis);
    if (!showIcon) return text;

    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (tone) {
      AppMessageTone.info => (AppIcons.info, colors.primary),
      AppMessageTone.success => (AppIcons.checkCircle, colors.primary),
      AppMessageTone.warning => (AppIcons.info, colors.secondary),
      AppMessageTone.error => (AppIcons.error, colors.error),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Flexible(child: text),
      ],
    );
  }
}
