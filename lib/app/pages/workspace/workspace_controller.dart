import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../settings/settings_dependencies.dart';
import '../settings/settings_view.dart';

class WorkspaceController extends GetxController {
  WorkspaceController([this.services]);
  final AppServices? services;
  final index = 0.obs;
  final visited = <int>{0}.obs;

  void select(int value) {
    if (value < 0 || value > 3) return;
    visited.add(value);
    index.value = value;
  }

  void openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsView(
          dependencies: services == null
              ? null
              : SettingsDependencies.fromAppServices(services!),
        ),
      ),
    );
  }
}
