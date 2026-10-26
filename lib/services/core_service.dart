import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domains/clash_connection.dart';
import '../domains/core_status.dart';
import '../domains/proxy_group.dart';
import '../domains/traffic_statistics.dart';
import '../platform/core_error.dart';
import '../platform/core_lifecycle.dart';
import '../platform/core_rpc.dart';
import '../platform/core_runtime.dart';
import '../platform/helper_client.dart';
import '../platform/startup.dart';
import '../storage/atomic_file.dart';
import 'config_builder.dart';
import 'core_ports.dart';
import 'profile_service.dart';
import 'settings_service.dart';

class CoreService extends GetxService
    with WidgetsBindingObserver
    implements
        CoreActivityPort,
        CoreLifecyclePort,
        CoreProfilePort,
        CoreProxyPort {
  CoreService(
    this.profiles,
    this.settings, {
    this.preview = false,
    CoreRuntime Function()? runtimeFactory,
    Future<Directory> Function()? supportDirectory,
    this.recoveryBaseDelay = const Duration(seconds: 1),
    this.recoveryStablePeriod = const Duration(seconds: 30),
  }) : _runtimeFactory = runtimeFactory ?? createCoreRuntime,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory {
    _lifecycle = CoreLifecycle(
      apply: _applyIntent,
      cancelStart: () => _runtime?.cancelPendingStart(),
    );
  }
  @override
  final ProfileService profiles;
  @override
  final SettingsService settings;
  final bool preview;
  final CoreRuntime Function() _runtimeFactory;
  final Future<Directory> Function() _supportDirectory;
  final Duration recoveryBaseDelay;
  final Duration recoveryStablePeriod;
  late final CoreLifecycle _lifecycle;
  @override
  final status = CoreStatus.stopped.obs;
  final error = RxnString();
  final errorCategory = Rxn<CoreErrorCategory>();
  final recovering = false.obs;
  final recoveryExhausted = false.obs;
  final recoveryAttempt = 0.obs;
  @override
  final groups = <ProxyGroup>[].obs;
  @override
  final connections = <ClashConnection>[].obs;
  final trafficUpdate = Rxn<CoreTrafficUpdate>();
  @override
  final logs = <CoreLog>[].obs;
  @override
  final requests = <Map<String, dynamic>>[].obs;
  @override
  final dnsQueries = <Map<String, dynamic>>[].obs;
  final providers = <Map<String, dynamic>>[].obs;
  final routeState = <String, dynamic>{}.obs;
  final _routeWatchers = <Object>{};
  final upload = 0.obs,
      download = 0.obs,
      totalUpload = 0.obs,
      totalDownload = 0.obs,
      memory = 0.obs;
  final startedAt = Rxn<DateTime>();
  final version = ''.obs;
  @override
  final delays = <String, int>{}.obs;
  CoreRuntime? _runtime;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _pollTimer;
  Timer? _recoveryTimer, _recoveryStableTimer;
  Worker? _settingsWorker, _profileWorker, _profileContentWorker;
  String _observedProfile = '';
  bool _initialized = false;
  bool _polling = false;
  bool _foreground = true;
  int? _scheduledInterval;
  bool _maintenance = false;
  int _recoveryGeneration = 0;
  static const _maxRecoveryAttempts = 3;
  int _epoch = 0;
  String _appliedSettings = '';
  String _desiredFingerprint = '';
  String? _appliedProfile;
  @override
  bool get running => status.value == CoreStatus.running;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    if (preview) {
      version.value = 'Preview fixture · mihomo';
      groups.assignAll(const [
        ProxyGroup(
          name: 'Preview · Proxy',
          type: 'Selector',
          selected: 'Preview · Tokyo',
          nodes: [
            ProxyNode(name: 'Preview · Tokyo', type: 'Shadowsocks'),
            ProxyNode(name: 'Preview · Singapore', type: 'VLESS'),
          ],
        ),
      ]);
      return;
    }
    _settingsWorker = debounce(settings.fields, (_) {
      if (running && _scheduledInterval != pollIntervalSeconds) {
        _schedulePoll(_epoch);
      }
      if (_lifecycle.desired &&
          _desiredFingerprint != _fingerprint(settings.fields)) {
        unawaited(reload().catchError(_recordError));
      }
    }, time: const Duration(milliseconds: 250));
    _observedProfile = _profileFingerprint();
    _profileContentWorker = ever(profiles.profiles, (_) {
      final fingerprint = _profileFingerprint();
      if (fingerprint == _observedProfile) return;
      _observedProfile = fingerprint;
      if (_lifecycle.desired) unawaited(reload().catchError(_recordError));
    });
    _profileWorker = ever(profiles.activeId, (_) {
      if (_lifecycle.desired) unawaited(reload().catchError(_recordError));
    });
  }

  @override
  Future<void> start() {
    _cancelRecovery(resetAttempt: true);
    if (_maintenance) {
      return Future.error(
        const CoreException(
          'maintenance',
          'Wait for configuration maintenance to finish before connecting',
        ),
      );
    }
    if (preview) {
      return Future.error(
        const CoreException(
          'preview',
          'Preview is read only; VPN operations are disabled',
        ),
      );
    }
    return _lifecycle.request(true);
  }

  @override
  Future<void> stop() {
    _cancelRecovery(resetAttempt: true);
    return _lifecycle.request(false);
  }

  @override
  Future<void> toggle() => _lifecycle.desired ? stop() : start();
  @override
  Future<void> reload() {
    if (_maintenance) {
      return Future.error(
        const CoreException(
          'maintenance',
          'Configuration maintenance is still in progress',
        ),
      );
    }
    return _lifecycle.desired ? _lifecycle.request(true) : Future.value();
  }

  @override
  Future<T> withStoppedCore<T>(Future<T> Function() action) async {
    if (_maintenance ||
        _lifecycle.desired ||
        _runtime != null ||
        const [
          CoreStatus.starting,
          CoreStatus.stopping,
          CoreStatus.running,
        ].contains(status.value)) {
      throw const CoreException(
        'core_busy',
        'Stop the core before configuration maintenance',
      );
    }
    _maintenance = true;
    try {
      return await action();
    } finally {
      _maintenance = false;
    }
  }

  Future<void> _applyIntent(bool desired, int revision) async {
    if (!desired) {
      status.value = CoreStatus.stopping;
      try {
        await _tearDown();
      } catch (e) {
        _recordError(e);
        if (revision == _lifecycle.revision) status.value = CoreStatus.failed;
        rethrow;
      }
      status.value = CoreStatus.stopped;
      return;
    }
    final profile = profiles.active;
    if (profile == null) {
      await _tearDown();
      status.value = CoreStatus.failed;
      final failure = const CoreException(
        'profile_required',
        'Select or import a profile before connecting.',
      );
      _recordError(failure);
      throw failure;
    }
    _clearError();
    final fields = Map<String, dynamic>.from(settings.fields);
    final fingerprint = _fingerprint(fields);
    _desiredFingerprint = fingerprint;
    if (running &&
        _appliedSettings == fingerprint &&
        _appliedProfile == profile.id) {
      await _applyProfile(fields);
      return;
    }
    status.value = CoreStatus.starting;
    try {
      if (_runtime != null) await _tearDown();
      if (revision != _lifecycle.revision) return;
      final home = await _supportDirectory();
      await home.create(recursive: true);
      fields['providerDirectory'] = p.join(home.path, 'providers');
      fields['profileName'] = profile.name;
      final runtime = _runtime = _runtimeFactory();
      final epoch = ++_epoch;
      _eventSubscription = runtime.events.listen(
        (event) {
          if (epoch == _epoch) _handleEvent(event);
        },
        onError: (Object e) {
          if (epoch == _epoch) _recordError(e);
        },
      );
      await runtime.open(home.path, fields);
      if (revision != _lifecycle.revision) {
        await _tearDown();
        return;
      }
      TrafficAmount? baseline;
      try {
        final counters = _map(
          await runtime
              .invoke('getTotalTraffic', false)
              .timeout(const Duration(seconds: 1)),
        );
        if (counters['up'] is num && counters['down'] is num) {
          baseline = TrafficAmount(
            _integer(counters['up']),
            _integer(counters['down']),
          );
        }
      } on Object {
        // If the optional baseline is unavailable, the first poll seeds it.
      }
      if (epoch != _epoch || revision != _lifecycle.revision) return;
      trafficUpdate.value = CoreTrafficUpdate(
        session: epoch,
        baseline: true,
        totals: baseline,
      );
      final content = await ConfigBuilder.build(
        await profiles.readContent(profile),
        fields,
        script: profile.script,
        sharedScriptIds: profile.sharedScriptIds,
        profileRules: profile.standardRules,
        matchTarget: profile.matchTarget,
      );
      await writePrivateText(File(p.join(home.path, 'config.yaml')), content);
      _messageResult(
        await runtime.invoke('setupConfig', {
          'selected-map': <String, String>{},
          'test-url':
              fields['testUrl'] ?? 'https://www.gstatic.com/generate_204',
        }),
      );
      if (revision != _lifecycle.revision) {
        await _tearDown();
        return;
      }
      await runtime.start(fields);
      if (revision != _lifecycle.revision) {
        await _tearDown();
        return;
      }
      await runtime.invoke('startLog');
      try {
        version.value = '${await runtime.invoke('getVersion')}';
      } on CoreException {
        version.value = 'mihomo';
      }
      _appliedSettings = fingerprint;
      _appliedProfile = profile.id;
      startedAt.value = DateTime.now();
      recovering.value = false;
      recoveryExhausted.value = false;
      _scheduleStableRecoveryReset();
      status.value = CoreStatus.running;
      await refreshRuntime();
      _schedulePoll(epoch);
    } catch (e) {
      _recordError(e);
      try {
        await _tearDown();
      } catch (cleanup) {
        _recordError(StateError('$e; cleanup: $cleanup'));
      }
      if (revision == _lifecycle.revision) status.value = CoreStatus.failed;
      rethrow;
    }
  }

  Future<void> _applyProfile(Map<String, dynamic> fields) async {
    final profile = profiles.active;
    if (profile == null || _runtime == null) return;
    try {
      final home = await _supportDirectory();
      fields['providerDirectory'] = p.join(home.path, 'providers');
      final content = await ConfigBuilder.build(
        await profiles.readContent(profile),
        fields,
        script: profile.script,
        sharedScriptIds: profile.sharedScriptIds,
        profileRules: profile.standardRules,
        matchTarget: profile.matchTarget,
      );
      final file = File(p.join(home.path, 'config.yaml'));
      final previous = await file.exists() ? await file.readAsString() : null;
      await writePrivateText(file, content);
      try {
        _messageResult(
          await invoke('setupConfig', {
            'selected-map': {
              for (final group in groups) group.name: group.selected,
            },
            'test-url':
                fields['testUrl'] ?? 'https://www.gstatic.com/generate_204',
          }),
        );
      } catch (e) {
        if (previous != null) {
          await writePrivateText(file, previous);
        } else if (await file.exists()) {
          await file.delete();
        }
        rethrow;
      }
      await refreshRuntime();
    } catch (e) {
      _recordError(e);
      rethrow;
    }
  }

  Future<void> _tearDown() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final closingEpoch = _epoch++;
    final runtime = _runtime;
    Object? failure;
    if (runtime != null) {
      if (startedAt.value != null) {
        try {
          final snapshot = _map(
            await runtime
                .invoke('getConnections')
                .timeout(const Duration(seconds: 1)),
          );
          _publishTrafficSnapshot(snapshot, closingEpoch);
        } on Object {
          // Statistics must never prevent a failed core from stopping.
        }
      }
      try {
        await runtime.stop();
      } catch (e) {
        failure = e;
      }
      try {
        await runtime.close();
        _runtime = null;
      } catch (e) {
        failure ??= e;
      }
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    routeState.clear();
    startedAt.value = null;
    upload.value = download.value = memory.value = 0;
    connections.clear();
    _appliedProfile = null;
    if (failure != null) {
      _recordError(failure);
      throw failure;
    }
  }

  int get pollIntervalSeconds =>
      !_foreground && settings.fields['reduceBackgroundRefresh'] == true
      ? settings.fields['backgroundIntervalSeconds'] as int? ?? 5
      : settings.fields['pollIntervalSeconds'] as int? ?? 1;

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (running) _schedulePoll(_epoch);
  }

  @override
  Future<void> restart() async {
    if (!running) {
      throw const CoreException('not_running', 'Connect before restarting');
    }
    await stop();
    await start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid || Platform.isIOS) {
      setForeground(state == AppLifecycleState.resumed);
    }
  }

  void _schedulePoll(int epoch) {
    _scheduledInterval = pollIntervalSeconds;
    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(seconds: pollIntervalSeconds), () async {
      if (!running || epoch != _epoch) return;
      try {
        await _poll(epoch);
      } catch (e) {
        if (epoch == _epoch) _recordError(e);
      }
      if (running && epoch == _epoch) _schedulePoll(epoch);
    });
  }

  @override
  Future<void> refreshRuntime() async {
    if (_runtime == null) return;
    final epoch = _epoch;
    final results = await Future.wait([
      invoke('getProxies'),
      invoke('getExternalProviders'),
    ]);
    if (_runtime == null || epoch != _epoch) return;
    final proxyData = _map(results[0]);
    final map = _map(proxyData['proxies']);
    final names = proxyData['all'] as List? ?? map.keys.toList();
    groups.assignAll([
      for (final name in names)
        if (_map(map[name])['all'] is List)
          ProxyGroup(
            name: '$name',
            type: '${_map(map[name])['type'] ?? 'Selector'}',
            selected: '${_map(map[name])['now'] ?? ''}',
            nodes: [
              for (final node in _map(map[name])['all'] as List)
                ProxyNode(
                  name: '$node',
                  type: '${_map(map[node])['type'] ?? ''}',
                  delay: delays['$node'],
                  alive: delays['$node'] == null || delays['$node']! >= 0,
                ),
            ],
          ),
    ]);
    final data = results[1];
    providers.assignAll(
      data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
          : const [],
    );
    await _poll(_epoch);
  }

  Future<void> _poll(int epoch) async {
    if (_polling || _runtime == null) return;
    _polling = true;
    try {
      final results = await Future.wait([
        invoke('getTraffic', false),
        invoke('getTotalTraffic', false),
        invoke('getConnections'),
        invoke('getMemoryStats'),
      ]);
      if (epoch != _epoch) return;
      final traffic = _map(results[0]),
          total = _map(results[1]),
          snapshot = _map(results[2]),
          stats = _map(results[3]);
      upload.value = _integer(traffic['up']);
      download.value = _integer(traffic['down']);
      totalUpload.value = _integer(total['up']);
      totalDownload.value = _integer(total['down']);
      // RSS represents the memory currently resident in the core process.
      // Older cores may omit it, so retain the runtime-allocation total as a
      // compatible fallback.
      final rss = _integer(stats['rss']);
      memory.value = rss > 0
          ? rss
          : _integer(stats['heapInuse']) +
                _integer(stats['stackInuse']) +
                _integer(stats['runtimeOther']);
      final entries = (snapshot['connections'] as List? ?? [])
          .whereType<Map>()
          .take(10000)
          .map(_connectionFromMap)
          .toList();
      connections.assignAll(entries.take(5000));
      _publishTrafficSnapshot(
        snapshot,
        epoch,
        total: total,
        parsedConnections: entries,
      );
    } finally {
      _polling = false;
    }
  }

  static ClashConnection _connectionFromMap(Map raw) {
    final c = _map(raw), metadata = _map(c['metadata']);
    String firstValue(String first, String fallback) {
      final text = '${metadata[first] ?? ''}';
      return text.isNotEmpty ? text : '${metadata[fallback] ?? ''}';
    }

    return ClashConnection(
      id: '${c['id'] ?? ''}',
      host: firstValue('host', 'destinationIP'),
      network: '${metadata['network'] ?? ''}',
      source: '${metadata['sourceIP'] ?? ''}:${metadata['sourcePort'] ?? ''}',
      destination:
          '${metadata['destinationIP'] ?? ''}:${metadata['destinationPort'] ?? ''}',
      rule: '${c['rule'] ?? ''}',
      chains: (c['chains'] as List? ?? []).whereType<String>().toList(),
      upload: _integer(c['upload']),
      download: _integer(c['download']),
      startedAt: DateTime.tryParse('${c['start']}') ?? DateTime.now(),
      process: firstValue('process', 'processPath'),
    );
  }

  void _publishTrafficSnapshot(
    Map<String, dynamic> snapshot,
    int session, {
    Map<String, dynamic>? total,
    List<ClashConnection>? parsedConnections,
  }) {
    final up = snapshot['uploadTotal'] ?? total?['up'];
    final down = snapshot['downloadTotal'] ?? total?['down'];
    trafficUpdate.value = CoreTrafficUpdate(
      session: session,
      totals: up is num && down is num
          ? TrafficAmount(_integer(up), _integer(down))
          : null,
      connections:
          parsedConnections ??
          (snapshot['connections'] as List? ?? [])
              .whereType<Map>()
              .take(10000)
              .map(_connectionFromMap)
              .toList(),
    );
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'];
    final data = _map(event['data']);
    switch (type) {
      case 'log':
        _append(
          logs,
          CoreLog(
            level: '${data['LogLevel'] ?? data['level'] ?? 'info'}',
            message:
                '${data['Payload'] ?? data['payload'] ?? data['message'] ?? event['data']}',
            time: DateTime.now(),
          ),
          1000,
        );
      case 'request':
        _append(requests, data, 1000);
        trafficUpdate.value = CoreTrafficUpdate(
          session: _epoch,
          connections: [_connectionFromMap(data)],
        );
      case 'dns':
        _append(dnsQueries, data, 1000);
      case 'delay':
        final name = data['name'];
        if (name is String) delays[name] = _integer(data['value']);
      case 'loaded':
        if (running) unawaited(refreshRuntime().catchError(_recordError));
      case 'routeChanged':
        _updateRouteState(data);
      case 'requestTraffic':
        final updates = event['data'];
        if (updates is List) {
          trafficUpdate.value = CoreTrafficUpdate(
            session: _epoch,
            counters: [
              for (final raw in updates.whereType<Map>())
                ConnectionTrafficCounter(
                  '${raw['id'] ?? ''}',
                  _integer(raw['upload']),
                  _integer(raw['download']),
                ),
            ],
          );
          final byId = <String, Map<String, dynamic>>{
            for (final raw in updates.whereType<Map>())
              '${raw['id']}': Map<String, dynamic>.from(raw),
          };
          var changed = false;
          for (var i = 0; i < requests.length; i++) {
            final delta = byId['${requests[i]['id']}'];
            if (delta == null) continue;
            requests[i] = {
              ...requests[i],
              'upload': delta['upload'],
              'download': delta['download'],
            };
            changed = true;
          }
          if (changed) requests.refresh();
        }
      case 'geoUpdate':
        if (data['error'] is String && (data['error'] as String).isNotEmpty) {
          _recordError(data['error']);
        }
      case 'crash':
        final failure = CoreException(
          'process_exit',
          '${event['data'] ?? 'Core stopped unexpectedly'}',
        );
        _recordError(failure);
        status.value = CoreStatus.failed;
        final shouldRecover = _lifecycle.desired;
        // A crash is part of the recovery sequence.  Tear the runtime down
        // without going through the public stop() method, because a manual
        // stop intentionally resets the bounded recovery counter.
        final cleanup = _stopAfterCrash();
        final crashRevision = _lifecycle.revision;
        unawaited(
          cleanup
              .then<void>((_) {
                if (crashRevision == _lifecycle.revision) {
                  status.value = CoreStatus.failed;
                  if (shouldRecover) _scheduleRecovery();
                }
              })
              .catchError((error) {
                _recordError(error);
              }),
        );
    }
  }

  @override
  Future<void> setMode(String mode) async {
    if (!['rule', 'global', 'direct'].contains(mode)) {
      throw const CoreException('mode', 'Invalid proxy mode');
    }
    final previous = settings.fields['mode'] ?? 'rule';
    final runtime = _runtime;
    final applied = _appliedSettings;
    final nativeApplied = running && runtime != null;
    if (nativeApplied) {
      _messageResult(await runtime.invoke('updateConfig', {'mode': mode}));
    }
    try {
      await settings.set('mode', mode);
    } catch (e) {
      if (nativeApplied && identical(runtime, _runtime)) {
        try {
          _messageResult(
            await runtime.invoke('updateConfig', {'mode': previous}),
          );
        } catch (rollback) {
          _recordError('Mode save failed: $e; core rollback failed: $rollback');
        }
      }
      rethrow;
    }
    if (nativeApplied &&
        running &&
        identical(runtime, _runtime) &&
        _appliedSettings == applied) {
      final fields = Map<String, dynamic>.from(jsonDecode(applied) as Map);
      fields['mode'] = mode;
      _appliedSettings = jsonEncode(fields);
      _desiredFingerprint = _appliedSettings;
    } else if (_lifecycle.desired) {
      await reload();
    }
  }

  @override
  Future<void> selectProxy(String group, String name) async {
    final response = _map(
      await invoke('changeProxy', {'group-name': group, 'proxy-name': name}),
    );
    _messageResult(response['message']);
    await refreshRuntime();
  }

  @override
  Future<int?> testDelay(String name) async {
    final result = await invoke('asyncTestDelay', {
      'proxy-name': name,
      'test-url':
          settings.fields['testUrl'] ?? 'https://www.gstatic.com/generate_204',
      'timeout': settings.fields['testTimeout'] ?? 5000,
    });
    if (result == null) return null;
    final value = _integer(_map(result)['value']);
    delays[name] = value;
    return value;
  }

  @override
  Future<void> testAll() async {
    final names = groups
        .expand((group) => group.nodes)
        .map((node) => node.name)
        .toSet()
        .toList();
    for (var offset = 0; offset < names.length; offset += 8) {
      await Future.wait(names.skip(offset).take(8).map(testDelay));
    }
    await refreshRuntime();
  }

  @override
  Future<void> closeAll() async {
    await invoke('closeConnections');
    await _poll(_epoch);
  }

  @override
  Future<void> closeConnection(String id) async {
    await invoke('closeConnection', id);
    await _poll(_epoch);
  }

  Future<void> updateProvider(String name) async {
    _messageResult(await invoke('updateExternalProvider', name));
    await refreshRuntime();
  }

  Future<void> updateGeo(String name) async {
    _messageResult(await invoke('updateGeoData', name));
  }

  /// Watches only while a diagnostic page needs route validity information.
  /// Owners share the native watch so closing one page cannot stop another.
  Future<void> setRouteWatching(Object owner, {required bool enabled}) async {
    if (enabled) {
      _routeWatchers.add(owner);
    } else {
      _routeWatchers.remove(owner);
    }
    if (!running || preview) return;
    final epoch = _epoch;
    final response = await invoke('watchRoute', _routeWatchers.isNotEmpty);
    if (epoch == _epoch && running) _updateRouteState(_map(response));
  }

  void _updateRouteState(Map<String, dynamic> data) {
    final epoch = data['core-epoch'], picks = data['picks-version'];
    if (epoch is! int || picks is! int) return;
    final previousEpoch = routeState['core-epoch'] as int?;
    final previousPicks = routeState['picks-version'] as int?;
    if (previousEpoch != null &&
        (epoch < previousEpoch ||
            (epoch == previousEpoch && picks < (previousPicks ?? 0)))) {
      return;
    }
    if (epoch == previousEpoch && picks == previousPicks) return;
    routeState.assignAll(data);
  }

  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    if (preview) {
      throw const CoreException(
        'preview',
        'Preview is read only; core operations are disabled',
      );
    }
    if (method == 'installHelper' || method == 'uninstallHelper') {
      await HelperClient.manage(
        DesktopCoreRuntime.artifactDirectory,
        uninstall: method == 'uninstallHelper',
      );
      return null;
    }
    final runtime = _runtime;
    if (runtime == null) {
      throw const CoreException(
        'not_running',
        'Connect the core before using this operation',
      );
    }
    return runtime.invoke(method, arguments);
  }

  Future<bool> isLaunchAtLoginEnabled() async {
    if (preview) return false;
    return DesktopStartup.isEnabled();
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    if (preview) {
      throw const CoreException('preview', 'Preview cannot change login items');
    }
    await DesktopStartup.setEnabled(enabled);
  }

  void _scheduleRecovery() {
    if (preview || _maintenance || _lifecycle.desired) return;
    if (recoveryAttempt.value >= _maxRecoveryAttempts) {
      recovering.value = false;
      recoveryExhausted.value = true;
      final generation = _recoveryGeneration;
      unawaited(
        _lifecycle
            .request(false)
            .then<void>((_) {
              if (generation == _recoveryGeneration) {
                status.value = CoreStatus.failed;
              }
            })
            .catchError(_recordError),
      );
      return;
    }
    final attempt = recoveryAttempt.value + 1;
    recoveryAttempt.value = attempt;
    recovering.value = true;
    recoveryExhausted.value = false;
    final generation = ++_recoveryGeneration;
    final multiplier = 1 << (attempt - 1);
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(
      recoveryBaseDelay * multiplier,
      () => unawaited(_runRecovery(generation, attempt)),
    );
  }

  Future<void> _runRecovery(int generation, int attempt) async {
    if (generation != _recoveryGeneration ||
        _maintenance ||
        _lifecycle.desired ||
        preview) {
      return;
    }
    _recoveryTimer = null;
    try {
      await _lifecycle.request(true);
      if (generation == _recoveryGeneration) recovering.value = false;
    } catch (error) {
      if (generation != _recoveryGeneration) return;
      _recordError(error);
      if (_isNonRecoverable(error) || attempt >= _maxRecoveryAttempts) {
        await _stopAfterRecoveryFailure(generation);
      } else {
        // The failed start leaves the lifecycle intent active. Move it back to
        // stopped before scheduling the next bounded attempt.
        try {
          await _lifecycle.request(false);
        } catch (cleanup) {
          _recordError(cleanup);
          await _stopAfterRecoveryFailure(generation);
          return;
        }
        if (generation == _recoveryGeneration) {
          status.value = CoreStatus.failed;
          _scheduleRecovery();
        }
      }
    }
  }

  Future<void> _stopAfterRecoveryFailure(int generation) async {
    if (generation != _recoveryGeneration) return;
    recovering.value = false;
    recoveryExhausted.value = true;
    try {
      await _lifecycle.request(false);
    } catch (error) {
      _recordError(error);
    }
    if (generation == _recoveryGeneration) status.value = CoreStatus.failed;
  }

  Future<void> _stopAfterCrash() => _lifecycle.request(false);

  bool _isNonRecoverable(Object error) {
    switch (classifyCoreError(error)) {
      case CoreErrorCategory.configuration:
      case CoreErrorCategory.permission:
      case CoreErrorCategory.systemProxy:
      case CoreErrorCategory.tun:
      case CoreErrorCategory.profile:
      case CoreErrorCategory.maintenance:
      case CoreErrorCategory.unsupported:
        return true;
      case CoreErrorCategory.process:
      case CoreErrorCategory.timeout:
      case CoreErrorCategory.connection:
      case CoreErrorCategory.unknown:
        return false;
    }
  }

  void _cancelRecovery({required bool resetAttempt}) {
    _recoveryGeneration++;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    recovering.value = false;
    recoveryExhausted.value = false;
    if (resetAttempt) recoveryAttempt.value = 0;
  }

  void _scheduleStableRecoveryReset() {
    _recoveryStableTimer?.cancel();
    _recoveryStableTimer = Timer(recoveryStablePeriod, () {
      if (running && !recovering.value) recoveryAttempt.value = 0;
    });
  }

  Future<void> disposeRuntime() async {
    _cancelRecovery(resetAttempt: true);
    _recoveryStableTimer?.cancel();
    if (_initialized) WidgetsBinding.instance.removeObserver(this);
    _settingsWorker?.dispose();
    _profileWorker?.dispose();
    _profileContentWorker?.dispose();
    await _lifecycle.close();
  }

  @override
  void onClose() {
    unawaited(disposeRuntime().catchError(_recordError));
    super.onClose();
  }

  void _recordError(Object e) {
    errorCategory.value = classifyCoreError(e);
    error.value = coreErrorMessage(e);
  }

  void recordError(Object e) => _recordError(e);

  String? get errorCategoryLabel => errorCategory.value?.labelKey;

  void _clearError() {
    error.value = null;
    errorCategory.value = null;
  }

  String _profileFingerprint() {
    final active = profiles.active;
    return active == null
        ? ''
        : jsonEncode([
            active.id,
            active.path,
            active.updatedAt?.toIso8601String(),
            active.script,
            active.sharedScriptIds,
            active.standardRules,
            active.matchTarget,
          ]);
  }

  static String _fingerprint(Map<String, dynamic> fields) => jsonEncode({
    for (final key in const [
      'mode',
      'mixedPort',
      'systemProxy',
      'tunEnabled',
      'allowLan',
      'ipv6',
      'logLevel',
      'stack',
      'dnsOverride',
      'tunOverride',
      'snifferOverride',
      'ntpOverride',
      'addedRules',
      'hosts',
      'controllerEnabled',
      'controllerPort',
      'bypassDomains',
      'accessControlEnabled',
      'accessControlMode',
      'accessControlPackages',
      'allowBypass',
      'unifiedDelay',
      'tcpConcurrent',
      'testUrl',
      'testTimeout',
      'scripts',
    ])
      key: fields[key],
  });
  static void _messageResult(dynamic result) {
    if (result is String && result.isNotEmpty) {
      throw CoreException('core_error', result);
    }
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static void _append<T>(RxList<T> list, T value, int limit) {
    list.add(value);
    if (list.length > limit) list.removeRange(0, list.length - limit);
  }
}
