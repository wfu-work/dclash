import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import 'profile_builder_draft.dart';

class BuilderRuleDialog extends StatefulWidget {
  const BuilderRuleDialog({
    super.key,
    required this.policies,
    required this.providers,
    required this.onSave,
    this.rule,
  });
  final List<String> policies, providers;
  final String? rule;
  final ValueChanged<String> onSave;
  @override
  State<BuilderRuleDialog> createState() => _BuilderRuleDialogState();
}

class _BuilderRuleDialogState extends State<BuilderRuleDialog> {
  final _form = GlobalKey<FormState>();
  late final BuilderRule _original = widget.rule == null
      ? const BuilderRule(type: 'DOMAIN-SUFFIX', payload: '', policy: 'DIRECT')
      : BuilderRule.parse(widget.rule!);
  late String _type = _original.structured ? _original.type : 'DOMAIN-SUFFIX';
  late String _policy = _original.structured ? _original.policy : 'DIRECT';
  late bool _noResolve = _original.noResolve;
  late bool _rawMode = !_original.structured;
  late final _payload = TextEditingController(text: _original.payload);
  late final _raw = TextEditingController(text: widget.rule ?? '');
  String _structured() => BuilderRule(
    type: _type,
    payload: _payload.text,
    policy: _policy,
    noResolve: _noResolve,
  ).toRule();
  bool get _supportsNoResolve => [
    'IP-CIDR',
    'IP-CIDR6',
    'GEOIP',
    'SRC-IP-CIDR',
    'RULE-SET',
  ].contains(_type);
  void _mode(bool raw) {
    try {
      if (raw) {
        _raw.text = [
          _type,
          if (_type != 'MATCH') _payload.text,
          _policy,
          if (_noResolve) 'no-resolve',
        ].join(',');
      } else {
        final rule = BuilderRule.parse(_raw.text.trim());
        if (!rule.structured) {
          throw const FormatException(
            'This rule uses a complex or unsupported expression. Keep it in raw mode.',
          );
        }
        _type = rule.type;
        _policy = rule.policy;
        _noResolve = rule.noResolve;
        _payload.text = rule.payload;
      }
      setState(() => _rawMode = raw);
    } catch (error) {
      showAppError(context, error);
    }
  }

  void _save() {
    try {
      if (!_form.currentState!.validate()) return;
      widget.onSave(_rawMode ? _raw.text.trim() : _structured());
      Navigator.pop(context, true);
    } catch (error) {
      showAppError(context, error);
    }
  }

  @override
  void dispose() {
    _payload.dispose();
    _raw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('builderRule'.tr),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('builderForm'.tr)),
                  ButtonSegment(value: true, label: Text('builderRawRule'.tr)),
                ],
                selected: {_rawMode},
                onSelectionChanged: (value) => _mode(value.single),
              ),
              const SizedBox(height: 20),
              if (_rawMode)
                TextFormField(
                  controller: _raw,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: 'builderRawRule'.tr),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'builderRequired'.tr
                      : null,
                  autocorrect: false,
                  enableSuggestions: false,
                )
              else ...[
                AppDropdownFormField<String>(
                  icon: const AppIcon(AppIcons.chevronDown, size: 16),
                  key: ValueKey('type:$_type'),
                  initialValue: _type,
                  decoration: InputDecoration(labelText: 'builderType'.tr),
                  isExpanded: true,
                  items: builderRuleTypes
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        if (value == 'RULE-SET' && _type != 'RULE-SET') {
                          _payload.text = widget.providers.isEmpty
                              ? ''
                              : widget.providers.first;
                        }
                        if (_type == 'RULE-SET' && value != 'RULE-SET') {
                          _payload.clear();
                        }
                        _type = value;
                        if (!_supportsNoResolve) _noResolve = false;
                      });
                    }
                  },
                ),
                if (_type != 'MATCH') ...[
                  const SizedBox(height: 16),
                  if (_type == 'RULE-SET')
                    AppDropdownFormField<String>(
                      icon: const AppIcon(AppIcons.chevronDown, size: 16),
                      key: ValueKey('provider:${_payload.text}'),
                      initialValue: _payload.text.isEmpty
                          ? null
                          : _payload.text,
                      decoration: InputDecoration(
                        labelText: 'builderRuleProvider'.tr,
                      ),
                      isExpanded: true,
                      items:
                          {
                                ...widget.providers,
                                if (_payload.text.isNotEmpty) _payload.text,
                              }
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                      validator: (value) => value == null || value.isEmpty
                          ? 'builderRequired'.tr
                          : null,
                      onChanged: (value) =>
                          setState(() => _payload.text = value ?? ''),
                    )
                  else
                    TextFormField(
                      controller: _payload,
                      decoration: InputDecoration(
                        labelText: 'builderRuleValue'.tr,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'builderRequired'.tr
                          : null,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                ],
                const SizedBox(height: 16),
                AppDropdownFormField<String>(
                  icon: const AppIcon(AppIcons.chevronDown, size: 16),
                  key: ValueKey('policy:$_policy'),
                  initialValue: _policy,
                  decoration: InputDecoration(labelText: 'builderPolicy'.tr),
                  isExpanded: true,
                  items: {...widget.policies, _policy}
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _policy = value);
                  },
                ),
                if (_supportsNoResolve)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('no-resolve'),
                    value: _noResolve,
                    onChanged: (value) => setState(() => _noResolve = value),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('featureCancel'.tr),
      ),
      FilledButton(onPressed: _save, child: Text('builderApply'.tr)),
    ],
  );
}
