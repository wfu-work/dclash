import 'package:get/get.dart';

import '../../../services/core_service.dart';
import 'connections_controller.dart';

class ConnectionsBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ConnectionsController>()) {
      Get.lazyPut(() => ConnectionsController(Get.find<CoreService>()));
    }
  }
}
