import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/clash_connection.dart';
import '../domains/traffic_statistics.dart';
import 'core_service.dart';

class TrafficStatisticsService extends GetxService with WidgetsBindingObserver {
  TrafficStatisticsService(
    this.core, {
    this.memoryOnly = false,
    this.preferences,
    DateTime Function()? clock,
    this.saveInterval = const Duration(seconds: 5),
    this.maxKeysPerDay = 500,
    this.maxTrackedConnections = 10000,
  }) : assert(maxKeysPerDay > 0),
       assert(maxTrackedConnections > 0),
       _clock = clock ?? DateTime.now;

  static const storageKey = 'cloudrift.traffic-statistics.v1';
  static const retentionDays = 30;
  // Labels cannot collide with native names, which have NULs stripped.
  static const unknown = '\u0000unknown';
  static const other = '\u0000other';
  final CoreService core;
  final bool memoryOnly;
  final SharedPreferences? preferences;
  final DateTime Function() _clock;
  final Duration saveInterval;
  final int maxKeysPerDay, maxTrackedConnections;
  final revision = 0.obs;
  final saveError = false.obs;
  final _days = <String, _DayUsage>{};
  final _tracked = <String, _TrackedConnection>{};
  final _workers = <Worker>[];
  SharedPreferences? _preferences;
  Future<void> _writes = Future.value();
  Timer? _saveTimer, _dateTimer;
  int? _session;
  TrafficAmount? _lastTotals;
  DateTime? _forgottenBefore;
  bool _initialized = false, _closed = false;
  int _savedRevision = 0;
  bool _seedAfterOptOut = false;

