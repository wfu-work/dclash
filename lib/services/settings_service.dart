import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domains/resource_item.dart';

class SettingsService extends GetxService {
  SettingsService({this.memoryOnly = false, this.preferences});

  final bool memoryOnly;
  final SharedPreferences? preferences;
  SharedPreferences? _preferences;
  final fields = <String, dynamic>{}.obs;
  final _secrets = <String, String>{};
  final _secure = const FlutterSecureStorage();
  Future<void> _writes = Future.value();

  static const defaults = <String, dynamic>{
    'mode': 'rule',
    'mixedPort': 7890,
    'systemProxy': false,
    'tunEnabled': false,
    'allowLan': false,
    'ipv6': false,
    'logLevel': 'info',
    'stack': 'mixed',
    'themeMode': 'system',
    'pureBlack': false,
    'fontFamily': 'system',
    'locale': 'zh_CN',
    'accent': 'blue',
    'dnsOverride': '',
    'tunOverride': '',
    'snifferOverride': '',
    'ntpOverride': '',
    'addedRules': '',
    'hosts': '',
    'controllerEnabled': false,
    'controllerPort': 19090,
    'scripts': '',
    'resources': '',
    'dashboardCards': [
      'status',
      'outboundMode',
      'currentProfile',
      'currentOutbound',
      'proxyGroups',
      'connections',
      'serviceStatus',
    ],
    'proxySort': 'default',
    'proxyLayout': 'grid',
    'hideUnavailable': false,
    // Connections start automatically when an active profile is available.
    // Kept as a storage field for backwards-compatible settings restores; the
    // UI intentionally does not expose a switch for disabling this behavior.
    'autoStart': true,
    'launchAtLogin': false,
    'minimizeToTray': true,
    'webdavUrl': '',
    'webdavUser': '',
    'testUrl': 'https://www.gstatic.com/generate_204',
    'testTimeout': 5000,
    'bypassDomains': ['localhost', '*.local', '127.*', '10.*', '192.168.*'],
    'accessControlEnabled': false,
    'accessControlMode': 'rejectSelected',
    'accessControlPackages': <String>[],
    'allowBypass': true,
    'unifiedDelay': true,
    'tcpConcurrent': true,
  };

  Future<void> initialize() async {
    if (!memoryOnly) {
      _preferences ??= preferences ?? await SharedPreferences.getInstance();
    }
    final stored = _preferences?.getString('cloudrift.settings.v1');
    final values = stored == null ? <String, dynamic>{} : _decode(stored);
    values.removeWhere((key, _) => !defaults.containsKey(key));
    fields.assignAll(_validated({...defaults, ...values}));
  }

