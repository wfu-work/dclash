import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/clash_profile.dart';
import '../../../../domains/script_library.dart';
import '../../../../domains/standard_extension.dart';
import '../../../widgets/app_switch.dart';

class ProfileSettingsDialog extends StatefulWidget {
  const ProfileSettingsDialog({
    super.key,
    required this.profile,
    required this.scripts,
  });
  final ClashProfile profile;
  final List<LibraryScript> scripts;
  @override
  State<ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends State<ProfileSettingsDialog> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _url = TextEditingController(text: widget.profile.url);
  late final _hours = TextEditingController(
    text: '${widget.profile.autoUpdateHours}',
  );
  late final _rules = TextEditingController(
    text: widget.profile.standardRules.join('\n'),
  );
  late final _target = TextEditingController(
    text: widget.profile.matchTarget ?? '',
  );
  final _form = GlobalKey<FormState>();
  late bool _followEnabled;
  late Set<String> _selectedScriptIds;

  @override
  void initState() {
    super.initState();
    _followEnabled = widget.profile.sharedScriptIds == null;
    _selectedScriptIds = {
      ...(widget.profile.sharedScriptIds ??
          widget.scripts.where((item) => item.enabled).map((item) => item.id)),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _hours.dispose();
    _rules.dispose();
    _target.dispose();
    super.dispose();
  }

  void _appendPreset(StandardRulePreset preset) {
    final current = _rules.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final rule in preset.rules) {
      if (!current.contains(rule)) current.add(rule);
    }
    setState(() => _rules.text = current.join('\n'));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('profileAction_settings'.tr),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'profileName'.tr),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'profileNameRequired'.tr
                    : null,
              ),
              if (widget.profile.source == ProfileSource.remote) ...[
                const SizedBox(height: 18),
                TextFormField(
                  controller: _url,
                  decoration: InputDecoration(
                    labelText: 'profileSubscriptionUrl'.tr,
                  ),
                  validator: (value) {
                    final uri = Uri.tryParse(value ?? '');
                    return uri == null ||
                            !['http', 'https'].contains(uri.scheme) ||
                            uri.host.isEmpty
                        ? 'profileInvalidUrl'.tr
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _hours,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'profileUpdateHours'.tr,
                    helperText: 'profileUpdateHoursHelp'.tr,
                  ),
                  validator: (value) =>
                      int.tryParse(value ?? '') == null || int.parse(value!) < 0
                      ? 'profileInvalidHours'.tr
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'scriptSelectionTitle'.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              MergeSemantics(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('scriptSelectionFollow'.tr),
                  subtitle: Text('scriptSelectionFollowHelp'.tr),
                  trailing: AppSwitch(
                    value: _followEnabled,
                    onChanged: (value) =>
                        setState(() => _followEnabled = value),
                  ),
                  onTap: () => setState(() => _followEnabled = !_followEnabled),
                ),
              ),
              if (widget.scripts.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'scriptSelectionEmpty'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                ...widget.scripts.map(
                  (script) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedScriptIds.contains(script.id),
                    onChanged: _followEnabled || !script.enabled
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selectedScriptIds.add(script.id);
                            } else {
                              _selectedScriptIds.remove(script.id);
                            }
                          }),
                    title: Text(script.name),
                    subtitle: Text(
                      script.enabled
                          ? (script.remote
                                ? 'scriptImport'.tr
                                : 'scriptLocal'.tr)
                          : 'scriptDisabled'.tr,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              if (!_followEnabled)
                ...widget.profile.sharedScriptIds
                        ?.where(
                          (id) =>
                              widget.scripts.every((script) => script.id != id),
                        )
                        .map(
                          (id) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_outlined),
                            title: Text(id),
                            subtitle: Text('scriptSelectionMissing'.tr),
                          ),
                        ) ??
                    const <Widget>[],
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded:
                    widget.profile.standardRules.isNotEmpty ||
                    widget.profile.matchTarget != null,
                title: Text('profileStandardExtension'.tr),
                subtitle: Text('profileStandardExtensionHelp'.tr),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'profileStandardRules'.tr,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                      PopupMenuButton<StandardRulePreset>(
                        tooltip: 'profileRulePreset'.tr,
                        onSelected: _appendPreset,
                        itemBuilder: (_) => [
                          for (final preset in standardRulePresets)
                            PopupMenuItem(
                              value: preset,
                              child: Text(preset.labelKey.tr),
                            ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text('profileRulePreset'.tr),
                          ],
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _rules,
                    minLines: 3,
                    maxLines: 7,
                    decoration: InputDecoration(
                      labelText: 'profileStandardRules'.tr,
                      helperText: 'profileStandardRulesHelp'.tr,
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      try {
                        normalizeStandardRules((value ?? '').split('\n'));
                        return null;
                      } on FormatException catch (error) {
                        return error.message.toString();
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _target,
                    decoration: InputDecoration(
                      labelText: 'profileMatchTarget'.tr,
                      helperText: 'profileMatchTargetHelp'.tr,
                    ),
                    validator: (value) {
                      try {
                        validateMatchTarget(value);
                        return null;
                      } on FormatException catch (error) {
                        return error.message.toString();
                      }
                    },
                  ),
                ],
              ),
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
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              widget.profile.copyWith(
                name: _name.text.trim(),
                url: _url.text.trim(),
                autoUpdateHours: int.tryParse(_hours.text),
                sharedScriptIds: _followEnabled
                    ? null
                    : _selectedScriptIds.toList(),
                standardRules: normalizeStandardRules(_rules.text.split('\n')),
                matchTarget: _target.text.trim().isEmpty
                    ? null
                    : _target.text.trim(),
              ),
            );
          }
        },
        child: Text('featureSave'.tr),
      ),
    ],
  );
}
