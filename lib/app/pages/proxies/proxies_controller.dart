import 'package:get/get.dart';

import '../../../domains/proxy_group.dart';
import '../../../services/core_ports.dart';
import '../../../services/settings_service.dart';
import '../../../utils/yaml_config.dart';

class ProxiesController extends GetxController {
  ProxiesController(this.core, this.settings);

  final CoreProxyPort core;
  final SettingsService settings;
  final query = ''.obs;
  final selectedGroup = ''.obs;
  final grid = true.obs;
  final testing = <String>{}.obs;
  final testingGroups = <String>{}.obs;
  final expandedGroups = <String, bool>{}.obs;
  final testingAll = false.obs;
  final previewGroups = <ProxyGroup>[].obs;
  final previewLoading = false.obs;
  final _workers = <Worker>[];
  int _previewRevision = 0;

  @override
  void onInit() {
    super.onInit();
    grid.value = settings.fields['proxyLayout'] != 'list';
    _workers.add(ever(core.profiles.profiles, (_) => refreshPreview()));
    _workers.add(ever(core.profiles.activeId, (_) => refreshPreview()));
    _workers.add(ever(core.status, (_) => refreshPreview()));
    refreshPreview();
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }

  List<ProxyGroup> get groups {
    // Preview builds may provide groups without an active profile. An active
    // stopped profile always uses the parsed configuration below.
    final useRuntime =
        core.running ||
        (core.profiles.active == null && core.groups.isNotEmpty);
    return (useRuntime ? core.groups : previewGroups).toList(growable: false);
  }

  bool get hasActiveProfile => core.profiles.active != null;

  /// Reads the active profile for display while the core is stopped. This is
  /// deliberately kept separate from [CoreService.groups], which represents
  /// the live mihomo state and is empty until the service connects.
  Future<void> refreshPreview() async {
    final revision = ++_previewRevision;
    final profile = core.profiles.active;
    if (profile == null) {
      previewGroups.clear();
      previewLoading.value = false;
      return;
    }
    previewLoading.value = true;
    try {
      final content = await core.profiles.readContent(profile);
      if (revision != _previewRevision) return;
      previewGroups.assignAll(_parsePreviewGroups(parseConfig(content)));
    } catch (_) {
      // The profile editor and subscription updater surface their own errors.
      // A malformed or temporarily unavailable profile should leave the proxy
      // page empty instead of making navigation fail.
      if (revision == _previewRevision) previewGroups.clear();
    } finally {
      if (revision == _previewRevision) previewLoading.value = false;
    }
  }

  ProxyGroup? get group {
    final available = groups;
    return available.firstWhereOrNull(
          (item) => item.name == selectedGroup.value,
        ) ??
        available.firstOrNull;
  }

  String get sort => settings.fields['proxySort'] as String? ?? 'default';
  bool get hideUnavailable => settings.fields['hideUnavailable'] == true;
  int? delay(ProxyNode node) =>
      core.running ? core.delays[node.name] ?? node.delay : node.delay;

  List<ProxyNode> get visibleNodes {
    final search = query.value.trim().toLowerCase();
    final nodes = (group?.nodes ?? <ProxyNode>[])
        .where(
          (node) =>
              (search.isEmpty ||
                  '${node.name} ${node.type}'.toLowerCase().contains(search)) &&
              (!hideUnavailable ||
                  (delay(node) == null ? node.alive : delay(node)! >= 0)),
        )
        .toList();
    switch (sort) {
      case 'name':
        nodes.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case 'delay':
        int latency(ProxyNode node) {
          final value = delay(node);
          return value == null
              ? 1 << 30
              : value < 0
              ? 1 << 31
              : value;
        }
        nodes.sort((a, b) {
          final order = latency(a).compareTo(latency(b));
          return order == 0 ? a.name.compareTo(b.name) : order;
        });
    }
    return nodes;
  }

  Future<void> setSort(String value) => settings.set('proxySort', value);
  Future<void> setHideUnavailable(bool value) =>
      settings.set('hideUnavailable', value);

