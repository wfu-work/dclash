import 'dart:async';

import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';
import 'app_icon.dart';

/// The tone used by a transient application message.
enum AppMessageTone { info, success, warning, error }

/// Shared content and presentation for short-lived feedback messages.
///
/// Messages are rendered in the root [Overlay], so they stay centered at the
/// top of the current window from pages, dialogs, and nested layouts.
class AppMessage extends StatelessWidget {
  const AppMessage({
    super.key,
    required this.message,
    this.tone = AppMessageTone.info,
    this.showIcon = true,
  });

  final String message;
  final AppMessageTone tone;
  final bool showIcon;

  static final _hosts = <OverlayState, _AppMessageHost>{};

  /// Shows one message and replaces an older message that is still visible.
  static void show(
    BuildContext context,
    String message, {
    AppMessageTone tone = AppMessageTone.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    bool showIcon = true,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final host = _hosts.putIfAbsent(overlay, () => _createHost(overlay));
    host.timer?.cancel();
    host.message.value = _AppMessageData(text, tone, action, showIcon);
    host.timer = Timer(duration, () => _dismiss(overlay));
  }

  static _AppMessageHost _createHost(OverlayState overlay) {
    final message = ValueNotifier<_AppMessageData?>(null);
    late final _AppMessageHost host;
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<_AppMessageData?>(
        valueListenable: message,
        builder: (_, data, _) => data == null
            ? const SizedBox.shrink()
            : _AppMessageOverlay(
                message: data.message,
                tone: data.tone,
                action: data.action,
                showIcon: data.showIcon,
                dismiss: () => _dismiss(overlay),
              ),
      ),
    );
    host = _AppMessageHost(message);
    entry.addListener(() {
      if (!entry.mounted && identical(_hosts[overlay], host)) {
        _hosts.remove(overlay);
        host.timer?.cancel();
        message.dispose();
      }
    });
    overlay.insert(entry);
    return host;
  }

  static void _dismiss(OverlayState overlay) {
    final host = _hosts[overlay];
    if (host == null) return;
    host.timer?.cancel();
    host.timer = null;
    host.message.value = null;
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
      AppMessageTone.warning => (AppIcons.warning, colors.secondary),
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

class _AppMessageOverlay extends StatelessWidget {
  const _AppMessageOverlay({
    required this.message,
    required this.tone,
    required this.action,
    required this.showIcon,
    required this.dismiss,
  });

  final String message;
  final AppMessageTone tone;
  final SnackBarAction? action;
  final bool showIcon;
  final VoidCallback dismiss;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final maxWidth = (media.size.width - 32).clamp(0.0, 560.0);
    return Positioned(
      top: media.padding.top + 16,
      left: 16,
      right: 16,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: message,
        child: IgnorePointer(
          ignoring: action == null,
          child: Align(
            alignment: Alignment.topCenter,
            child: IntrinsicWidth(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: colors.surfaceContainerHigh,
                  shape: AppShapes.control.copyWith(
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: AppMessage(
                            message: message,
                            tone: tone,
                            showIcon: showIcon,
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              dismiss();
                              action!.onPressed();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  action!.textColor ?? colors.primary,
                              backgroundColor: action!.backgroundColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 32),
                            ),
                            child: Text(action!.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppMessageData {
  const _AppMessageData(this.message, this.tone, this.action, this.showIcon);

  final String message;
  final AppMessageTone tone;
  final SnackBarAction? action;
  final bool showIcon;
}

class _AppMessageHost {
  _AppMessageHost(this.message);

  final ValueNotifier<_AppMessageData?> message;
  Timer? timer;
}
