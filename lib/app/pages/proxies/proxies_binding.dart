import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../../services/settings_service.dart';
import 'proxies_controller.dart';

class ProxiesBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ProxiesController>()) {
      Get.lazyPut(
        () => ProxiesController(
          Get.find<CoreService>(),
          Get.find<SettingsService>(),
        ),
      );
    }
  }
}
