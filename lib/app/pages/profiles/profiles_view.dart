import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../domains/clash_profile.dart';
import '../../../services/script_library_service.dart';
import '../../../storage/atomic_file.dart';
import '../../widgets/app_widgets.dart';
import 'profile_builder_view.dart';
import 'profiles_controller.dart';
import 'widgets/effective_config_view.dart';
import 'widgets/profile_card.dart';
import 'widgets/profile_editor.dart';
import 'widgets/profile_settings_dialog.dart';

class ProfilesView extends GetView<ProfilesController> {
  const ProfilesView({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _import(BuildContext context, String source) =>
      _run(context, () async {
        switch (source) {
          case 'url':
            final url = await AppDialogs.prompt(
              context,
              title: 'profileImportUrl'.tr,
              hint: 'https://example.com/subscribe',
            );
            if (url != null && url.trim().isNotEmpty) {
              await controller.importUrl(url.trim(), '');
            }
          case 'file':
            await controller.importFile();
          case 'clipboard':
            await controller.importClipboard();
          case 'custom':
            final draft = await showDialog<ProfileDraft>(
              context: context,
              builder: (_) => ProfileEditor(
                title: 'profileCreate'.tr,
                name: '',
                content:
                    'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n',
              ),
            );
            if (draft != null) {
              await controller.save(name: draft.name, content: draft.content);
            }
        }
      });

  Future<void> _action(
    BuildContext context,
    ClashProfile profile,
    String action,
  ) => _run(context, () async {
    switch (action) {
      case 'refresh':
        await controller.refreshProfile(profile);
      case 'duplicate':
        await controller.duplicate(profile);
      case 'builder':
        final content = await controller.profiles.readContent(profile);
        if (!context.mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ProfileBuilderView(
              profile: profile,
              initialContent: content,
              onSave: (content) => controller.save(
                id: profile.id,
                name: profile.name,
                content: content,
              ),
            ),
          ),
        );
      case 'edit':
        final content = await controller.profiles.readContent(profile);
        if (!context.mounted) return;
        final draft = await showDialog<ProfileDraft>(
          context: context,
          builder: (_) => ProfileEditor(
            title: 'profileAction_edit'.tr,
            name: profile.name,
            content: content,
          ),
        );
        if (draft != null) {
          await controller.save(
            id: profile.id,
            name: draft.name,
            content: draft.content,
          );
        }
      case 'script':
        final draft = await showDialog<ProfileDraft>(
          context: context,
          builder: (_) => ProfileEditor(
            title: 'profileAction_script'.tr,
            name: profile.name,
            content: profile.script,
            script: true,
          ),
        );
        if (draft != null) {
          await controller.updateProfile(
            profile.copyWith(script: draft.content),
          );
        }
      case 'settings':
        final updated = await showDialog<ClashProfile>(
          context: context,
          builder: (_) => ProfileSettingsDialog(
            profile: profile,
            scripts: Get.find<ScriptLibraryService>().scripts.toList(),
          ),
        );
        if (updated != null) await controller.updateProfile(updated);
      case 'effective':
        final effective = await controller.effectiveConfig(profile);
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => EffectiveConfigView(
            name: profile.name,
            displayContent: effective.displayContent,
            exportContent: effective.exportContent,
            onExport: () =>
                controller.exportEffectiveConfig(profile, effective),
          ),
        );
      case 'effectiveExport':
        final effective = await controller.effectiveConfig(profile);
        final exported = await controller.exportEffectiveConfig(
          profile,
          effective,
        );
        if (exported && context.mounted) {
          _message(context, 'featureExported'.tr);
        }
      case 'export':
        final content = await controller.profiles.readContent(profile);
        final bytes = Uint8List.fromList(utf8.encode(content));
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'profileAction_export'.tr,
          fileName:
              '${profile.name.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]'), '_')}.yaml',
          type: FileType.custom,
          allowedExtensions: ['yaml'],
          bytes: bytes,
        );
        if (path != null) {
          if (!path.startsWith('content:')) {
            await writePrivateAtomic(File(path), bytes);
          }
          if (context.mounted) _message(context, 'featureExported'.tr);
        }
      case 'copy':
        final content = await controller.profiles.readContent(profile);
        await Clipboard.setData(ClipboardData(text: content));
        if (context.mounted) _message(context, 'featureCopied'.tr);
      case 'remove':
        final active = controller.profiles.activeId.value == profile.id;
        final confirmed = await AppDialogs.confirm(
          context,
          title: 'profileAction_remove'.tr,
          message:
              (active && controller.coreActive
                      ? 'profileRemoveActiveConfirm'
                      : 'profileRemoveConfirm')
                  .trParams({'name': profile.name}),
        );
        if (confirmed) await controller.remove(profile);
    }
  });

  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'featureProfiles'.tr,
    subtitle: 'profileSubtitle'.tr,
    scroll: false,
    actions: [
      Obx(
        () => PopupMenuButton<String>(
          enabled: !controller.busy.contains('import'),
          tooltip: 'profileAdd'.tr,
          onSelected: (value) => _import(context, value),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'url',
              child: ListTile(
                leading: const AppIcon(AppIcons.link),
                title: Text('profileImportUrl'.tr),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'file',
              child: ListTile(
                leading: const AppIcon(AppIcons.fileOpen),
                title: Text('profileImportFile'.tr),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'clipboard',
              child: ListTile(
                leading: const AppIcon(AppIcons.copy),
                title: Text('profileImportClipboard'.tr),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'custom',
              child: ListTile(
                leading: const AppIcon(AppIcons.edit),
                title: Text('profileCreate'.tr),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: AppShapes.control,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.busy.contains('import'))
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                else
                  AppIcon(
                    AppIcons.add,
                    size: 19,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'profileAdd'.tr,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          onChanged: (value) => controller.query.value = value,
          hint: 'profileSearch'.tr,
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Obx(() {
            final profiles = controller.visibleProfiles;
            if (profiles.isEmpty) {
              return AppEmpty(
                icon: AppIcons.layers,
                title: controller.query.value.isNotEmpty
                    ? 'featureNoResults'.tr
                    : 'profileEmpty'.tr,
                message: 'profileEmptyHint'.tr,
                action: TextButton.icon(
                  onPressed: () => _import(context, 'url'),
                  icon: const AppIcon(AppIcons.addLink),
                  label: Text('profileImportUrl'.tr),
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                Widget card(BuildContext context, int index) {
                  final profile = profiles[index];
                  return Obx(
                    () => ProfileCard(
                      profile: profile,
                      active: controller.profiles.activeId.value == profile.id,
                      busy:
                          controller.busy.contains(profile.id) ||
                          controller.profiles.updating.contains(profile.id),
                      onActivate: () =>
                          _run(context, () => controller.activate(profile)),
                      onAction: (action) => _action(context, profile, action),
                    ),
                  );
                }

                if (constraints.maxWidth < 600 ||
                    MediaQuery.textScalerOf(context).scale(14) > 17.5) {
                  return ListView.separated(
                    itemCount: profiles.length,
                    itemBuilder: card,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                  );
                }
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: (constraints.maxWidth / 360).floor().clamp(
                      1,
                      4,
                    ),
                    mainAxisExtent: 270,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: profiles.length,
                  itemBuilder: card,
                );
              },
            );
          }),
        ),
      ],
    ),
  );
}
