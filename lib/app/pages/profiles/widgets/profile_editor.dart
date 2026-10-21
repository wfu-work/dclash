import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../widgets/app_icon.dart';

class ProfileDraft {
  const ProfileDraft(this.name, this.content);
  final String name, content;
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.title,
    required this.name,
    required this.content,
    this.script = false,
  });
  final String title, name, content;
  final bool script;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _name = TextEditingController(text: widget.name);
  late final _content = TextEditingController(text: widget.content);
  final _form = GlobalKey<FormState>();
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
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'featureCancel'.tr,
                    icon: const AppIcon(AppIcons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!widget.script) ...[
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: 'profileName'.tr),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'profileNameRequired'.tr
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              Text(
                widget.script ? 'profileScriptHelp'.tr : 'profileYamlHelp'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ProfileCodeEditor(
                  controller: _content,
                  hintText: widget.script
                      ? 'function main(config) {\n  return config;\n}'
                      : 'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT',
                  validator: (value) =>
                      !widget.script && (value == null || value.trim().isEmpty)
                      ? 'profileContentRequired'.tr
                      : null,
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      Navigator.pop(
                        context,
                        ProfileDraft(_name.text.trim(), _content.text),
                      );
                    }
                  },
                  icon: const AppIcon(AppIcons.check, size: 18),
                  label: Text('featureSave'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const _matchLimit = 10000;

List<List<int>> _findCodeMatches(List<String> input) {
  if (input[1].isEmpty) return [];
  final pattern = RegExp(RegExp.escape(input[1]), caseSensitive: false);
  final matches = <List<int>>[];
  for (final match in pattern.allMatches(input[0])) {
    matches.add([match.start, match.end]);
    if (matches.length > _matchLimit) break;
  }
  return matches;
}

/// Shared by the editable source and the read-only effective configuration.
class ProfileCodeEditor extends StatefulWidget {
  const ProfileCodeEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.hintText,
    this.validator,
  });
  final TextEditingController controller;
  final bool readOnly;
  final String? hintText;
  final FormFieldValidator<String>? validator;

  @override
  State<ProfileCodeEditor> createState() => _ProfileCodeEditorState();
}

class _ProfileCodeEditorState extends State<ProfileCodeEditor> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _fieldKey = GlobalKey();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<TextSelection> _matches = [];
  String _lastText = '';
  int _current = -1;
  int _revision = 0;
  bool _searchOpen = false;
  bool _searching = false;
  bool _limited = false;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_contentChanged);
    _search.addListener(_queueSearch);
  }

  @override
  void didUpdateWidget(covariant ProfileCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_contentChanged);
      widget.controller.addListener(_contentChanged);
      _lastText = widget.controller.text;
      _queueSearch();
    }
  }

  void _contentChanged() {
    if (_lastText == widget.controller.text) return;
    _lastText = widget.controller.text;
    _queueSearch();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _search.text.length,
      );
    });
    _queueSearch();
  }

  void _closeSearch() {
    _debounce?.cancel();
    _revision++;
    setState(() {
      _searchOpen = false;
      _searching = false;
    });
    _codeFocus.requestFocus();
  }

  void _queueSearch() {
    _debounce?.cancel();
    final revision = ++_revision;
    if (!_searchOpen) return;
    if (_search.text.isEmpty) {
      setState(() {
        _matches = [];
        _current = -1;
        _searching = false;
        _limited = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final matches = await compute(_findCodeMatches, [
        widget.controller.text,
        _search.text,
      ]);
      if (!mounted || revision != _revision) return;
      setState(() {
        _limited = matches.length > _matchLimit;
        _matches = matches
            .take(_matchLimit)
            .map(
              (value) =>
                  TextSelection(baseOffset: value[0], extentOffset: value[1]),
            )
            .toList();
        _current = _matches.isEmpty ? -1 : 0;
        _searching = false;
      });
      _selectMatch();
    });
  }

  void _jump(int direction) {
    if (!_searchOpen) {
      _openSearch();
      return;
    }
    if (_matches.isEmpty || _searching) return;
    setState(() => _current = (_current + direction) % _matches.length);
    _selectMatch();
  }

  void _selectMatch() {
    if (_current < 0 || _current >= _matches.length) return;
    final selection = _matches[_current];
    if (selection.end > widget.controller.text.length) return;
    widget.controller.selection = selection;
    // Reveal the caret without stealing focus from the find input. The form
    // field creates its EditableText internally, so use its public state API.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EditableTextState? editable;
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          editable = element.state as EditableTextState;
        } else {
          element.visitChildElements(visit);
        }
      }

      _fieldKey.currentContext?.visitChildElements(visit);
      editable?.bringIntoView(selection.extent);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_contentChanged);
    _search.removeListener(_queueSearch);
    _search.dispose();
    _searchFocus.dispose();
    _codeFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          _openSearch,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
      const SingleActivator(LogicalKeyboardKey.f3): () => _jump(1),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
          _jump(-1),
      if (_searchOpen)
        const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_searchOpen)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'profileEditorFind'.tr,
              onPressed: _openSearch,
              icon: const AppIcon(AppIcons.search),
            ),
          ),
        if (_searchOpen) ...[
          TextField(
            key: const ValueKey('profileEditorFindInput'),
            controller: _search,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _jump(1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'profileEditorFindHint'.tr,
              prefixIcon: const AppIcon(AppIcons.search),
              suffixIcon: IconButton(
                tooltip: 'profileEditorCloseFind'.tr,
                onPressed: _closeSearch,
                icon: const AppIcon(AppIcons.close),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _search.text.isEmpty
                      ? 'profileEditorFindHelp'.tr
                      : _searching
                      ? 'profileEditorSearching'.tr
                      : _matches.isEmpty
                      ? 'profileEditorNoMatches'.tr
                      : 'profileEditorMatches'.trParams({
                          'current': '${_current + 1}',
                          'total': '${_matches.length}${_limited ? '+' : ''}',
                        }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'profileEditorPrevious'.tr,
                onPressed: _matches.isEmpty || _searching
                    ? null
                    : () => _jump(-1),
                icon: const AppIcon(AppIcons.chevronUp),
              ),
              IconButton(
                tooltip: 'profileEditorNext'.tr,
                onPressed: _matches.isEmpty || _searching
                    ? null
                    : () => _jump(1),
                icon: const AppIcon(AppIcons.chevronDown),
              ),
            ],
          ),
        ],
        Expanded(
          child: TextFormField(
            key: _fieldKey,
            controller: widget.controller,
            focusNode: _codeFocus,
            scrollController: _scroll,
            readOnly: widget.readOnly,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12.5,
              height: 1.65,
            ),
            decoration: InputDecoration(
              alignLabelWithHint: true,
              hintText: widget.hintText,
            ),
            validator: widget.validator,
          ),
        ),
      ],
    ),
  );
}
