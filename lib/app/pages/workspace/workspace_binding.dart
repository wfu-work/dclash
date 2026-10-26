import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../configs/app_services_bridge.dart';
import '../connections/connections_controller.dart';
import '../dashboard/dashboard_controller.dart';
import '../logs/logs_controller.dart';
import '../profiles/profiles_controller.dart';
import '../profiles/profiles_dependencies.dart';
import '../proxies/proxies_controller.dart';
import '../proxies/proxies_dependencies.dart';
import '../settings/settings_controller.dart';
import '../tools/resource_library_controller.dart';
import 'workspace_controller.dart';

class WorkspaceBinding extends Bindings {
  WorkspaceBinding([this.services]);
  final AppServices? services;

  @override
  void dependencies() {
    final dependencies = services ?? appServicesFromGetX();
    final profiles = ProfilesDependencies.fromAppServices(dependencies);
    final proxies = ProxiesDependencies.fromAppServices(dependencies);
    Get.lazyPut(() => WorkspaceController(services));
    Get.lazyPut(
      () => DashboardController(
        dependencies.core,
        dependencies.profiles,
        dependencies.settings,
      ),
    );
    Get.lazyPut(() => ProxiesController(proxies.core, proxies.settings));
    Get.lazyPut(() => ProfilesController(profiles.profiles, profiles.core));
    Get.lazyPut(() => ConnectionsController(dependencies.core));
    Get.lazyPut(() => LogsController(dependencies.core));
    Get.lazyPut(
      () => SettingsController(
        dependencies.settings,
        dependencies.core,
        shortcuts: dependencies.shortcuts,
      ),
    );
    final resources = dependencies.resources;
    if (resources != null) {
      Get.lazyPut(() => ResourceLibraryController(resources));
    }
  }
}
