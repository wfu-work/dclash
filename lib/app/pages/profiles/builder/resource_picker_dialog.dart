import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/resource_item.dart';
import '../../../../services/resource_library_service.dart';
import '../../../widgets/app_widgets.dart';

class ResourcePickerDialog extends StatefulWidget {
  const ResourcePickerDialog({
    super.key,
    required this.service,
    required this.kind,
    required this.onSelected,
  });

  final ResourceLibraryService service;
  final ResourceKind kind;
  final ValueChanged<ResourceItem> onSelected;

  @override
  State<ResourcePickerDialog> createState() => _ResourcePickerDialogState();
}

class _ResourcePickerDialogState extends State<ResourcePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('builderUseResourceTitle'.tr),
    content: SizedBox(
      width: 460,
      height: 360,
      child: Obx(() {
        final needle = _query.trim().toLowerCase();
        final resources = widget.service.items
            .where((item) {
              return item.kind == widget.kind &&
                  item.enabled &&
                  (needle.isEmpty || item.name.toLowerCase().contains(needle));
            })
            .toList(growable: false);
        return Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'builderResourceSearch'.tr,
                prefixIcon: const AppIcon(AppIcons.search, size: 19),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: resources.isEmpty
                  ? AppEmpty(
                      icon: AppIcons.layers,
                      title: 'builderResourceEmpty'.tr,
                    )
                  : ListView.separated(
                      itemCount: resources.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = resources[index];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(item.sourceType.translationKey.tr),
                          leading: const AppIcon(AppIcons.layers, size: 20),
                          onTap: () {
                            widget.onSelected(item);
                            Navigator.pop(context, item);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      }),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('cancel'.tr),
      ),
    ],
  );
}

extension on ResourceSourceType {
  String get translationKey => 'resourceSource_$wireName';
}
