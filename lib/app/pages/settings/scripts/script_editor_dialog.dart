import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/script_library.dart';
import '../../../widgets/app_icon.dart';
import '../../profiles/widgets/profile_editor.dart';

class ScriptDraft {
  const ScriptDraft(this.name, this.content);
  final String name, content;
}

class ScriptEditorDialog extends StatefulWidget {
  const ScriptEditorDialog({super.key, this.script});
  final LibraryScript? script;

  @override
  State<ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _ScriptEditorDialogState extends State<ScriptEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.script?.name ?? '');
  late final _content = TextEditingController(
    text:
        widget.script?.content ??
        'function main(config) {\n  return config;\n}',
  );

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 900,
        maxHeight: MediaQuery.sizeOf(context).height * .86,
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
                      (widget.script == null ? 'scriptCreate' : 'scriptEdit')
                          .tr,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'close'.tr,
                    onPressed: () => Navigator.pop(context),
                    icon: const AppIcon(AppIcons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                maxLength: 256,
                decoration: InputDecoration(labelText: 'scriptName'.tr),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'scriptNameRequired'.tr
                    : null,
              ),
              if (widget.script?.url != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.script!.url!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Text(
                (widget.script?.remote == true
                        ? 'scriptRemoteEditHelp'
                        : 'scriptEditHelp')
                    .tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ProfileCodeEditor(
                  controller: _content,
                  readOnly: widget.script?.remote == true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'scriptContentRequired'.tr;
                    }
                    try {
                      validateScriptContent(value);
                    } on FormatException {
                      return 'scriptTooLarge'.tr;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    if (!_form.currentState!.validate()) return;
                    Navigator.pop(
                      context,
                      ScriptDraft(_name.text.trim(), _content.text),
                    );
                  },
                  icon: const AppIcon(AppIcons.check),
                  label: Text('save'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RemoteScriptDraft {
  const RemoteScriptDraft(this.name, this.url);
  final String name, url;
}

class RemoteScriptDialog extends StatefulWidget {
  const RemoteScriptDialog({super.key});

  @override
  State<RemoteScriptDialog> createState() => _RemoteScriptDialogState();
}

class _RemoteScriptDialogState extends State<RemoteScriptDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('scriptImport'.tr),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('scriptImportHelp'.tr),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 256,
                decoration: InputDecoration(labelText: 'scriptName'.tr),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'scriptNameRequired'.tr
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'scriptUrl'.tr,
                  hintText: 'https://example.com/script.js',
                ),
                validator: (value) {
                  try {
                    validateScriptUrl(value ?? '');
                    return null;
                  } on FormatException {
                    return 'scriptInvalidUrl'.tr;
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('cancel'.tr),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            RemoteScriptDraft(_name.text.trim(), _url.text.trim()),
          );
        },
        child: Text('scriptImport'.tr),
      ),
    ],
  );
}
