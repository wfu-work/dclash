import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paints dclash beneath the macOS titlebar while keeping native controls
/// usable and the rest of the titlebar draggable.
class AppWindowFrame extends StatefulWidget {
  const AppWindowFrame({required this.child, super.key});

  final Widget child;

  static const titlebarHeight = 32.0;
  static const trafficLightInset = 80.0;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> {
  static const _channel = MethodChannel('cloudrift/windowChrome');
  Brightness? _brightness;

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Widget tests and previews do not have a native macOS window.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppWindowFrame.isMacOS) return;
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    _invoke('setAppearance', brightness == Brightness.dark);
  }

  Widget _dragRegion({
    required double left,
    required double right,
    required double height,
  }) => Positioned(
    top: 0,
    left: left,
    right: right,
    height: height,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _invoke('startDragging'),
        onDoubleTap: () => _invoke('zoom'),
        child: const SizedBox.expand(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!AppWindowFrame.isMacOS) return widget.child;

    final media = MediaQuery.of(context);
    final inset = math.max(media.padding.top, AppWindowFrame.titlebarHeight);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: inset),
        viewPadding: media.viewPadding.copyWith(top: inset),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // Keep the native traffic lights clickable while making the rest of
          // the transparent titlebar behave like a normal macOS titlebar.
          _dragRegion(
            left: AppWindowFrame.trafficLightInset,
            right: 0,
            height: inset,
          ),
        ],
      ),
    );
  }
}