  DateTime get today {
    final now = _clock().toLocal();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!memoryOnly) {
      _preferences = preferences ?? await SharedPreferences.getInstance();
      _restore(_preferences!.getString(storageKey));
    }
    if (_prune()) _changed();
    final previous = core.trafficUpdate.value;
    if (previous != null) _accept(previous, seed: true);
    _workers.add(
      ever(core.trafficUpdate, (update) {
        if (update != null) _accept(update);
      }),
    );
    _workers.add(
      ever(core.status, (_) {
        if (!core.running) _flushQuietly();
      }),
    );
    _workers.add(
      ever(core.settings.fields, (_) {
        if (core.settings.fields['recordTraffic'] == false) {
          _lastTotals = null;
          _tracked.clear();
          _seedAfterOptOut = true;
          _forgottenBefore = _clock();
        }
        if (_prune()) _changed();
      }),
    );
    WidgetsBinding.instance.addObserver(this);
    var lastDate = today;
    _dateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (lastDate == today) return;
      lastDate = today;
      _prune();
      _changed();
    });
  }

  List<DailyTrafficUsage> dailyUsage(TrafficPeriod period) => [
    for (var index = 0; index < period.days; index++)
      // Calendar arithmetic also works on days with a DST clock change.
      for (final date in [DateTime(today.year, today.month, today.day - index)])
        DailyTrafficUsage(date, _days[_key(date)]?.total ?? TrafficAmount.zero),
  ];

  TrafficAmount usage(TrafficPeriod period, {DateTime? date}) => date != null
      ? _days[_key(date)]?.total ?? TrafficAmount.zero
      : dailyUsage(
          period,
        ).fold(TrafficAmount.zero, (sum, day) => sum + day.usage);

  List<TrafficRankingEntry> ranking(
    TrafficDimension dimension,
    TrafficPeriod period, {
    TrafficSort sort = TrafficSort.total,
    DateTime? date,
  }) {
    final combined = <String, TrafficAmount>{};
    final dates = date == null
        ? dailyUsage(period).map((day) => day.date)
        : [date];
    for (final day in dates) {
      final values = _days[_key(day)]?.rankings[dimension];
      if (values == null) continue;
      for (final entry in values.entries) {
        combined[entry.key] =
            (combined[entry.key] ?? TrafficAmount.zero) + entry.value;
      }
    }
    return combined.entries
        .map((entry) => TrafficRankingEntry(entry.key, entry.value))
        .toList()
      ..sort((a, b) {
        final order = b.usage.valueFor(sort).compareTo(a.usage.valueFor(sort));
        return order != 0 ? order : a.name.compareTo(b.name);
      });
  }

  void _accept(CoreTrafficUpdate update, {bool seed = false}) {
    if (_closed || core.preview) return;
    if (core.settings.fields['recordTraffic'] == false) {
      _lastTotals = null;
      _tracked.clear();
      _seedAfterOptOut = true;
      return;
    }
    if (_session != update.session || update.baseline) {
      _session = update.session;
      _lastTotals = null;
      _forgottenBefore = null;
      _tracked.clear();
    }
    seed = seed || _seedAfterOptOut;
    _seedAfterOptOut = false;
    final date = _key(today);
    var changed = _prune();
    if (update.totals case final totals?
        when totals.upload >= 0 && totals.download >= 0) {
      final previous = _lastTotals;
      _lastTotals = totals;
      if (!seed && !update.baseline && previous != null) {
        // A reset is a new counter interval; upload/download reset separately.
        final delta = TrafficAmount(
          _delta(totals.upload, previous.upload, reset: true),
          _delta(totals.download, previous.download, reset: true),
        );
        if (delta.total > 0) {
          final bucket = _days.putIfAbsent(date, _DayUsage.new);
          bucket.total = bucket.total + delta;
          changed = true;
        }
      }
    }
    for (final connection in update.connections) {
      changed =
          _connection(
            connection.id,
            connection.upload,
            connection.download,
            date,
            connection: connection,
            seed: seed || update.baseline,
          ) ||
          changed;
    }
    for (final counter in update.counters) {
      changed =
          _connection(
            counter.id,
            counter.upload,
            counter.download,
            date,
            seed: seed || update.baseline,
          ) ||
          changed;
    }
    if (changed) _changed();
  }

  bool _connection(
    String id,
    int upload,
    int download,
    String date, {
    ClashConnection? connection,
    required bool seed,
  }) {
    if (id.isEmpty || upload < 0 || download < 0) return false;
    final previous = _tracked.remove(id);
    // A final event without metadata cannot safely resurrect an evicted ID.
    if (previous == null && connection == null) return false;
    final evicted =
        previous == null &&
        _forgottenBefore != null &&
        !connection!.startedAt.isAfter(_forgottenBefore!);
    final tracked = previous ?? _TrackedConnection();
    _tracked[id] = tracked;
    if (connection != null) {
      tracked.startedAt = connection.startedAt;
      tracked.names = {
        TrafficDimension.application: _label(
          connection.process.replaceAll('\\', '/').split('/').last,
        ),
        TrafficDimension.domain: _domain(connection.host),
        TrafficDimension.node: _label(connection.chains.firstOrNull ?? ''),
      };
    }
    // Poll replies and final events can arrive out of order. Keep high-water
    // marks until the runtime changes; an older reply must never add bytes.
    final delta = TrafficAmount(
      _delta(upload, tracked.upload),
      _delta(download, tracked.download),
    );
    tracked.upload = math.max(tracked.upload, upload);
    tracked.download = math.max(tracked.download, download);
    while (_tracked.length > maxTrackedConnections) {
      final removed = _tracked.remove(_tracked.keys.first)!;
      if (_forgottenBefore == null ||
          removed.startedAt.isAfter(_forgottenBefore!)) {
        _forgottenBefore = removed.startedAt;
      }
    }
    if (seed || evicted || delta.total == 0) return false;
    final bucket = _days.putIfAbsent(date, _DayUsage.new);
    for (final dimension in TrafficDimension.values) {
      final map = bucket.rankings[dimension]!;
      var name = tracked.names[dimension] ?? unknown;
      if (!map.containsKey(name) &&
          map.length >= maxKeysPerDay &&
          name != unknown) {
        name = other;
      }
      map[name] = (map[name] ?? TrafficAmount.zero) + delta;
    }
    return true;
  }

  static int _delta(int current, int previous, {bool reset = false}) =>
      current >= previous
      ? current - previous
      : reset
      ? math.max(0, current)
      : 0;

  static String _label(String text) {
    final value = text.replaceAll('\u0000', '').trim();
    return value.isEmpty
        ? unknown
        : value.substring(0, math.min(value.length, 256));
  }

  static String _domain(String text) {
    var value = text.trim().toLowerCase();
    if (value.contains('://')) value = Uri.tryParse(value)?.host ?? '';
    return _label(value.replaceFirst(RegExp(r'\.$'), ''));
  }

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _prune() {
    final length = _days.length;
    final first = _key(
      DateTime(
        today.year,
        today.month,
        today.day -
            (core.settings.fields['historyRetentionDays'] as int? ??
                retentionDays) +
            1,
      ),
    );
    final last = _key(today);
    _days.removeWhere(
      (key, _) => key.compareTo(first) < 0 || key.compareTo(last) > 0,
    );
    return length != _days.length;
  }

  void _changed() {
    revision.value++;
    if (!_closed && _saveTimer == null) {
      _saveTimer = Timer(saveInterval, () {
        _saveTimer = null;
        _flushQuietly();
      });
    }
  }

  void _restore(String? raw) {
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['days'] is! Map) return;
      for (final entry in (data['days'] as Map).entries) {
        try {
          final key = entry.key;
          if (key is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) {
            continue;
          }
          final parsed = DateTime.tryParse(key);
          if (parsed == null || _key(parsed) != key) continue;
          _days[key] = _DayUsage.fromMap(entry.value, maxKeysPerDay);
        } on Object {
          // Skip a damaged day without losing the remaining history.
        }
      }
    } on FormatException {
      // A malformed payload must not prevent startup.
    }
  }

  /// Writes are serialized, and counters keep updating while storage is busy.
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final write = _writes.then((_) async {
      if (_savedRevision == revision.value) return;
      final savingRevision = revision.value;
      try {
        if (!memoryOnly) {
          final saved = await _preferences!.setString(
            storageKey,
            jsonEncode({
              'version': 1,
              'days': {
                for (final entry in _days.entries)
                  entry.key: entry.value.toMap(),
              },
            }),
          );
          if (!saved) throw StateError('Could not save traffic statistics');
        }
        _savedRevision = savingRevision;
        saveError.value = false;
      } on Object {
        saveError.value = true;
        rethrow;
      }
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  int get storedBytes => utf8
      .encode(
        jsonEncode({
          'version': 1,
          'days': {
            for (final entry in _days.entries) entry.key: entry.value.toMap(),
          },
        }),
      )
      .length;

  Future<void> clear() async {
    // Keep live counter baselines so bytes before this action cannot return.
    _days.clear();
    _forgottenBefore = _clock();
    _changed();
    await flush();
  }

  void _flushQuietly() => unawaited(flush().catchError((Object _) {}));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushQuietly();
  }

  @override
  void onClose() {
    if (_closed) return;
    _closed = true;
    _saveTimer?.cancel();
    _dateTimer?.cancel();
    for (final worker in _workers) {
      worker.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    _flushQuietly();
    super.onClose();
  }
}

class _TrackedConnection {
  int upload = 0, download = 0;
  DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Map<TrafficDimension, String> names = {};
}

class _DayUsage {
  TrafficAmount total = TrafficAmount.zero;
  final rankings = {
    for (final dimension in TrafficDimension.values)
      dimension: <String, TrafficAmount>{},
  };

  Map<String, dynamic> toMap() => {
    'total': total.toMap(),
    for (final dimension in TrafficDimension.values)
      dimension.name: {
        for (final entry in rankings[dimension]!.entries)
          entry.key: entry.value.toMap(),
      },
  };

  _DayUsage();

  factory _DayUsage.fromMap(Object? data, int maxKeys) {
    if (data is! Map) throw const FormatException('Invalid daily usage');
    final day = _DayUsage()..total = TrafficAmount.fromMap(data['total']);
    for (final dimension in TrafficDimension.values) {
      final entries = data[dimension.name];
      if (entries is! Map || entries.length > maxKeys + 2) {
        throw const FormatException('Invalid traffic ranking');
      }
      for (final entry in entries.entries) {
        if (entry.key is! String ||
            (entry.key as String).isEmpty ||
            (entry.key as String).length > 256) {
          throw const FormatException('Invalid ranking name');
        }
        day.rankings[dimension]![entry.key as String] = TrafficAmount.fromMap(
          entry.value,
        );
      }
    }
    return day;
  }
}
