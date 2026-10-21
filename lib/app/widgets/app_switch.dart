import 'package:flutter/material.dart';

/// A compact switch used throughout dclash.
///
/// The native switch is scaled down to match the compact desktop controls in
/// codexc-flutter. Its hit target stays at 48 logical pixels so the control
/// remains easy to operate with a mouse, keyboard, or touch input.
class AppSwitch extends StatelessWidget {
  static const visualScale = .65;

  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.autofocus = false,
    this.focusNode,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final control = SwitchTheme(
      data: SwitchTheme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: EdgeInsets.zero,
      ),
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        autofocus: autofocus,
        focusNode: focusNode,
      ),
    );

    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: 48,
        child: Transform.scale(
          scale: visualScale,
          transformHitTests: false,
          child: control,
        ),
      ),
    );
  }
}
