import 'package:get/get.dart';

import '../../../../platform/installed_apps.dart';

class InstalledAppsController extends GetxController {
  InstalledAppsController({
    required Iterable<String> selected,
    required this.persist,
    InstalledApps? catalog,
  }) : catalog = catalog ?? AndroidInstalledApps() {
    this.selected.addAll(selected);
  }

  final InstalledApps catalog;
  final Future<void> Function(List<String>) persist;
  final apps = <InstalledApp>[].obs;
  final selected = <String>{}.obs;
  final query = ''.obs;
  final showSystem = false.obs;
  final internetOnly = true.obs;
  final selectedOnly = false.obs;
  final permissionGranted = true.obs;
  final loading = false.obs;
  final saving = false.obs;
  final error = RxnString();
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  List<InstalledApp> get visibleApps {
    final search = query.value.trim().toLowerCase();
    final installed = apps.map((app) => app.packageName).toSet();
    final entries = [
      ...apps,
      for (final name in selected.where((name) => !installed.contains(name)))
        InstalledApp(packageName: name, label: name, installed: false),
    ];
    final result = entries.where((app) {
      // Saved selections remain reachable even when system/network filters hide
      // other apps, including package names not installed on this device.
      final checked = selected.contains(app.packageName);
      return (!selectedOnly.value || checked) &&
          (checked || showSystem.value || !app.system) &&
          (checked || !internetOnly.value || app.internet) &&
          (search.isEmpty ||
              '${app.label} ${app.packageName}'.toLowerCase().contains(search));
    }).toList();
    result.sort((a, b) {
      final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return byLabel == 0 ? a.packageName.compareTo(b.packageName) : byLabel;
    });
    return result;
  }

  Future<void> load({bool requestPermission = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    try {
      final granted = requestPermission
          ? await catalog.requestPermission()
          : await catalog.hasPermission();
      if (_closed) return;
      permissionGranted.value = granted;
      final result = await catalog.load();
      if (_closed) return;
      apps.assignAll(result);
    } on Object catch (failure) {
      if (!_closed) error.value = failure.toString();
    } finally {
      if (!_closed) loading.value = false;
    }
  }

  void toggle(String packageName, bool enabled) {
    if (saving.value) return;
    if (enabled) {
      selected.add(packageName);
    } else {
      selected.remove(packageName);
    }
  }

  Future<bool> save() async {
    if (saving.value) return false;
    saving.value = true;
    error.value = null;
    try {
      final packages = selected.toList()..sort();
      await persist(packages);
      return true;
    } on Object catch (failure) {
      if (!_closed) error.value = failure.toString();
      return false;
    } finally {
      if (!_closed) saving.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }
}
