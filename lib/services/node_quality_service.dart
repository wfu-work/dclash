import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/node_quality.dart';
import 'core_service.dart';

/// Bounded local latency history from existing delay-test results.
class NodeQualityService extends GetxService {
  NodeQualityService(
    this.core, {
    this.memoryOnly = false,
    this.preferences,
    DateTime Function()? clock,
    this.maxSamplesPerNode = 1440,
    this.maxNodes = 200,
  }) : _clock = clock ?? DateTime.now;

  static const storageKey = 'cloudrift.node-quality.v1';
  static const retention = Duration(days: 30);
  final CoreService core;
  final bool memoryOnly;
  final SharedPreferences? preferences;
  final DateTime Function() _clock;
  final int maxSamplesPerNode, maxNodes;
  final revision = 0.obs;
  final running = false.obs;
  final _observedDelays = <String, int>{};
  final _samples = <String, List<NodeQualitySample>>{};
  SharedPreferences? _preferences;
  Worker? _worker, _settingsWorker;
  Future<void> _writes = Future.value();
  Timer? _timer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!memoryOnly) {
      _preferences = preferences ?? await SharedPreferences.getInstance();
      _restore(_preferences!.getString(storageKey));
    }
    _prune();
    _observedDelays.addAll(core.delays);
    _worker = ever(core.delays, _recordDelays);
    _settingsWorker = ever(core.settings.fields, (_) {
      _prune();
      revision.value++;
      _scheduleSave();
    });
  }

  void _recordDelays(Map<String, int> values) {
    var changed = false;
    _observedDelays.removeWhere((key, _) => !values.containsKey(key));
    for (final entry in values.entries) {
      if (entry.key.trim().isEmpty) continue;
      final previous = _observedDelays[entry.key];
      _observedDelays[entry.key] = entry.value;
      if (previous == entry.value ||
          core.settings.fields['recordNodeQuality'] == false) {
        continue;
      }
      changed = true;
      final list = _samples.putIfAbsent(entry.key, () => []);
      list.add(NodeQualitySample(at: _clock().toUtc(), delay: entry.value));
    }
    if (!changed) return;
    _prune();
    revision.value++;
    _scheduleSave();
  }

  List<NodeQualitySummary> summaries(Duration window) {
    final after = _clock().toUtc().subtract(window);
    return _samples.entries.map((entry) {
      final samples = entry.value
          .where((sample) => !sample.at.isBefore(after))
          .toList();
      final successful = samples.where((sample) => sample.delay >= 0).toList();
      final average = successful.isEmpty
          ? null
          : successful.map((sample) => sample.delay).reduce((a, b) => a + b) ~/
                successful.length;
      final jitter = successful.length < 2 || average == null
          ? null
          : sqrt(
              successful
                      .map((sample) => pow(sample.delay - average, 2))
                      .reduce((a, b) => a + b) /
                  successful.length,
            ).round();
      return NodeQualitySummary(
        name: entry.key,
        samples: samples,
        average: average,
        jitter: jitter,
        failureRate: samples.isEmpty
            ? 0
            : samples.where((sample) => sample.delay < 0).length /
                  samples.length,
        lastDelay: samples.isEmpty ? null : samples.last.delay,
      );
    }).toList()..sort((a, b) {
      final av = a.unavailable ? 1 : 0;
      final bv = b.unavailable ? 1 : 0;
      if (av != bv) return av.compareTo(bv);
      return (a.average ?? 1 << 30).compareTo(b.average ?? 1 << 30);
    });
  }

  Future<void> testAll() async {
    if (running.value || !core.running) return;
    running.value = true;
    try {
      await core.testAll();
    } finally {
      running.value = false;
    }
  }

  Future<void> test(String node) async {
    if (running.value || !core.running || node.isEmpty) return;
    running.value = true;
    try {
      await core.testDelay(node);
    } finally {
      running.value = false;
    }
  }

  void _prune() {
    final cutoff = _clock().toUtc().subtract(
      Duration(
        days: core.settings.fields['historyRetentionDays'] as int? ?? 30,
      ),
    );
    _samples.removeWhere((_, values) {
      values.removeWhere((sample) => sample.at.isBefore(cutoff));
      if (values.length > maxSamplesPerNode) {
        values.removeRange(0, values.length - maxSamplesPerNode);
      }
      return values.isEmpty;
    });
    if (_samples.length > maxNodes) {
      final names = _samples.keys.toList()
        ..sort((a, b) {
          final at = _samples[a]!.last.at;
          final bt = _samples[b]!.last.at;
          return at.compareTo(bt);
        });
      for (final name in names.take(_samples.length - maxNodes)) {
        _samples.remove(name);
      }
    }
  }

  void _restore(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['nodes'] is! Map) {
        return;
      }
      for (final entry in (decoded['nodes'] as Map).entries) {
        if (entry.key is! String ||
            entry.key.isEmpty ||
            entry.key.length > 256 ||
            entry.value is! List) {
          continue;
        }
        try {
          _samples[entry.key as String] = [
            for (final value in entry.value as List)
              NodeQualitySample.fromMap(value),
          ]..sort((a, b) => a.at.compareTo(b.at));
        } on Object {
          // A malformed node must not prevent other histories from loading.
        }
      }
    } on FormatException {
      // A future valid delay result replaces corrupt history.
    }
  }

  int get storedBytes => utf8
      .encode(
        jsonEncode({
          'version': 1,
          'nodes': {
            for (final entry in _samples.entries)
              entry.key: entry.value.map((sample) => sample.toMap()).toList(),
          },
        }),
      )
      .length;

  Future<void> clear() async {
    _samples.clear();
    revision.value++;
    await flush();
  }

  void _scheduleSave() {
    _timer ??= Timer(const Duration(seconds: 2), () {
      _timer = null;
      unawaited(flush().catchError((Object _) {}));
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final result = _writes.then((_) async {
      if (!memoryOnly) {
        final saved = await _preferences!.setString(
          storageKey,
          jsonEncode({
            'version': 1,
            'nodes': {
              for (final entry in _samples.entries)
                entry.key: entry.value.map((sample) => sample.toMap()).toList(),
            },
          }),
        );
        if (!saved) throw StateError('Could not save node quality history');
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void onClose() {
    _worker?.dispose();
    _settingsWorker?.dispose();
    unawaited(flush().catchError((Object _) {}));
    super.onClose();
  }
}
