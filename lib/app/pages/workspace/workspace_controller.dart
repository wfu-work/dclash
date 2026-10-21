import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../settings/settings_view.dart';

class WorkspaceController extends GetxController {
  final index = 0.obs;
  final visited = <int>{0}.obs;

  void select(int value) {
    if (value < 0 || value > 4) return;
    visited.add(value);
    index.value = value;
  }

  void openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsView()));
  }
}
