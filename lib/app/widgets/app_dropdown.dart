import 'package:flutter/material.dart';

import '../../configs/theme/app_theme.dart';
import 'app_icon.dart';

/// Compact dropdown used by settings rows and other inline controls.
///
/// The control and popup are intentionally kept in one component so settings,
/// editors, and dialogs share the same sizing, borders, selected state, and
/// menu spacing.
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
    final colors = theme.colorScheme;
    final entries = items ?? <DropdownMenuItem<T>>[];
    final selected = _selectedItem(entries);
    final border = BorderSide(color: colors.outlineVariant, width: .6);
    final menuShadow = colors.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: .30)
        : Colors.black.withValues(alpha: .10);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: WidgetStatePropertyAll(menuShadow),
        shape: WidgetStatePropertyAll(AppShapes.card.copyWith(side: border)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        minimumSize: const WidgetStatePropertyAll(Size(144, 0)),
        maximumSize: WidgetStatePropertyAll(Size(280, menuMaxHeight ?? 320)),
      ),
      menuChildren: [
        for (final item in entries)
          MenuItemButton(
            onPressed: item.enabled && onChanged != null
                ? () {
                    item.onTap?.call();
                    onChanged!(item.value);
                  }
                : null,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              alignment: AlignmentDirectional.centerStart,
              shape: const WidgetStatePropertyAll(AppShapes.control),
              textStyle: WidgetStatePropertyAll(theme.textTheme.bodyMedium),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (value != null && item.value == value) {
                  return colors.surfaceContainerHighest;
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return colors.surfaceContainer;
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => item.enabled
                    ? colors.onSurface
                    : colors.onSurfaceVariant.withValues(alpha: .45),
              ),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            trailingIcon: SizedBox.square(
              dimension: 16,
              child: value != null && item.value == value
                  ? AppIcon(
                      AppIcons.check,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    )
                  : null,
            ),
            child: item.child,
          ),
      ],
      builder: (context, controller, child) {
        final button = OutlinedButton(
          onPressed: onChanged == null
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(
              Size(isExpanded ? double.infinity : 96, 36),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            ),
            alignment: AlignmentDirectional.centerStart,
            shape: const WidgetStatePropertyAll(AppShapes.control),
            textStyle: WidgetStatePropertyAll(theme.textTheme.bodyMedium),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.surfaceContainerLow.withValues(alpha: .55);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return colors.surfaceContainer;
              }
              return colors.surfaceContainerLow;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? colors.onSurfaceVariant.withValues(alpha: .45)
                  : colors.onSurface,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? colors.primary
                    : colors.outlineVariant,
                width: states.contains(WidgetState.focused) ? 1 : .6,
              ),
            ),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Flexible(
                child: selected?.child ?? hint ?? const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              icon ?? const AppIcon(AppIcons.chevronDown, size: 16),
            ],
          ),
        );
        return isExpanded
            ? SizedBox(width: double.infinity, child: button)
            : button;
      },
    );
  }

  DropdownMenuItem<T>? _selectedItem(List<DropdownMenuItem<T>> entries) {
    for (final item in entries) {
      if (value != null && item.value == value) return item;
    }
    return null;
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
