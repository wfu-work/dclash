import 'package:get/get.dart';

import '../../configs/app_services.dart';
import '../../configs/app_services_bridge.dart';
import '../pages/workspace/workspace_binding.dart';
import '../pages/workspace/workspace_view.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static List<GetPage> forServices(AppServices services) => [
    GetPage(
      name: AppRoutes.workspace,
      page: () => WorkspaceView(services: services),
      binding: WorkspaceBinding(services),
    ),
  ];

  /// Transitional getter for callers that still assemble services in GetX.
  static List<GetPage> get pages => forServices(appServicesFromGetX());
}
