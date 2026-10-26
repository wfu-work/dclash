import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../services/core_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/resource_library_service.dart';
import '../../../services/script_library_service.dart';

/// Services owned by the profiles feature.
///
/// The profile editor can be used without the optional libraries (for example
/// in preview mode), so those integrations remain nullable at the boundary.
class ProfilesDependencies {
  const ProfilesDependencies({
    required this.profiles,
    required this.core,
    this.scripts,
    this.resources,
  });

  factory ProfilesDependencies.fromAppServices(AppServices services) =>
      ProfilesDependencies(
        profiles: services.profiles,
        core: services.core,
        scripts: services.scripts,
        resources: services.resources,
      );

  /// Compatibility path for standalone routes and legacy tests.
  factory ProfilesDependencies.fromGetX() => ProfilesDependencies(
    profiles: Get.find<ProfileService>(),
    core: Get.find<CoreService>(),
    scripts: _find<ScriptLibraryService>(),
    resources: _find<ResourceLibraryService>(),
  );

  final ProfileService profiles;
  final CoreService core;
  final ScriptLibraryService? scripts;
  final ResourceLibraryService? resources;
}

T? _find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
