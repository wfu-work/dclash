import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/diagnostic_privacy.dart';
import '../domains/network_health.dart';
import '../domains/network_timeline.dart';
import 'core_service.dart';
import 'health_history_service.dart';
import 'settings_service.dart';
import 'traffic_statistics_service.dart';

/// A bounded, local-only record of state changes and actionable failures.
class NetworkTimelineService extends GetxService {
  NetworkTimelineService(
    this.core,
    this.settings,
    this.health,
    this.traffic, {
    this.memoryOnly = false,
    this.preferences,
    DateTime Function()? clock,
    this.maxEntries = 300,
    this.retention = const Duration(days: 14),
  }) : _clock = clock ?? DateTime.now;

  static const storageKey = 'cloudrift.network-timeline.v1';
  final CoreService core;
  final SettingsService settings;
  final HealthHistoryService health;
  final TrafficStatisticsService traffic;
  final bool memoryOnly;
  final SharedPreferences? preferences;
  final DateTime Function() _clock;
  final int maxEntries;
  final Duration retention;
  final entries = <NetworkTimelineEvent>[].obs;
  final _workers = <Worker>[];
  final _knownReports = <String>{};
  final _knownLogs = <String>{};
  SharedPreferences? _preferences;
  Future<void> _writes = Future.value();
  String _status = '';
  String _error = '';
  String _settingsFingerprint = '';
  int? _routeEpoch, _routePicks;
  bool _trafficSaveError = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!memoryOnly) {
      _preferences = preferences ?? await SharedPreferences.getInstance();
      _restore(_preferences!.getString(storageKey));
    }
    _prune();
    _status = core.status.value.name;
    _error = core.error.value ?? '';
    _settingsFingerprint = _fingerprint();
    _routeEpoch = core.routeState['core-epoch'] as int?;
    _routePicks = core.routeState['picks-version'] as int?;
    _trafficSaveError = traffic.saveError.value;
    _knownReports.addAll(health.entries.map((entry) => entry.id));
    _knownLogs.addAll(core.logs.map(_logSignature));
    _workers.add(ever(core.status, (value) => _onStatus(value.name)));
    _workers.add(ever(core.error, (value) => _onError(value?.toString())));
    _workers.add(ever(core.routeState, (_) => _onRoute()));
    _workers.add(
      ever(settings.fields, (_) {
        _onSettings();
        _prune();
        _schedulePersist();
      }),
    );
    _workers.add(ever(health.entries, (_) => _onHealthReports()));
    _workers.add(ever(core.logs, (_) => _onLogs()));
    _workers.add(
      ever(traffic.saveError, (value) => _onTrafficSaveError(value)),
    );
  }

  void _onStatus(String value) {
    if (value == _status) return;
    _status = value;
    add(
      kind: TimelineKind.core,
      severity: value == 'failed'
          ? TimelineSeverity.error
          : TimelineSeverity.info,
      titleKey: 'timelineCoreStatus',
      params: {'status': value},
    );
  }

  void _onError(String? value) {
    final next = value ?? '';
    if (next.isEmpty || next == _error) {
      _error = next;
      return;
    }
    _error = next;
    add(
      kind: TimelineKind.error,
      severity: TimelineSeverity.error,
      titleKey: 'timelineCoreError',
      detail: DiagnosticPrivacy.sanitize(next, maxLength: 240),
    );
  }

  void _onRoute() {
    final epoch = core.routeState['core-epoch'] as int?;
    final picks = core.routeState['picks-version'] as int?;
    if (epoch == null ||
        picks == null ||
        (epoch == _routeEpoch && picks == _routePicks)) {
      return;
    }
    _routeEpoch = epoch;
    _routePicks = picks;
    add(
      kind: TimelineKind.route,
      severity: TimelineSeverity.info,
      titleKey: 'timelineRouteChanged',
    );
  }

  String _fingerprint() => jsonEncode([
    settings.fields['mode'],
    settings.fields['systemProxy'],
    settings.fields['tunEnabled'],
    settings.fields['mixedPort'],
    settings.fields['dnsOverride'].toString().isNotEmpty,
  ]);

  void _onSettings() {
    final current = _fingerprint();
    if (current == _settingsFingerprint) return;
    final previous = jsonDecode(_settingsFingerprint) as List;
    final next = jsonDecode(current) as List;
    _settingsFingerprint = current;
    if (previous[0] != next[0]) {
      add(
        kind: TimelineKind.settings,
        severity: TimelineSeverity.info,
        titleKey: 'timelineModeChanged',
        params: {'mode': '${next[0]}'},
      );
    }
    if (previous[1] != next[1]) {
      add(
        kind: TimelineKind.settings,
        severity: TimelineSeverity.info,
        titleKey: 'timelineSystemProxyChanged',
        params: {'state': next[1] == true ? 'enabled' : 'disabled'},
      );
    }
    if (previous[2] != next[2]) {
      add(
        kind: TimelineKind.settings,
        severity: TimelineSeverity.info,
        titleKey: 'timelineTunChanged',
        params: {'state': next[2] == true ? 'enabled' : 'disabled'},
      );
    }
    if (previous[3] != next[3] || previous[4] != next[4]) {
      add(
        kind: TimelineKind.settings,
        severity: TimelineSeverity.info,
        titleKey: 'timelineNetworkSettingsChanged',
      );
    }
  }

  void _onHealthReports() {
    for (final report in health.entries) {
      if (!_knownReports.add(report.id)) continue;
      final failed = report.results.values
          .where((result) => result.status == HealthStatus.failed)
          .length;
      final warning = report.results.values
          .where((result) => result.status == HealthStatus.warning)
          .length;
      add(
        kind: TimelineKind.health,
        severity: failed > 0
            ? TimelineSeverity.error
            : warning > 0
            ? TimelineSeverity.warning
            : TimelineSeverity.info,
        titleKey: failed == 0 && warning == 0
            ? 'timelineHealthPassed'
            : 'timelineHealthAttention',
        params: {'failed': '$failed', 'warnings': '$warning'},
        occurredAt: report.checkedAt,
      );
    }
  }

  void _onLogs() {
    for (final log in core.logs) {
      final signature = _logSignature(log);
      if (!_knownLogs.add(signature)) continue;
      final level = log.level.toLowerCase();
      if (level != 'error' && level != 'warn' && level != 'warning') continue;
      add(
        kind: TimelineKind.error,
        severity: level == 'error'
            ? TimelineSeverity.error
            : TimelineSeverity.warning,
        titleKey: 'timelineLogIssue',
        detail: DiagnosticPrivacy.sanitize(log.message, maxLength: 240),
        occurredAt: log.time,
      );
    }
    while (_knownLogs.length > 1200) {
      _knownLogs.remove(_knownLogs.first);
    }
  }

  static String _logSignature(dynamic log) =>
      '${log.time.toUtc().microsecondsSinceEpoch}:${log.level}:${log.message.hashCode}';

  void _onTrafficSaveError(bool value) {
    if (value == _trafficSaveError) return;
    _trafficSaveError = value;
    if (value) {
      add(
        kind: TimelineKind.traffic,
        severity: TimelineSeverity.warning,
        titleKey: 'timelineTrafficSaveFailed',
      );
    }
  }

  void add({
    required TimelineKind kind,
    required TimelineSeverity severity,
    required String titleKey,
    Map<String, String> params = const {},
    String detail = '',
    DateTime? occurredAt,
  }) {
    if (settings.fields['recordTimeline'] == false) return;
    final event = NetworkTimelineEvent.create(
      kind: kind,
      severity: severity,
      titleKey: titleKey,
      params: {
        for (final entry in params.entries.take(8))
          DiagnosticPrivacy.sanitize(entry.key, maxLength: 64):
              DiagnosticPrivacy.sanitize(entry.value, maxLength: 256),
      },
      detail: DiagnosticPrivacy.sanitize(detail, maxLength: 512),
      occurredAt: occurredAt ?? _clock(),
    );
    entries.insert(0, event);
    _prune();
    _schedulePersist();
  }

  int get storedBytes =>
      utf8.encode(jsonEncode(entries.map((e) => e.toMap()).toList())).length;

  Future<void> clear() async {
    entries.clear();
    await _persist();
  }

  void _prune() {
    final cutoff = _clock().toUtc().subtract(
      Duration(
        days:
            settings.fields['historyRetentionDays'] as int? ?? retention.inDays,
      ),
    );
    entries.removeWhere((entry) => entry.occurredAt.isBefore(cutoff));
    entries.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
  }

  void _restore(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final ids = <String>{};
      for (final value in decoded) {
        try {
          final event = NetworkTimelineEvent.fromMap(value);
          if (ids.add(event.id)) entries.add(event);
        } on Object {
          // One corrupt historical event must not block the timeline.
        }
      }
    } on FormatException {
      // Keep a malformed payload untouched until the next valid write.
    }
  }

  Timer? _saveTimer;
  void _schedulePersist() {
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(_persist().catchError((Object _) {}));
    });
  }

  Future<void> _persist() {
    final write = _writes.then((_) async {
      if (!memoryOnly) {
        final saved = await _preferences!.setString(
          storageKey,
          jsonEncode(entries.map((event) => event.toMap()).toList()),
        );
        if (!saved) throw StateError('Could not save network timeline');
      }
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _persist();
  }

  @override
  void onClose() {
    _saveTimer?.cancel();
    for (final worker in _workers) {
      worker.dispose();
    }
    unawaited(flush().catchError((Object _) {}));
    super.onClose();
  }
}
