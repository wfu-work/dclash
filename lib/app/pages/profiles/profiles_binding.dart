import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../../services/profile_service.dart';
import 'profiles_controller.dart';

class ProfilesBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ProfilesController>()) {
      Get.lazyPut(
        () => ProfilesController(
          Get.find<ProfileService>(),
          Get.find<CoreService>(),
        ),
      );
    }
  }
}
