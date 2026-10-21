import 'package:get/get.dart';

import '../pages/workspace/workspace_binding.dart';
import '../pages/workspace/workspace_view.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.workspace,
      page: () => const WorkspaceView(),
      binding: WorkspaceBinding(),
    ),
  ];
}
