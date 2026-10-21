import 'package:flutter/material.dart';

import 'app_icon.dart';

class AppCheckedMenuItem<T> extends PopupMenuItem<T> {
  AppCheckedMenuItem({
    super.key,
    super.value,
    super.enabled,
    required bool checked,
    required Widget child,
  }) : super(
         child: Semantics(
           checked: checked,
           child: Row(
             children: [
               Expanded(child: child),
               const SizedBox(width: 16),
               if (checked)
                 const AppIcon(AppIcons.check, size: 16)
               else
                 const SizedBox.square(dimension: 16),
             ],
           ),
         ),
       );
}
