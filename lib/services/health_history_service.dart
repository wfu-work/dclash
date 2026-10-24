import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/network_health_report.dart';
import 'settings_service.dart';

/// Stores a small local-only ring buffer of completed health reports.
class HealthHistoryService extends GetxService {
  HealthHistoryService({
    this.memoryOnly = false,
    this.preferences,
    this.maxEntries = 20,
    this.settings,
  });

  static const _storageKey = 'cloudrift.network-health-history.v1';
  final bool memoryOnly;
  final SharedPreferences? preferences;
  final int maxEntries;
  final SettingsService? settings;
  Worker? _settingsWorker;
  final entries = <HealthReportEntry>[].obs;
  SharedPreferences? _preferences;
  Future<void> _writes = Future.value();

  int get storedBytes =>
      utf8.encode(jsonEncode(entries.map((e) => e.toMap()).toList())).length;

  List<HealthReportEntry> _retained(Iterable<HealthReportEntry> values) {
    final cutoff = DateTime.now().subtract(
      Duration(days: settings?.fields['historyRetentionDays'] as int? ?? 30),
    );
    return values
        .where((e) => settings == null || !e.checkedAt.isBefore(cutoff))
        .take(maxEntries)
        .toList();
  }

  Future<void> initialize() async {
    if (settings != null) {
      _settingsWorker = ever(settings!.fields, (_) {
        unawaited(
          _enqueue(
            () => _persist(_retained(entries)),
          ).catchError((Object _) {}),
        );
      });
    }
    if (!memoryOnly) {
      _preferences = preferences ?? await SharedPreferences.getInstance();
    }
    final raw = _preferences?.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('History is not a list');
      }
      final loaded = <HealthReportEntry>[];
      final ids = <String>{};
      for (final value in decoded) {
        if (value is! Map) continue;
        try {
          final entry = HealthReportEntry.fromMap(value);
          if (ids.add(entry.id)) loaded.add(entry);
        } on Object {
          // An older or malformed record must not prevent the app from opening.
        }
      }
      loaded.sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
      entries.assignAll(_retained(loaded));
    } on FormatException {
      // Keep the corrupt persisted payload untouched; a future new report will
      // replace it with a valid bounded history.
    }
  }

  Future<void> add(HealthReportEntry entry) => _enqueue(() async {
    if (settings?.fields['recordHealthHistory'] == false) return;
    final next = [
      entry,
      ...entries.where((existing) => existing.id != entry.id),
    ]..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    await _persist(_retained(next));
  });

  Future<void> remove(String id) => _enqueue(() async {
    await _persist(
      entries.where((entry) => entry.id != id).toList(growable: false),
    );
  });

  Future<void> clear() => _enqueue(() => _persist(<HealthReportEntry>[]));

  Future<void> _persist(List<HealthReportEntry> next) async {
    if (!memoryOnly) {
      final saved = await _preferences!.setString(
        _storageKey,
        jsonEncode(next.map((entry) => entry.toMap()).toList(growable: false)),
      );
      if (!saved) throw StateError('Could not save network health history');
    }
    entries.assignAll(next);
  }

  @override
  void onClose() {
    _settingsWorker?.dispose();
    super.onClose();
  }

  Future<T> _enqueue<T>(Future<T> Function() write) {
    final result = _writes.then((_) => write());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
