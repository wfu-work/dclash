import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../services/core_service.dart';
import '../../widgets/app_navigation_item.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/app_workspace_surface.dart';
import '../dashboard/dashboard_view.dart';
import '../profiles/profiles_view.dart';
import '../proxies/proxies_view.dart';
import '../tools/tools_view.dart';
import 'workspace_controller.dart';

class WorkspaceView extends GetView<WorkspaceController> {
  const WorkspaceView({super.key});
  static const labels = ['dashboard', 'proxies', 'profiles', 'tools'];
  static const icons = [
    AppIcons.dashboard,
    AppIcons.globe,
    // Keep the workspace navigation on the same open Lucide outline family.
    // Layers communicates assembled proxy configuration more clearly than a
    // document glyph, while terminal gives the tools area a distinct,
    // technical entry point without the heavier briefcase silhouette.
    AppIcons.layers,
    AppIcons.terminal,
  ];
  static const dockLabels = [...labels, 'settings'];
  static const dockIcons = [...icons, AppIcons.settings];
  static const pages = <Widget>[
    DashboardView(),
    ProxiesView(),
    ProfilesView(),
    ToolsView(),
  ];

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (var i = 0; i < labels.length; i++) ...{
        SingleActivator(
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
          ][i],
          meta: true,
        ): () =>
            controller.select(i),
        SingleActivator(
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
          ][i],
          control: true,
        ): () =>
            controller.select(i),
      },
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, box) {
            final desktop = box.maxWidth >= 840;
            return SafeArea(
              // On desktop the main surface is allowed to paint beneath the
              // transparent macOS titlebar. The sidebar keeps its own safe
              // inset so the traffic lights remain unobstructed.
              top: !desktop,
              bottom: false,
              child: ColoredBox(
                color: desktop
                    ? Theme.of(context).extension<AppSurfaces>()!.window
                    : Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    if (const bool.fromEnvironment('DC_PREVIEW'))
                      Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 5,
                          horizontal: 16,
                        ),
                        child: Text(
                          'preview'.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (desktop)
                            SafeArea(
                              top: true,
                              bottom: false,
                              child: _sidebar(context),
                            ),
                          Expanded(
                            child: Obx(
                              () => AppWorkspaceSurface(
                                desktop: desktop,
                                child: IndexedStack(
                                  index: controller.index.value,
                                  children: [
                                    for (var i = 0; i < pages.length; i++)
                                      controller.visited.contains(i)
                                          ? pages[i]
                                          : const SizedBox.shrink(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!desktop) _dock(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _sidebar(BuildContext context) => Container(
    width: 208,
    color: Theme.of(context).extension<AppSurfaces>()!.sidebar,
    padding: const EdgeInsets.fromLTRB(12, 28, 12, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const AppLogo(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'brandName'.tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'dclash',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Obx(
          () => Column(
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AppNavigationItem(
                    label: labels[i].tr,
                    icon: icons[i],
                    selected: controller.index.value == i,
                    onTap: () => controller.select(i),
                  ),
                ),
            ],
          ),
        ),
        const Spacer(),
        Obx(() {
          final core = Get.find<CoreService>();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: core.running
                        ? const Color(0xFF239464)
                        : Theme.of(context).colorScheme.outline,
                  ),
                  child: const SizedBox.square(dimension: 6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    core.status.value.name.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(),
        const SizedBox(height: 8),
        AppNavigationItem(
          label: 'settings'.tr,
          icon: AppIcons.settings,
          selected: false,
          onTap: () => controller.openSettings(context),
        ),
      ],
    ),
  );

  Widget _dock(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: .5,
        ),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Obx(
          () => Row(
            children: [
              for (var i = 0; i < dockLabels.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AppNavigationItem(
                    label: dockLabels[i].tr,
                    icon: dockIcons[i],
                    selected: i < labels.length && controller.index.value == i,
                    vertical: true,
                    onTap: () => i < labels.length
                        ? controller.select(i)
                        : controller.openSettings(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
