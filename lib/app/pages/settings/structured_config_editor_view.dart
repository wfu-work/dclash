import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import 'config_editor/config_draft.dart';
import 'config_editor/config_field_row.dart';
import 'config_editor/config_schema.dart';
import 'settings_controller.dart';

class StructuredConfigEditorView extends StatefulWidget {
  const StructuredConfigEditorView({
    super.key,
    required this.setting,
    required this.title,
    required this.example,
  });
  final String setting, title, example;
  @override
  State<StructuredConfigEditorView> createState() =>
      _StructuredConfigEditorViewState();
}

class _StructuredConfigEditorViewState
    extends State<StructuredConfigEditorView> {
  late final TextEditingController _source;
  late ConfigDraft _draft;
  String? _error;
  bool _formMode = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial =
        Get.find<SettingsController>().settings.fields[widget.setting]
            as String? ??
        '';
    _source = TextEditingController(text: initial);
    try {
      _draft = ConfigDraft.parse(initial);
    } catch (error) {
      _draft = ConfigDraft({});
      _formMode = false;
      _error = error.toString();
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _switchMode(bool form) {
    if (form == _formMode) return;
    try {
      if (form) _draft = ConfigDraft.parse(_source.text);
      setState(() {
        _formMode = form;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _change(ConfigField field, dynamic value, {bool remove = false}) {
    try {
      if (remove) {
        _draft.remove(field.path);
      } else {
        _draft.write(field.path, value);
      }
      _source.text = _draft.encode();
      setState(() => _error = null);
    } catch (error) {
      showAppError(context, error);
    }
  }

  Future<void> _edit(ConfigField field) async {
    final value = _draft.read(field.path);
    final initial = value is List ? value.join('\n') : value?.toString() ?? '';
    final next = await AppDialogs.prompt(
      context,
      title: field.label.tr,
      initialValue: initial,
      multiline: field.kind == ConfigFieldKind.list,
      hint:
          field.hint ??
          (field.kind == ConfigFieldKind.list
              ? 'cfgListHint'.tr
              : 'cfgTextHint'.tr),
    );
    if (next == null || !mounted) return;
    try {
      final text = next.trim();
      if (field.kind == ConfigFieldKind.list) {
        final lines = text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        if (field.numericList) {
          final ports = <dynamic>[];
          for (final line in lines) {
            final parts = line.split('-');
            if (parts.length > 2 ||
                parts.any(
                  (part) =>
                      int.tryParse(part) == null ||
                      int.parse(part) < 1 ||
                      int.parse(part) > 65535,
                ) ||
                (parts.length == 2 &&
                    int.parse(parts.first) > int.parse(parts.last))) {
              throw FormatException('cfgInvalidPorts'.tr);
            }
            ports.add(parts.length == 1 ? int.parse(line) : line);
          }
          _change(field, ports);
        } else {
          _change(field, lines);
        }
      } else if (text.isEmpty) {
        _change(field, null, remove: true);
      } else if (field.kind == ConfigFieldKind.number) {
        final number = int.tryParse(text);
        if (number == null ||
            (field.minimum != null && number < field.minimum!) ||
            (field.maximum != null && number > field.maximum!)) {
          throw FormatException(
            'cfgNumberRange'.trParams({
              'min': '${field.minimum ?? 0}',
              'max': '${field.maximum ?? 65535}',
            }),
          );
        }
        _change(field, number);
      } else {
        _change(field, text);
      }
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final content = _formMode ? _draft.encode() : _source.text;
      final parsed = ConfigDraft.parse(content);
      await Get.find<SettingsController>().saveYaml(
        widget.setting,
        parsed.values.isEmpty ? '' : content,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form() {
    final fields = ConfigSchemas.forSetting(widget.setting);
    final sections = fields.map((field) => field.section).toSet();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'cfgPreserveHelp'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (widget.setting == 'tunOverride' || widget.setting == 'dnsOverride')
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              (widget.setting == 'tunOverride'
                      ? 'cfgTunManaged'
                      : 'cfgDnsTunManaged')
                  .tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        for (final section in sections)
          AppSection(
            title: section.tr,
            child: Column(
              children: [
                for (final field in fields.where(
                  (field) => field.section == section,
                ))
                  ConfigFieldRow(
                    key: ValueKey(field.key),
                    field: field,
                    value: _draft.read(field.path),
                    exists: _draft.contains(field.path),
                    onEdit: () => _edit(field),
                    onValue: (value) => _change(field, value),
                    onReset: () => _change(field, null, remove: true),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        title: widget.title.tr,
        subtitle: 'cfgEditorSubtitle'.tr,
        scroll: false,
        actions: [
          IconButton(
            tooltip: 'featureCancel'.tr,
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const AppIcon(AppIcons.close),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppIcon(AppIcons.check, size: 18),
            label: Text('featureSave'.tr),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const AppIcon(AppIcons.sliders, size: 17),
                    label: Text('cfgFormMode'.tr),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const AppIcon(AppIcons.code, size: 17),
                    label: Text('cfgYamlMode'.tr),
                  ),
                ],
                selected: {_formMode},
                onSelectionChanged: _saving
                    ? null
                    : (values) => _switchMode(values.first),
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: IgnorePointer(
                ignoring: _saving,
                child: _formMode
                    ? _form()
                    : AppCard(
                        child: TextField(
                          controller: _source,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 13,
                            height: 1.6,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.example,
                            border: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
