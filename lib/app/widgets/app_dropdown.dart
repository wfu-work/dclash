import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Compact dropdown used by settings rows and other inline controls.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.icon,
    this.menuMaxHeight,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final Widget? icon;
  final double? menuMaxHeight;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      isDense: true,
      elevation: 3,
      style: theme.textTheme.bodyMedium,
      dropdownColor: theme.canvasColor,
      menuMaxHeight: menuMaxHeight ?? 320,
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(7),
      underline: const SizedBox.shrink(),
      icon: icon ?? const AppIcon(AppIcons.chevronDown, size: 16),
      iconEnabledColor: theme.colorScheme.onSurfaceVariant,
      iconDisabledColor: theme.colorScheme.onSurfaceVariant.withValues(
        alpha: .45,
      ),
      hint: hint,
    );
  }
}

/// Compact form dropdown with the same control and menu treatment as
/// [AppDropdown].
class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({
    super.key,
    required this.items,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
    this.icon,
    this.menuMaxHeight,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final InputDecoration decoration;
  final bool isExpanded;
  final Widget? icon;
  final double? menuMaxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: isExpanded,
      isDense: true,
      elevation: 3,
      style: theme.textTheme.bodyMedium,
      dropdownColor: theme.canvasColor,
      menuMaxHeight: menuMaxHeight ?? 320,
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(7),
      icon: icon ?? const AppIcon(AppIcons.chevronDown, size: 16),
      iconEnabledColor: theme.colorScheme.onSurfaceVariant,
      iconDisabledColor: theme.colorScheme.onSurfaceVariant.withValues(
        alpha: .45,
      ),
      decoration: decoration.copyWith(
        isDense: true,
        contentPadding:
            decoration.contentPadding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
