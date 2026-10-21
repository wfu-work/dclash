import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../utils/yaml_config.dart';
import '../../../widgets/app_widgets.dart';
import '../widgets/profile_editor.dart';
import 'builder_fields.dart';
import 'builder_schema.dart';
import 'profile_builder_draft.dart';

class BuilderEntryDialog extends StatefulWidget {
  const BuilderEntryDialog({
    super.key,
    required this.section,
    required this.entry,
    required this.members,
    required this.providers,
    required this.onSave,
  });
  final BuilderSection section;
  final BuilderEntry entry;
  final List<String> members, providers;
  final ValueChanged<BuilderEntry> onSave;
  @override
  State<BuilderEntryDialog> createState() => _BuilderEntryDialogState();
}

class _BuilderEntryDialogState extends State<BuilderEntryDialog> {
  final _form = GlobalKey<FormState>();
  late Map<String, dynamic> _data = {...widget.entry.data};
  late final _name = TextEditingController(text: widget.entry.name);
  late final _yaml = TextEditingController(text: encodeYaml(_data));
  final _edits = <String, dynamic>{};
  final _specs = <String, BuilderFieldSpec>{};
  late bool _advanced = !_types.contains(_data['type']);

  Map<String, dynamic> get _visibleData => applyBuilderEdits(_data, _edits);
  List<String> get _types => widget.section == BuilderSection.proxies
      ? ProfileBuilderDraft.proxyTypes
      : widget.section == BuilderSection.groups
      ? ProfileBuilderDraft.groupTypes
      : ProfileBuilderDraft.providerTypes;
  bool get _known => _types.contains(_visibleData['type']);

  Map<String, dynamic> _formData({bool ignoreInvalid = false}) {
    final values = <String, dynamic>{};
    for (final entry in _edits.entries) {
      try {
        final spec = _specs[entry.key];
        values[entry.key] = spec == null
            ? entry.value
            : spec.convert(entry.value);
      } on FormatException {
        if (!ignoreInvalid) rethrow;
        values[entry.key] = entry.value;
      }
    }
    return applyBuilderEdits(_data, values);
  }

  void _mode(bool advanced) {
    try {
      if (advanced) {
        _data = _formData(ignoreInvalid: true);
        _yaml.text = encodeYaml(_data);
      } else {
        _data = parseBuilderEntryYaml(_yaml.text);
        if (_data['type'] is! String || (_data['type'] as String).isEmpty) {
          throw const FormatException('An entry requires a type.');
        }
      }
      setState(() {
        _edits.clear();
        _specs.clear();
        _advanced = advanced;
      });
    } catch (error) {
      showAppError(context, error);
    }
  }

  void _changeType(String? type) {
    if (type == null) return;
    setState(() {
      _data = {..._formData(ignoreInvalid: true), 'type': type};
      _edits.clear();
      _specs.clear();
      if (widget.section == BuilderSection.groups &&
          ['url-test', 'fallback', 'load-balance'].contains(type)) {
        _data.putIfAbsent('url', () => 'https://www.gstatic.com/generate_204');
        _data.putIfAbsent('interval', () => 300);
      }
      if (widget.section == BuilderSection.proxies && type == 'ss') {
        _data.putIfAbsent('cipher', () => 'aes-128-gcm');
      }
    });
  }

  void _save() {
    try {
      if (!_form.currentState!.validate()) return;
      final data = _advanced ? parseBuilderEntryYaml(_yaml.text) : _formData();
      final name = widget.section.provider ? _name.text.trim() : data['name'];
      if (name is! String) throw const FormatException('Enter an entry name.');
      widget.onSave(BuilderEntry(name, data));
      Navigator.pop(context, true);
    } catch (error) {
      showAppError(context, error);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _yaml.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _visibleData;
    final type = data['type'] is String ? data['type'] as String : '';
    final options = {..._types, if (type.isNotEmpty) type};
    final specs = builderSchema(widget.section, data);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.section.labelKey.tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'featureCancel'.tr,
                      onPressed: () => Navigator.pop(context),
                      icon: const AppIcon(AppIcons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.section.provider) ...[
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(labelText: 'builderName'.tr),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'builderRequired'.tr
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const AppIcon(AppIcons.sliders),
                      label: Text('builderForm'.tr),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const AppIcon(AppIcons.code),
                      label: Text('builderAdvancedYaml'.tr),
                    ),
                  ],
                  selected: {_advanced},
                  onSelectionChanged: (value) => _mode(value.single),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _advanced
                      ? ProfileCodeEditor(controller: _yaml)
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppDropdownFormField<String>(
                                icon: const AppIcon(
                                  AppIcons.chevronDown,
                                  size: 16,
                                ),
                                key: ValueKey('type:$type'),
                                initialValue: type.isEmpty ? null : type,
                                decoration: InputDecoration(
                                  labelText: 'builderType'.tr,
                                ),
                                items: options
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _changeType,
                              ),
                              if (!_known)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'builderUnknownType'.tr,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              if (type == 'inline' && widget.section.provider)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'builderInlineHelp'.tr,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              for (final spec in specs)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: BuilderFieldInput(
                                    key: ValueKey(
                                      '${widget.section.name}:${spec.path}',
                                    ),
                                    spec: spec,
                                    value: builderValue(data, spec.path),
                                    onChanged: (value) => setState(() {
                                      _edits[spec.path] = value;
                                      _specs[spec.path] = spec;
                                    }),
                                  ),
                                ),
                              if (widget.section == BuilderSection.groups) ...[
                                const SizedBox(height: 16),
                                BuilderNameList(
                                  label: 'builderMembers'.tr,
                                  values: data['proxies'] is List
                                      ? (data['proxies'] as List)
                                            .whereType<String>()
                                            .toList()
                                      : [],
                                  options: widget.members
                                      .where((value) => value != data['name'])
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => _edits['proxies'] = value),
                                ),
                                const SizedBox(height: 16),
                                BuilderNameList(
                                  label: 'builderProxyProviders'.tr,
                                  values: data['use'] is List
                                      ? (data['use'] as List)
                                            .whereType<String>()
                                            .toList()
                                      : [],
                                  options: widget.providers,
                                  onChanged: (value) =>
                                      setState(() => _edits['use'] = value),
                                ),
                              ],
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const AppIcon(AppIcons.check, size: 18),
                    label: Text('builderApply'.tr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
