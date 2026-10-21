import 'package:get/get.dart';

import '../../../domains/proxy_group.dart';
import '../../../services/core_service.dart';
import '../../../services/settings_service.dart';

class ProxiesController extends GetxController {
  ProxiesController(this.core, this.settings);

  final CoreService core;
  final SettingsService settings;
  final query = ''.obs;
  final selectedGroup = ''.obs;
  final grid = true.obs;
  final testing = <String>{}.obs;
  final testingAll = false.obs;

  @override
  void onInit() {
    super.onInit();
    grid.value = settings.fields['proxyLayout'] != 'list';
  }

  ProxyGroup? get group {
    final groups = core.groups;
    return groups.firstWhereOrNull(
          (item) => item.name == selectedGroup.value,
        ) ??
        groups.firstOrNull;
  }

  String get sort => settings.fields['proxySort'] as String? ?? 'default';
  bool get hideUnavailable => settings.fields['hideUnavailable'] == true;
  int? delay(ProxyNode node) => core.delays[node.name] ?? node.delay;

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

  Future<void> testAll() async {
    if (testingAll.value) return;
    testingAll.value = true;
    try {
      await core.testAll();
    } finally {
      testingAll.value = false;
    }
  }
}
