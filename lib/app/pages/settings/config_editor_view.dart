import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import 'settings_controller.dart';

class ConfigEditorView extends StatefulWidget {
  const ConfigEditorView({
    super.key,
    required this.setting,
    required this.title,
    required this.example,
  });
  final String setting, title, example;

  @override
  State<ConfigEditorView> createState() => _ConfigEditorViewState();
}

class _ConfigEditorViewState extends State<ConfigEditorView> {
  late final _text = TextEditingController(
    text:
        Get.find<SettingsController>().settings.fields[widget.setting]
            as String? ??
        '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Get.find<SettingsController>().saveYaml(widget.setting, _text.text);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        title: widget.title.tr,
        subtitle: 'yamlEditorHint'.tr,
        scroll: false,
        actions: [
          IconButton(
            tooltip: 'cancel'.tr,
            onPressed: () => Navigator.pop(context),
            icon: const AppIcon(AppIcons.close),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const AppIcon(AppIcons.check),
            label: Text('save'.tr),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: AppCard(
                child: TextField(
                  controller: _text,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
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
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
