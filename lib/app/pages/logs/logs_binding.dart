import 'package:get/get.dart';

import '../../../services/core_service.dart';
import 'logs_controller.dart';

class LogsBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<LogsController>()) {
      Get.lazyPut(() => LogsController(Get.find<CoreService>()));
    }
  }
}
