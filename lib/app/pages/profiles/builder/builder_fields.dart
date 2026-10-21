import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';

enum BuilderFieldKind { text, integer, choice, boolean }

class BuilderFieldSpec {
  const BuilderFieldSpec(
    this.path,
    this.label, {
    this.kind = BuilderFieldKind.text,
    this.required = false,
    this.secret = false,
    this.choices = const [],
    this.min,
    this.max,
    this.hint,
  });
  final String path, label;
  final BuilderFieldKind kind;
  final bool required, secret;
  final List<String> choices;
  final int? min, max;
  final String? hint;

  String? validate(String? input) {
    final value = secret ? input ?? '' : (input ?? '').trim();
    if (value.isEmpty) return required ? 'builderRequired'.tr : null;
    if (kind == BuilderFieldKind.integer) {
      final number = int.tryParse(value);
      if (number == null ||
          (min != null && number < min!) ||
          (max != null && number > max!)) {
        return 'builderInvalidNumber'.trParams({
          'min': '${min ?? 0}',
          'max': '${max ?? 2147483647}',
        });
      }
    }
    return null;
  }

  dynamic convert(dynamic value) {
    if (kind == BuilderFieldKind.boolean) return value;
    final text = secret ? '$value' : '$value'.trim();
    if (text.isEmpty) return null;
    return kind == BuilderFieldKind.integer ? int.parse(text) : text;
  }
}

/// One field implementation for nodes, groups and both provider forms.
class BuilderFieldInput extends StatefulWidget {
  const BuilderFieldInput({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
  });
  final BuilderFieldSpec spec;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  @override
  State<BuilderFieldInput> createState() => _BuilderFieldInputState();
}

class _BuilderFieldInputState extends State<BuilderFieldInput> {
  late final _text = TextEditingController(
    text: widget.value?.toString() ?? '',
  );
  bool _obscured = true;
  @override
  void didUpdateWidget(covariant BuilderFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value?.toString() ?? '';
    if (oldWidget.value != widget.value && _text.text != value) {
      _text.text = value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final decoration = InputDecoration(
      labelText: spec.label.tr,
      hintText: spec.hint,
    );
    if (spec.kind == BuilderFieldKind.boolean) {
      return AppDropdownFormField<bool?>(
        icon: const AppIcon(AppIcons.chevronDown, size: 16),
        key: ValueKey('${spec.path}:${widget.value}'),
        initialValue: widget.value is bool ? widget.value as bool : null,
        decoration: decoration,
        items: [
          DropdownMenuItem(value: null, child: Text('builderDefault'.tr)),
          DropdownMenuItem(value: true, child: Text('builderEnabled'.tr)),
          DropdownMenuItem(value: false, child: Text('builderDisabled'.tr)),
        ],
        onChanged: widget.onChanged,
      );
    }
    if (spec.kind == BuilderFieldKind.choice) {
      final value = widget.value?.toString();
      final options = {
        ...spec.choices,
        if (value != null && value.isNotEmpty) value,
      };
      return AppDropdownFormField<String>(
        icon: const AppIcon(AppIcons.chevronDown, size: 16),
        key: ValueKey('${spec.path}:$value'),
        initialValue: value?.isEmpty == true ? null : value,
        isExpanded: true,
        decoration: decoration,
        items: [
          if (!spec.required)
            DropdownMenuItem(value: '', child: Text('builderDefault'.tr)),
          ...options.map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        validator: spec.validate,
        onChanged: widget.onChanged,
      );
    }
    return TextFormField(
      controller: _text,
      decoration: decoration.copyWith(
        suffixIcon: spec.secret
            ? IconButton(
                tooltip:
                    (_obscured
                            ? 'builderShowCredential'
                            : 'builderHideCredential')
                        .tr,
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: AppIcon(_obscured ? AppIcons.eye : AppIcons.eyeOff),
              )
            : null,
      ),
      obscureText: spec.secret && _obscured,
      autocorrect: false,
      enableSuggestions: false,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      keyboardType: spec.kind == BuilderFieldKind.integer
          ? TextInputType.number
          : TextInputType.text,
      validator: spec.validate,
      onChanged: widget.onChanged,
    );
  }
}

class BuilderNameList extends StatelessWidget {
  const BuilderNameList({
    super.key,
    required this.label,
    required this.values,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final List<String> values, options;
  final ValueChanged<List<String>> onChanged;

  Future<void> _choose(BuildContext context) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _NamePicker(label: label, selected: values, options: options),
    );
    if (result != null) onChanged(result);
  }

  void _move(int index, int direction) {
    final result = [...values];
    final value = result.removeAt(index);
    result.insert(index + direction, value);
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          TextButton.icon(
            onPressed: () => _choose(context),
            icon: const AppIcon(AppIcons.add, size: 18),
            label: Text('builderChoose'.tr),
          ),
        ],
      ),
      if (values.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'builderNoSelection'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (values.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: values.length,
            itemBuilder: (_, index) => Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    values[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'builderMoveUp'.tr,
                  visualDensity: VisualDensity.compact,
                  onPressed: index == 0 ? null : () => _move(index, -1),
                  icon: const AppIcon(AppIcons.arrowUp, size: 17),
                ),
                IconButton(
                  tooltip: 'builderMoveDown'.tr,
                  visualDensity: VisualDensity.compact,
                  onPressed: index == values.length - 1
                      ? null
                      : () => _move(index, 1),
                  icon: const AppIcon(AppIcons.arrowDown, size: 17),
                ),
                IconButton(
                  tooltip: 'builderRemove'.tr,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final result = [...values]..removeAt(index);
                    onChanged(result);
                  },
                  icon: const AppIcon(AppIcons.close, size: 17),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _NamePicker extends StatefulWidget {
  const _NamePicker({
    required this.label,
    required this.selected,
    required this.options,
  });
  final String label;
  final List<String> selected, options;
  @override
  State<_NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<_NamePicker> {
  late final _selected = [...widget.selected];
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final options = {...widget.options, ...widget.selected}
        .where((value) => value.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const AppIcon(AppIcons.search),
                hintText: 'builderSearchMembers'.tr,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, index) {
                  final value = options[index];
                  return CheckboxListTile(
                    dense: true,
                    title: Text(value),
                    value: _selected.contains(value),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(value);
                      } else {
                        _selected.remove(value);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('featureCancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text('featureDone'.tr),
        ),
      ],
    );
  }
}