  Future<void> toggleLayout() async {
    final next = !grid.value;
    await settings.set('proxyLayout', next ? 'grid' : 'list');
    grid.value = next;
  }

  bool isExpanded(ProxyGroup value) => expandedGroups[value.name] ?? true;

  void toggleGroup(ProxyGroup value) {
    expandedGroups[value.name] = !isExpanded(value);
  }

  Future<void> select(ProxyNode node) async {
    final current = group;
    if (current != null && current.selectable) {
      await core.selectProxy(current.name, node.name);
    }
  }

  Future<void> test(ProxyNode node) async {
    if (!testing.add(node.name)) return;
    try {
      await core.testDelay(node.name);
    } finally {
      testing.remove(node.name);
    }
  }

  Future<void> testGroup(ProxyGroup value) async {
    if (!testingGroups.add(value.name)) return;
    try {
      final nodes = value.nodes;
      for (var offset = 0; offset < nodes.length; offset += 8) {
        await Future.wait(nodes.skip(offset).take(8).map(test));
      }
      await core.refreshRuntime();
    } finally {
      testingGroups.remove(value.name);
    }
  }

  Future<void> testAll() async {
    if (testingAll.value) return;
    testingAll.value = true;
    try {
      await core.testAll();
    } finally {
      testingAll.value = false;
    }
  }

  List<ProxyGroup> _parsePreviewGroups(Map<String, dynamic> config) {
    final nodesByName = <String, ProxyNode>{};
    for (final raw in config['proxies'] as List? ?? const []) {
      if (raw is! Map || raw['name'] is! String || raw['type'] is! String) {
        continue;
      }
      final name = raw['name'] as String;
      nodesByName[name] = ProxyNode(name: name, type: raw['type'] as String);
    }

    final groupTypes = <String, String>{};
    final rawGroups = config['proxy-groups'] as List? ?? const [];
    for (final raw in rawGroups) {
      if (raw is Map && raw['name'] is String && raw['type'] is String) {
        groupTypes[raw['name'] as String] = raw['type'] as String;
      }
    }

    final result = <ProxyGroup>[];
    for (final raw in rawGroups) {
      if (raw is! Map || raw['name'] is! String || raw['type'] is! String) {
        continue;
      }
      final name = raw['name'] as String;
      final type = raw['type'] as String;
      final names = _proxyNames(raw['proxies']);
      final effectiveNames = names.isEmpty && nodesByName.isNotEmpty
          ? nodesByName.keys.toList()
          : names;
      final nodes = <ProxyNode>[];
      final seen = <String>{};
      for (final nodeName in effectiveNames) {
        if (!seen.add(nodeName)) continue;
        nodes.add(
          nodesByName[nodeName] ??
              ProxyNode(
                name: nodeName,
                type: groupTypes[nodeName] ?? _builtInType(nodeName),
              ),
        );
      }
      final selected = raw['now'] is String && (raw['now'] as String).isNotEmpty
          ? raw['now'] as String
          : nodes.firstOrNull?.name ?? '';
      result.add(
        ProxyGroup(name: name, type: type, selected: selected, nodes: nodes),
      );
    }

    if (result.isEmpty && nodesByName.isNotEmpty) {
      final nodes = nodesByName.values.toList(growable: false);
      result.add(
        ProxyGroup(
          name: '全部节点',
          type: 'Proxy',
          selected: nodes.first.name,
          nodes: nodes,
        ),
      );
    }
    return result;
  }

  static List<String> _proxyNames(dynamic value) => value is List
      ? value.whereType<String>().where((name) => name.isNotEmpty).toList()
      : const [];

  static String _builtInType(String name) {
    switch (name.toUpperCase()) {
      case 'DIRECT':
      case 'REJECT':
      case 'REJECT-DROP':
      case 'PASS':
        return 'Built-in';
      default:
        return 'Proxy group';
    }
  }
}
