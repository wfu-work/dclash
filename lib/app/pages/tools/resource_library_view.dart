import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/resource_item.dart';
import '../../widgets/app_widgets.dart';
import 'resource_library_controller.dart';

class ResourceLibraryView extends GetView<ResourceLibraryController> {
  const ResourceLibraryView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'resourceLibrary'.tr,
        subtitle: 'resourceLibrarySubtitle'.tr,
        actions: [
          FilledButton.icon(
            onPressed: () => _edit(context),
            icon: const AppIcon(AppIcons.add, size: 18),
            label: Text('resourceAdd'.tr),
          ),
        ],
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSearchField(
                hint: 'resourceSearch'.tr,
                onChanged: controller.setQuery,
              ),
              const SizedBox(height: 12),
              _KindFilters(controller: controller),
              const SizedBox(height: 16),
              if (controller.visibleItems.isEmpty)
                AppEmpty(
                  icon: AppIcons.layers,
                  title:
                      (controller.query.value.trim().isEmpty
                              ? 'resourceEmpty'
                              : 'resourceNoResults')
                          .tr,
                  message: controller.query.value.trim().isEmpty
                      ? 'resourceEmptyHint'.tr
                      : null,
                  action: controller.query.value.trim().isEmpty
                      ? OutlinedButton.icon(
                          onPressed: () => _edit(context),
                          icon: const AppIcon(AppIcons.add, size: 17),
                          label: Text('resourceAdd'.tr),
                        )
                      : null,
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < controller.visibleItems.length;
                        index++
                      ) ...[
                        _ResourceRow(
                          item: controller.visibleItems[index],
                          onEdit: () =>
                              _edit(context, controller.visibleItems[index]),
                          onRefresh: () =>
                              _refresh(context, controller.visibleItems[index]),
                          onToggle: () =>
                              _toggle(context, controller.visibleItems[index]),
                          onRemove: () =>
                              _remove(context, controller.visibleItems[index]),
                        ),
                        if (index + 1 < controller.visibleItems.length)
                          const Divider(height: 1, indent: 68),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _edit(BuildContext context, [ResourceItem? item]) async {
    final draft = await showDialog<_ResourceDraft>(
      context: context,
      builder: (_) =>
          _ResourceEditorDialog(item: item, pickFile: controller.pickFile),
    );
    if (draft == null || !context.mounted) return;
    try {
      await controller.saveItem(
        existing: item,
        name: draft.name,
        kind: draft.kind,
        sourceType: draft.sourceType,
        source: draft.source,
      );
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _refresh(BuildContext context, ResourceItem item) async {
    try {
      await controller.refreshItem(item);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _toggle(BuildContext context, ResourceItem item) async {
    try {
      await controller.toggleItem(item);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _remove(BuildContext context, ResourceItem item) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'resourceDelete'.tr,
      message: 'resourceDeleteConfirm'.trParams({'name': item.name}),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await controller.removeItem(item);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}

class _KindFilters extends StatelessWidget {
  const _KindFilters({required this.controller});
  final ResourceLibraryController controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        ChoiceChip(
          label: Text('resourceAll'.tr),
          selected: controller.selectedKind.value == null,
          onSelected: (_) => controller.setKind(null),
        ),
        for (final kind in ResourceKind.values) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(kind.translationKey.tr),
            selected: controller.selectedKind.value == kind,
            onSelected: (_) => controller.setKind(kind),
          ),
        ],
      ],
    ),
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.item,
    required this.onEdit,
    required this.onRefresh,
    required this.onToggle,
    required this.onRemove,
  });
  final ResourceItem item;
  final VoidCallback onEdit, onRefresh, onToggle, onRemove;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    leading: AppIcon(_icon(item.kind), size: 21),
    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${item.kind.translationKey.tr} · ${item.sourceType.translationKey.tr}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPill(
          label: (item.enabled ? 'enabled' : 'disabled').tr,
          color: item.enabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        PopupMenuButton<String>(
          tooltip: 'more'.tr,
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'refresh':
                onRefresh();
              case 'toggle':
                onToggle();
              case 'remove':
                onRemove();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text('edit'.tr)),
            if (item.sourceType != ResourceSourceType.inline)
              PopupMenuItem(
                value: 'refresh',
                child: Text('resourceRefresh'.tr),
              ),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                (item.enabled ? 'resourceDisable' : 'resourceEnable').tr,
              ),
            ),
            PopupMenuItem(value: 'remove', child: Text('delete'.tr)),
          ],
        ),
      ],
    ),
  );

  static IconData _icon(ResourceKind kind) => switch (kind) {
    ResourceKind.proxy => AppIcons.server,
    ResourceKind.ruleProvider => AppIcons.rules,
    ResourceKind.regexFilter => AppIcons.filter,
    ResourceKind.iconSet => AppIcons.layers,
  };
}

class _ResourceDraft {
  const _ResourceDraft({
    required this.name,
    required this.kind,
    required this.sourceType,
    required this.source,
  });
  final String name, source;
  final ResourceKind kind;
  final ResourceSourceType sourceType;
}

class _ResourceEditorDialog extends StatefulWidget {
  const _ResourceEditorDialog({required this.item, required this.pickFile});
  final ResourceItem? item;
  final Future<String?> Function() pickFile;

  @override
  State<_ResourceEditorDialog> createState() => _ResourceEditorDialogState();
}

class _ResourceEditorDialogState extends State<_ResourceEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _source;
  late ResourceKind _kind;
  late ResourceSourceType _sourceType;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _source = TextEditingController(text: item?.source ?? '');
    _kind = item?.kind ?? ResourceKind.ruleProvider;
    _sourceType = item?.sourceType ?? ResourceSourceType.url;
  }

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text((widget.item == null ? 'resourceAdd' : 'resourceEdit').tr),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'resourceName'.tr),
            ),
            const SizedBox(height: 14),
            AppDropdownFormField<ResourceKind>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: 'resourceType'.tr),
              items: [
                for (final kind in ResourceKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(kind.translationKey.tr),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _kind = value);
              },
            ),
            const SizedBox(height: 14),
            AppDropdownFormField<ResourceSourceType>(
              initialValue: _sourceType,
              decoration: InputDecoration(labelText: 'resourceSourceType'.tr),
              items: [
                for (final type in ResourceSourceType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type.translationKey.tr),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sourceType = value);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _source,
              minLines: _sourceType == ResourceSourceType.inline ? 5 : 1,
              maxLines: _sourceType == ResourceSourceType.inline ? 12 : 3,
              decoration: InputDecoration(
                labelText: _sourceType == ResourceSourceType.inline
                    ? 'resourceContent'.tr
                    : 'resourceSource'.tr,
                hintText: _sourceType == ResourceSourceType.inline
                    ? 'resourceInlineHint'.tr
                    : null,
                suffixIcon: _sourceType == ResourceSourceType.file
                    ? IconButton(
                        tooltip: 'resourcePickFile'.tr,
                        onPressed: () async {
                          final path = await widget.pickFile();
                          if (path != null && mounted) _source.text = path;
                        },
                        icon: const AppIcon(AppIcons.fileOpen),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('cancel'.tr),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ResourceDraft(
            name: _name.text,
            kind: _kind,
            sourceType: _sourceType,
            source: _source.text,
          ),
        ),
        child: Text('save'.tr),
      ),
    ],
  );
}

extension on ResourceKind {
  String get translationKey => 'resourceKind_$wireName';
}

extension on ResourceSourceType {
  String get translationKey => 'resourceSource_$wireName';
}
