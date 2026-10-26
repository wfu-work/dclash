import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import 'profiles_controller.dart';
import 'profiles_dependencies.dart';

class ProfilesBinding extends Bindings {
  ProfilesBinding([this.services]);
  final AppServices? services;

  @override
  void dependencies() {
    final dependencies = services == null
        ? ProfilesDependencies.fromGetX()
        : ProfilesDependencies.fromAppServices(services!);
    if (!Get.isRegistered<ProfilesController>()) {
      Get.lazyPut(
        () => ProfilesController(dependencies.profiles, dependencies.core),
      );
    }
  }
}
