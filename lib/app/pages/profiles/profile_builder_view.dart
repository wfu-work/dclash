import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/clash_profile.dart';
import '../../../domains/resource_item.dart';
import '../../../services/resource_library_service.dart';
import '../../widgets/app_widgets.dart';
import 'builder/builder_entry_dialog.dart';
import 'builder/builder_rule_dialog.dart';
import 'builder/profile_builder_draft.dart';
import 'builder/resource_picker_dialog.dart';

String _encodeDraft(ProfileBuilderDraft draft) => draft.toYaml();

class ProfileBuilderView extends StatefulWidget {
  const ProfileBuilderView({
    super.key,
    required this.profile,
    required this.initialContent,
    required this.onSave,
  });

  final ClashProfile profile;
  final String initialContent;
  final Future<void> Function(String content) onSave;

  @override
  State<ProfileBuilderView> createState() => _ProfileBuilderViewState();
}

class _ProfileBuilderViewState extends State<ProfileBuilderView> {
  final _search = TextEditingController();
  ProfileBuilderDraft? _draft;
  Object? _error;
  BuilderSection _section = BuilderSection.proxies;
  String _query = '';
  bool _dirty = false, _saving = false, _leaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final draft = await compute(
        ProfileBuilderDraft.parse,
        widget.initialContent,
      );
      if (mounted) setState(() => _draft = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _leave() async {
    if (_saving || _leaving) return;
    _leaving = true;
    try {
      if (_dirty) {
        final discard = await AppDialogs.confirm(
          context,
          title: 'builderDiscardTitle'.tr,
          message: 'builderDiscardMessage'.tr,
        );
        if (!discard || !mounted) return;
      }
      if (mounted) {
        setState(() => _dirty = false);
        // Update PopScope before popping the route on Android as well.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } finally {
      _leaving = false;
    }
  }

  Future<void> _save() async {
    if (_draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      final content = await compute(_encodeDraft, _draft!);
      await widget.onSave(content);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  BuilderEntry _newEntry(BuilderSection section) {
    final draft = _draft!;
    final name = draft.nextName(section, switch (section) {
      BuilderSection.proxies => 'builderNewProxy'.tr,
      BuilderSection.groups => 'builderNewGroup'.tr,
      BuilderSection.proxyProviders => 'builderNewProxyProvider'.tr,
      BuilderSection.ruleProviders => 'builderNewRuleProvider'.tr,
      BuilderSection.rules => '',
    });
    final path =
        './providers/${section.name}-${DateTime.now().microsecondsSinceEpoch}.yaml';
    return BuilderEntry(name, switch (section) {
      BuilderSection.proxies => {
        'name': name,
        'type': 'ss',
        'server': '',
        'port': 443,
        'cipher': 'aes-128-gcm',
        'password': '',
      },
      BuilderSection.groups => {
        'name': name,
        'type': 'select',
        'proxies': ['DIRECT'],
      },
      BuilderSection.proxyProviders => {
        'type': 'http',
        'url': '',
        'path': path,
        'interval': 3600,
        'health-check': {
          'enable': true,
          'url': 'https://www.gstatic.com/generate_204',
          'interval': 300,
        },
      },
      BuilderSection.ruleProviders => {
        'type': 'http',
        'behavior': 'domain',
        'format': 'yaml',
        'url': '',
        'path': path,
        'interval': 86400,
      },
      BuilderSection.rules => <String, dynamic>{},
    });
  }

  Future<void> _edit({BuilderEntry? entry, int? ruleIndex}) async {
    if (_saving) return;
    final section = _section;
    final draft = _draft!;
    final changed = section == BuilderSection.rules
        ? await showDialog<bool>(
            context: context,
            builder: (_) => BuilderRuleDialog(
              rule: ruleIndex == null ? null : draft.rules[ruleIndex],
              policies: draft.policies,
              providers: draft.names(BuilderSection.ruleProviders),
              onSave: (rule) => draft.saveRule(rule, index: ruleIndex),
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => BuilderEntryDialog(
              section: section,
              entry: entry ?? _newEntry(section),
              members: draft.policies,
              providers: draft.names(BuilderSection.proxyProviders),
              onSave: (edited) => draft.saveEntry(
                section,
                originalName: entry?.name,
                name: edited.name,
                data: edited.data,
              ),
            ),
          );
    if (changed == true && mounted) setState(() => _dirty = true);
  }

  Future<void> _remove({BuilderEntry? entry, int? ruleIndex}) async {
    if (_saving) return;
    final section = _section;
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'builderRemove'.tr,
      message: ruleIndex == null
          ? 'builderRemoveConfirm'.trParams({'name': entry!.name})
          : 'builderRemoveRuleConfirm'.trParams({'index': '${ruleIndex + 1}'}),
    );
    if (!confirmed || !mounted) return;
    try {
      if (ruleIndex == null) {
        _draft!.removeEntry(section, entry!.name);
      } else {
        _draft!.removeRule(ruleIndex);
      }
      setState(() => _dirty = true);
    } catch (error) {
      showAppError(context, error);
    }
  }

  void _move(int oldIndex, int newIndex) {
    if (_saving || oldIndex == newIndex || newIndex == oldIndex + 1) return;
    setState(() {
      _draft!.move(_section, oldIndex, newIndex);
      _dirty = true;
    });
  }

  Future<void> _useResource(ResourceKind kind) async {
    if (_saving || _draft == null) return;
    final service = Get.find<ResourceLibraryService>();
    final item = await showDialog<ResourceItem>(
      context: context,
      builder: (_) => ResourcePickerDialog(
        service: service,
        kind: kind,
        onSelected: (_) {},
      ),
    );
    if (item == null || !mounted) return;
    try {
      final content = await service.resolveContent(item);
      switch (kind) {
        case ResourceKind.proxy:
          _draft!.importProxyResource(content);
        case ResourceKind.ruleProvider:
          _draft!.addProviderResource(
            BuilderSection.ruleProviders,
            item,
            content: content,
          );
        case ResourceKind.regexFilter:
          _draft!.applyRegexFilter(content);
        case ResourceKind.iconSet:
          _draft!.applyIconSet(content);
      }
      setState(() => _dirty = true);
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  String _host(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    final uri = Uri.tryParse(value.contains('://') ? value : '//$value');
    return uri?.host ?? '';
  }

  String _subtitle(BuilderEntry entry) {
    final data = entry.data;
    final values = <String>[if (data['type'] is String) data['type'] as String];
    if (_section == BuilderSection.proxies) {
      final host = _host(data['server']);
      if (host.isNotEmpty) values.add(host);
      if (data['port'] is int) values.add('${data['port']}');
    } else if (_section == BuilderSection.groups) {
      final members = data['proxies'] is List
          ? (data['proxies'] as List).length
          : 0;
      values.add('builderMemberCount'.trParams({'count': '$members'}));
    } else {
      final host = _host(data['url']);
      if (host.isNotEmpty) values.add(host);
      if (data['behavior'] is String) values.add(data['behavior'] as String);
    }
    return values.join(' · ');
  }

  Widget _items() {
    final draft = _draft!;
    final isRule = _section == BuilderSection.rules;
    final entries = isRule ? <BuilderEntry>[] : draft.entries(_section);
    final rules = isRule ? draft.rules : <String>[];
    final count = isRule ? rules.length : entries.length;
    final query = _query.trim().toLowerCase();
    final indices = List.generate(count, (index) => index).where((index) {
      final searchable = isRule
          ? rules[index]
          : '${entries[index].name} ${_subtitle(entries[index])}';
      return query.isEmpty || searchable.toLowerCase().contains(query);
    }).toList();
    if (indices.isEmpty) {
      return AppEmpty(
        icon: isRule ? AppIcons.rules : AppIcons.tree,
        title: (query.isEmpty ? 'builderEmpty' : 'builderNoResults').tr,
        message: query.isEmpty ? 'builderEmptyHelp'.tr : null,
      );
    }
    Widget tile(BuildContext context, int visibleIndex) {
      final index = indices[visibleIndex];
      final entry = isRule ? null : entries[index];
      return Material(
        key: ValueKey('${_section.name}:$index:${entry?.name ?? rules[index]}'),
        color: Theme.of(context).colorScheme.surface,
        child: ListTile(
          enabled: !_saving,
          leading: isRule
              ? SizedBox(
                  width: 32,
                  child: Text('${index + 1}', textAlign: TextAlign.center),
                )
              : AppIcon(_icon(_section)),
          title: Text(
            isRule ? rules[index] : entry!.name,
            maxLines: isRule ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: isRule
              ? null
              : Text(
                  _subtitle(entry!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _edit(entry: entry, ruleIndex: isRule ? index : null),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                tooltip: 'featureMore'.tr,
                enabled: !_saving,
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _edit(entry: entry, ruleIndex: isRule ? index : null);
                    case 'remove':
                      _remove(entry: entry, ruleIndex: isRule ? index : null);
                    case 'up':
                      _move(index, index - 1);
                    case 'down':
                      _move(index, index + 2);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('edit'.tr)),
                  if (query.isEmpty && index > 0)
                    PopupMenuItem(value: 'up', child: Text('builderMoveUp'.tr)),
                  if (query.isEmpty && index < count - 1)
                    PopupMenuItem(
                      value: 'down',
                      child: Text('builderMoveDown'.tr),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('builderRemove'.tr),
                  ),
                ],
              ),
              if (query.isEmpty)
                ReorderableDragStartListener(
                  enabled: !_saving,
                  index: visibleIndex,
                  child: Tooltip(
                    message: 'builderDragReorder'.tr,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: AppIcon(AppIcons.drag),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return query.isEmpty
        ? ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: indices.length,
            itemBuilder: tile,
            onReorderItem: (oldIndex, newIndex) =>
                _move(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
          )
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: indices.length,
            itemBuilder: tile,
          );
  }

  IconData _icon(BuilderSection section) => switch (section) {
    BuilderSection.proxies => AppIcons.server,
    BuilderSection.groups => AppIcons.tree,
    BuilderSection.proxyProviders => AppIcons.cloudDownload,
    BuilderSection.ruleProviders => AppIcons.checkList,
    BuilderSection.rules => AppIcons.rules,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: DefaultTabController(
      length: BuilderSection.values.length,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _saving ? null : _leave),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('profileAction_builder'.tr),
              Text(
                widget.profile.name,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _draft == null || !_dirty || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppIcons.save, size: 19),
                label: Text('save'.tr),
              ),
            ),
          ],
          bottom: _draft == null
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) => setState(() {
                    _section = BuilderSection.values[index];
                    _query = '';
                    _search.clear();
                  }),
                  tabs: BuilderSection.values
                      .map(
                        (section) => Tab(
                          text:
                              '${section.labelKey.tr} (${_draft!.count(section)})',
                        ),
                      )
                      .toList(),
                ),
        ),
        body: _error != null
            ? AppEmpty(
                icon: AppIcons.error,
                title: 'builderLoadFailed'.tr,
                message: '$_error',
              )
            : _draft == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'builderHelp'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: InputDecoration(
                              prefixIcon: const AppIcon(AppIcons.search),
                              hintText: 'search'.tr,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        PopupMenuButton<ResourceKind>(
                          tooltip: 'builderUseResource'.tr,
                          enabled: !_saving,
                          onSelected: _useResource,
                          itemBuilder: (_) => [
                            for (final kind in ResourceKind.values)
                              PopupMenuItem(
                                value: kind,
                                child: Text(kind.translationKey.tr),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: AppIcon(AppIcons.layers),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: _saving ? null : _edit,
                          icon: const AppIcon(AppIcons.add, size: 19),
                          label: Text('add'.tr),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _items()),
                ],
              ),
      ),
    ),
  );
}

extension ResourceKindBuilderLabels on ResourceKind {
  String get translationKey => 'resourceKind_$wireName';
}
