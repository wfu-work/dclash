import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../platform/installed_apps.dart';
import '../../../widgets/app_widgets.dart';
import 'installed_apps_controller.dart';

class InstalledAppsView extends GetView<InstalledAppsController> {
  const InstalledAppsView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Obx(() {
        final entries = controller.visibleApps;
        final saving = controller.saving.value;
        return AppPage(
          title: 'installedApps'.tr,
          subtitle: 'appsSelectedCount'.trParams({
            'count': '${controller.selected.length}',
          }),
          scroll: false,
          leading: IconButton(
            tooltip: 'back'.tr,
            onPressed: saving ? null : () => Navigator.pop(context),
            icon: const AppIcon(AppIcons.arrowLeft),
          ),
          actions: [
            IconButton.filled(
              tooltip: 'save'.tr,
              onPressed: saving
                  ? null
                  : () async {
                      if (await controller.save() && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              icon: const AppIcon(AppIcons.check),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSearchField(onChanged: controller.query.call),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text('appsShowSystem'.tr),
                    selected: controller.showSystem.value,
                    onSelected: controller.showSystem.call,
                  ),
                  FilterChip(
                    label: Text('appsInternetOnly'.tr),
                    selected: controller.internetOnly.value,
                    onSelected: controller.internetOnly.call,
                  ),
                  FilterChip(
                    label: Text('appsSelectedOnly'.tr),
                    selected: controller.selectedOnly.value,
                    onSelected: controller.selectedOnly.call,
                  ),
                ],
              ),
              if (!controller.permissionGranted.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('appsPermissionHint'.tr),
                      TextButton.icon(
                        onPressed: controller.loading.value
                            ? null
                            : () => controller.load(requestPermission: true),
                        icon: const AppIcon(AppIcons.settings),
                        label: Text('appsGrantPermission'.tr),
                      ),
                    ],
                  ),
                ),
              if (controller.error.value != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.error.value!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.loading.value
                            ? null
                            : controller.load,
                        child: Text('retry'.tr),
                      ),
                    ],
                  ),
                ),
              if (controller.loading.value || saving)
                const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty && !controller.loading.value
                    ? AppEmpty(
                        icon: AppIcons.apps,
                        title: 'appsNoResults'.tr,
                        message: 'appsNoResultsHint'.tr,
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final app = entries[index];
                          return CheckboxListTile(
                            key: ValueKey(app.packageName),
                            secondary: _AppIcon(
                              app: app,
                              catalog: controller.catalog,
                            ),
                            title: Text(
                              app.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              app.installed
                                  ? app.packageName
                                  : '${app.packageName}\n${'appsNotInstalled'.tr}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            value: controller.selected.contains(
                              app.packageName,
                            ),
                            onChanged: saving
                                ? null
                                : (value) => controller.toggle(
                                    app.packageName,
                                    value == true,
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      }),
    ),
  );
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.app, required this.catalog});
  final InstalledApp app;
  final InstalledApps catalog;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  late final _path = widget.app.installed
      ? widget.catalog.icon(widget.app.packageName)
      : Future<String?>.value();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 36,
    child: FutureBuilder<String?>(
      future: _path,
      builder: (_, snapshot) => snapshot.data == null
          ? const AppIcon(AppIcons.android)
          : Image.file(
              File(snapshot.data!),
              fit: BoxFit.contain,
              cacheWidth: 96,
              cacheHeight: 96,
              errorBuilder: (_, _, _) => const AppIcon(AppIcons.android),
            ),
    ),
  );
}