  static Map<String, dynamic> _decode(String value) {
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } on Object catch (error) {
      throw FormatException('Settings could not be read: $error');
    }
  }

  T value<T>(String key) => fields[key] as T;

  Future<void> set(String key, dynamic value) => _enqueue(() async {
    if (!defaults.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Unknown setting');
    }
    await _persist(_validated({...fields, key: value}));
  });

  /// Compares inside the persistence queue, including any pending restore.
  Future<bool> compareAndSetString(
    String key, {
    required String expected,
    required String value,
  }) => _enqueue(() async {
    if (defaults[key] is! String) {
      throw ArgumentError.value(key, 'key', 'Expected a string setting');
    }
    if (fields[key] != expected) return false;
    await _persist(_validated({...fields, key: value}));
    return true;
  });

  Future<void> restore(Map<String, dynamic> values) => _enqueue(() async {
    final known = Map<String, dynamic>.from(values)
      ..removeWhere((key, _) => !defaults.containsKey(key));
    await _persist(_validated({...defaults, ...known}));
  });

  Map<String, dynamic> export() => {
    for (final entry in fields.entries)
      if (defaults.containsKey(entry.key))
        entry.key: entry.value is List
            ? List.of(entry.value as List)
            : entry.value,
  };

  Future<void> _persist(Map<String, dynamic> next) async {
    if (!memoryOnly) {
      final saved = await _preferences!.setString(
        'cloudrift.settings.v1',
        jsonEncode(next),
      );
      if (!saved) throw StateError('Could not save settings');
    }
    fields.assignAll(next);
  }

  Future<T> _enqueue<T>(Future<T> Function() write) {
    final result = _writes.then((_) => write());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> readSecret(String key) async {
    if (memoryOnly) return _secrets[key] ?? '';
    return await _secure.read(key: 'cloudrift.$key') ?? '';
  }

  Future<void> writeSecret(String key, String value) async {
    if (memoryOnly) {
      _secrets[key] = value;
    } else {
      await _secure.write(key: 'cloudrift.$key', value: value);
    }
  }

  static Map<String, dynamic> _validated(Map<String, dynamic> data) {
    for (final entry in defaults.entries) {
      final value = data[entry.key];
      final valid = switch (entry.value) {
        bool() => value is bool,
        int() => value is int,
        String() => value is String,
        List() => value is List && value.every((item) => item is String),
        _ => false,
      };
      if (!valid) throw FormatException('Invalid setting: ${entry.key}');
    }
    if (!['rule', 'global', 'direct'].contains(data['mode'])) {
      throw const FormatException('Invalid routing mode');
    }
    if (!['mixed', 'system', 'gvisor'].contains(data['stack'])) {
      throw const FormatException('Invalid TUN stack');
    }
    final port = data['mixedPort'] as int;
    if (port < 1 || port > 65535) {
      throw const FormatException('Port must be between 1 and 65535');
    }
    if (!['system', 'light', 'dark'].contains(data['themeMode'])) {
      throw const FormatException('Invalid theme mode');
    }
    if (!['zh_CN', 'en_US'].contains(data['locale'])) {
      throw const FormatException('Invalid language');
    }
    for (final choice in {
      'accent': ['blue', 'purple', 'green', 'orange', 'pink'],
      'fontFamily': ['system', 'JetBrainsMono'],
      'proxySort': ['default', 'name', 'delay'],
      'proxyLayout': ['grid', 'list'],
      'accessControlMode': ['rejectSelected', 'acceptSelected'],
    }.entries) {
      if (!choice.value.contains(data[choice.key])) {
        throw FormatException('Invalid setting: ${choice.key}');
      }
    }
    final controllerPort = data['controllerPort'] as int;
    if (controllerPort < 1 ||
        controllerPort > 65535 ||
        controllerPort == port) {
      throw const FormatException(
        'Controller port must be valid and differ from the mixed port',
      );
    }
    final testUri = Uri.tryParse(data['testUrl'] as String);
    if (testUri == null ||
        testUri.scheme != 'https' ||
        testUri.host.isEmpty ||
        testUri.userInfo.isNotEmpty) {
      throw const FormatException('Use an HTTPS test URL');
    }
    final dashboard = data['dashboardCards'] as List;
    final availableCards = defaults['dashboardCards'] as List;
    if (dashboard.isEmpty ||
        dashboard.toSet().length != dashboard.length ||
        dashboard.any((key) => !availableCards.contains(key))) {
      throw const FormatException('Invalid dashboard layout');
    }
    if (![
      'silent',
      'error',
      'warning',
      'info',
      'debug',
    ].contains(data['logLevel'])) {
      throw const FormatException('Invalid log level');
    }
    final timeout = data['testTimeout'] as int;
    if (timeout < 1000 || timeout > 60000) {
      throw const FormatException('Timeout must be between 1000 and 60000 ms');
    }
    ResourceEnvelope.decode(data['resources'] as String);
    return {
      for (final entry in data.entries)
        entry.key: entry.value is List
            ? List<String>.unmodifiable((entry.value as List).cast<String>())
            : entry.value,
    };
  }
}
