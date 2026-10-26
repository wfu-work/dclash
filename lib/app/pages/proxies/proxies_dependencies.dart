import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../services/core_service.dart';
import '../../../services/settings_service.dart';

/// Services used by the proxies feature.
class ProxiesDependencies {
  const ProxiesDependencies({required this.core, required this.settings});

  factory ProxiesDependencies.fromAppServices(AppServices services) =>
      ProxiesDependencies(core: services.core, settings: services.settings);

  /// Compatibility path for standalone routes and legacy tests.
  factory ProxiesDependencies.fromGetX() => ProxiesDependencies(
    core: Get.find<CoreService>(),
    settings: Get.find<SettingsService>(),
  );

  final CoreService core;
  final SettingsService settings;
}
