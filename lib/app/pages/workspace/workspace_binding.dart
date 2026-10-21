import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/resource_library_service.dart';
import '../../../services/settings_service.dart';
import '../connections/connections_controller.dart';
import '../dashboard/dashboard_controller.dart';
import '../logs/logs_controller.dart';
import '../profiles/profiles_controller.dart';
import '../proxies/proxies_controller.dart';
import '../settings/settings_controller.dart';
import '../tools/resource_library_controller.dart';
import 'workspace_controller.dart';

class WorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(WorkspaceController.new);
    Get.lazyPut(
      () => DashboardController(
        Get.find<CoreService>(),
        Get.find<ProfileService>(),
        Get.find<SettingsService>(),
      ),
    );
    Get.lazyPut(
      () => ProxiesController(
        Get.find<CoreService>(),
        Get.find<SettingsService>(),
      ),
    );
    Get.lazyPut(
      () => ProfilesController(
        Get.find<ProfileService>(),
        Get.find<CoreService>(),
      ),
    );
    Get.lazyPut(() => ConnectionsController(Get.find<CoreService>()));
    Get.lazyPut(() => LogsController(Get.find<CoreService>()));
    Get.lazyPut(
      () => SettingsController(
        Get.find<SettingsService>(),
        Get.find<CoreService>(),
      ),
    );
    Get.lazyPut(
      () => ResourceLibraryController(Get.find<ResourceLibraryService>()),
    );
  }
}
