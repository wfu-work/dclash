import 'package:dclash_flutter/app/pages/dashboard/dashboard_controller.dart';
import 'package:dclash_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:dclash_flutter/app/pages/proxies/proxies_controller.dart';
import 'package:dclash_flutter/app/pages/settings/settings_controller.dart';
import 'package:dclash_flutter/app/pages/workspace/workspace_binding.dart';
import 'package:dclash_flutter/configs/app_services.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  test(
    'workspace binding uses the explicit composition root services',
    () async {
      Get.testMode = true;
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      final profiles = ProfileService();
      final core = CoreService(profiles, settings, preview: true);
      final services = AppServices(
        settings: settings,
        profiles: profiles,
        core: core,
      );

      WorkspaceBinding(services).dependencies();

      expect(Get.find<DashboardController>().core, same(core));
      expect(Get.find<DashboardController>().profiles, same(profiles));
      expect(Get.find<SettingsController>().settings, same(settings));
      expect(Get.find<SettingsController>().core, same(core));
      expect(Get.find<ProfilesController>().profiles, same(profiles));
      expect(Get.find<ProfilesController>().core, same(core));
      expect(Get.find<ProxiesController>().core, same(core));
      expect(Get.find<ProxiesController>().settings, same(settings));
    },
  );
}
