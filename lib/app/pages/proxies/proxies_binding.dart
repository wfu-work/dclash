import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import 'proxies_controller.dart';
import 'proxies_dependencies.dart';

class ProxiesBinding extends Bindings {
  ProxiesBinding([this.services]);
  final AppServices? services;

  @override
  void dependencies() {
    final dependencies = services == null
        ? ProxiesDependencies.fromGetX()
        : ProxiesDependencies.fromAppServices(services!);
    if (!Get.isRegistered<ProxiesController>()) {
      Get.lazyPut(
        () => ProxiesController(dependencies.core, dependencies.settings),
      );
    }
  }
}
