import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import 'config_schema.dart';

class ConfigFieldRow extends StatelessWidget {
  const ConfigFieldRow({
    super.key,
    required this.field,
    required this.value,
    required this.exists,
    required this.onEdit,
    required this.onValue,
    required this.onReset,
  });
  final ConfigField field;
  final dynamic value;
  final bool exists;
  final VoidCallback onEdit, onReset;
  final ValueChanged<dynamic> onValue;

  String get _summary {
    if (!exists) return 'cfgInherit'.tr;
    if (value is List) {
      final list = value as List;
      return list.isEmpty ? 'cfgEmptyList'.tr : list.join(', ');
    }
    return value?.toString() ?? 'null';
  }

  Widget _reset() => IconButton(
    tooltip: 'cfgResetField'.tr,
    visualDensity: VisualDensity.compact,
    onPressed: exists ? onReset : null,
    icon: const AppIcon(AppIcons.reset, size: 19),
  );

  @override
  Widget build(BuildContext context) {
    if (field.kind == ConfigFieldKind.toggle) {
      final selected = !exists
          ? 'inherit'
          : value is bool
          ? value.toString()
          : 'custom';
      return AppSettingsRow(
        title: field.label.tr,
        subtitle: field.key,
        trailing: AppDropdown<String>(
          icon: const AppIcon(AppIcons.chevronDown, size: 16),
          value: selected,
          items: [
            DropdownMenuItem(value: 'inherit', child: Text('cfgInherit'.tr)),
            DropdownMenuItem(value: 'true', child: Text('cfgOn'.tr)),
            DropdownMenuItem(value: 'false', child: Text('cfgOff'.tr)),
            if (selected == 'custom')
              DropdownMenuItem(
                value: 'custom',
                enabled: false,
                child: Text('cfgCustomYaml'.tr),
              ),
          ],
          onChanged: (next) {
            if (next == 'inherit') {
              onReset();
            } else if (next != null && next != 'custom') {
              onValue(next == 'true');
            }
          },
        ),
      );
    }
    if (field.kind == ConfigFieldKind.choice) {
      final raw = value.toString();
      final options = [
        ...field.options,
        if (exists && !field.options.contains(raw)) raw,
      ];
      final selected = exists ? options.indexOf(raw) + 1 : 0;
      return AppSettingsRow(
        title: field.label.tr,
        subtitle: field.key,
        trailing: AppDropdown<int>(
          icon: const AppIcon(AppIcons.chevronDown, size: 16),
          value: selected,
          items: [
            DropdownMenuItem(value: 0, child: Text('cfgInherit'.tr)),
            for (var index = 0; index < options.length; index++)
              DropdownMenuItem(
                value: index + 1,
                enabled: field.options.contains(options[index]),
                child: Text(
                  field.options.contains(options[index])
                      ? options[index].tr
                      : 'cfgCustomYaml'.tr,
                ),
              ),
          ],
          onChanged: (next) {
            if (next == 0) {
              onReset();
            } else if (next != null) {
              onValue(options[next - 1]);
            }
          },
        ),
      );
    }
    return AppSettingsRow(
      title: field.label.tr,
      subtitle: _summary,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_reset(), const AppIcon(AppIcons.edit, size: 18)],
      ),
    );
  }
}
