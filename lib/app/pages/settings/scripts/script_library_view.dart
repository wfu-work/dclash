import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../domains/script_library.dart';
import '../../../../services/script_library_service.dart';
import '../../../widgets/app_widgets.dart';
import 'script_editor_dialog.dart';

class ScriptLibraryView extends GetView<ScriptLibraryService> {
  const ScriptLibraryView({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
    final scripts = controller.scripts.toList();
    final busy = controller.busy.value;
    final error = controller.error.value;
    return Scaffold(
      body: SafeArea(
        child: AppPage(
          title: 'scriptLibrary'.tr,
          subtitle: 'scriptLibraryHelp'.tr,
          scroll: false,
          actions: [
            PopupMenuButton<String>(
              tooltip: 'scriptAdd'.tr,
              enabled: !busy && error == null,
              icon: const AppIcon(AppIcons.add),
              onSelected: (value) =>
                  value == 'local' ? _edit(context) : _import(context),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'local', child: Text('scriptCreate'.tr)),
                PopupMenuItem(value: 'remote', child: Text('scriptImport'.tr)),
              ],
            ),
            IconButton(
              tooltip: 'back'.tr,
              onPressed: () => Navigator.pop(context),
              icon: const AppIcon(AppIcons.close),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Expanded(child: _invalid(context, error, busy))
              else if (scripts.isEmpty)
                Expanded(
                  child: AppEmpty(
                    icon: AppIcons.code,
                    title: 'scriptEmpty'.tr,
                    message: 'scriptEmptyHelp'.tr,
                    action: FilledButton.icon(
                      onPressed: busy ? null : () => _edit(context),
                      icon: const AppIcon(AppIcons.add),
                      label: Text('scriptCreate'.tr),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 12),
                    itemCount: scripts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => _script(
                      context,
                      scripts[index],
                      index,
                      scripts.length,
                      busy,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  });

  Widget _script(
    BuildContext context,
    LibraryScript item,
    int index,
    int count,
    bool busy,
  ) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${index + 1}. ${item.name}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Semantics(
              label: 'scriptEnabled'.tr,
              child: AppSwitch(
                value: item.enabled,
                onChanged: busy
                    ? null
                    : (value) => _enable(context, item, value),
              ),
            ),
          ],
        ),
        Text(
          item.url ?? 'scriptLocal'.tr,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              tooltip: 'scriptMoveUp'.tr,
              onPressed: busy || index == 0
                  ? null
                  : () => _run(context, () => controller.move(item.id, -1)),
              icon: const AppIcon(AppIcons.arrowUp),
            ),
            IconButton(
              tooltip: 'scriptMoveDown'.tr,
              onPressed: busy || index == count - 1
                  ? null
                  : () => _run(context, () => controller.move(item.id, 1)),
              icon: const AppIcon(AppIcons.arrowDown),
            ),
            if (item.remote)
              IconButton(
                tooltip: 'scriptRefresh'.tr,
                onPressed: busy
                    ? null
                    : () => _run(context, () async {
                        await controller.refreshRemote(item.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('scriptRefreshed'.tr)),
                          );
                        }
                      }),
                icon: const AppIcon(AppIcons.refresh),
              ),
            IconButton(
              tooltip: 'scriptEdit'.tr,
              onPressed: busy ? null : () => _edit(context, item),
              icon: const AppIcon(AppIcons.edit),
            ),
            IconButton(
              tooltip: 'scriptDelete'.tr,
              onPressed: busy ? null : () => _remove(context, item),
              icon: const AppIcon(AppIcons.delete),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _invalid(BuildContext context, String error, bool busy) =>
      SingleChildScrollView(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'scriptInvalidData'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('scriptInvalidDataHelp'.tr),
              const SizedBox(height: 12),
              SelectableText(error),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _run(
                      context,
                      () => Clipboard.setData(
                        ClipboardData(text: controller.raw),
                      ),
                    ),
                    icon: const AppIcon(AppIcons.copy),
                    label: Text('scriptCopyRaw'.tr),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : () => _reset(context),
                    icon: const AppIcon(AppIcons.reset),
                    label: Text('scriptReset'.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _edit(BuildContext context, [LibraryScript? item]) async {
    final draft = await showDialog<ScriptDraft>(
      context: context,
      builder: (_) => ScriptEditorDialog(script: item),
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      () => item == null
          ? controller.createLocal(draft.name, draft.content)
          : controller.save(item.id, draft.name, draft.content),
    );
  }

  Future<void> _import(BuildContext context) async {
    final draft = await showDialog<RemoteScriptDraft>(
      context: context,
      builder: (_) => const RemoteScriptDialog(),
    );
    if (draft == null || !context.mounted) return;
    await _run(context, () => controller.importRemote(draft.name, draft.url));
  }

  Future<void> _enable(
    BuildContext context,
    LibraryScript item,
    bool enabled,
  ) async {
    if (enabled &&
        !await AppDialogs.confirm(
          context,
          title: 'scriptEnabled'.tr,
          message: 'scriptEnableConfirm'.trParams({'name': item.name}),
        )) {
      return;
    }
    if (!context.mounted) return;
    await _run(context, () => controller.setEnabled(item.id, enabled));
  }

  Future<void> _remove(BuildContext context, LibraryScript item) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'scriptDelete'.tr,
      message: 'scriptDeleteConfirm'.trParams({'name': item.name}),
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, () => controller.remove(item.id));
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'scriptReset'.tr,
      message: 'scriptResetConfirm'.tr,
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, controller.reset);
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}
