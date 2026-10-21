import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_icon.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({super.key, required this.onChanged, this.hint});
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint ?? 'search'.tr,
      prefixIcon: const AppIcon(AppIcons.search, size: 20),
      isDense: true,
    ),
  );
}
