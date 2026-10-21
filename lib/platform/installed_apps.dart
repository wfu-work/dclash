import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.system = false,
    this.internet = true,
    this.installed = true,
  });

  final String packageName, label;
  final bool system, internet, installed;
}

abstract interface class InstalledApps {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<List<InstalledApp>> load();
  Future<String?> icon(String packageName);
}

/// Read-only Android package inventory. Icons are requested only for visible rows.
class AndroidInstalledApps implements InstalledApps {
  AndroidInstalledApps({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.cloudrift.dclash/app');

  final MethodChannel _channel;
  final _icons = <String, Future<String?>>{};
  final _queue = Queue<({String packageName, Completer<String?> result})>();
  int _loadingIcons = 0;

  @override
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('isInstalledAppsPermissionGranted') ??
      false;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestInstalledAppsPermission') ??
      false;

  @override
  Future<List<InstalledApp>> load() async {
    final data = await _channel.invokeMethod<String>('getPackages') ?? '[]';
    return compute(_decodeApps, data);
  }

  @override
  Future<String?> icon(String packageName) {
    final cached = _icons.remove(packageName);
    if (cached != null) {
      _icons[packageName] = cached;
      return cached;
    }
    if (_queue.length >= 64) return Future.value();
    final result = Completer<String?>();
    _icons[packageName] = result.future;
    while (_icons.length > 128) {
      _icons.remove(_icons.keys.first);
    }
    _queue.add((packageName: packageName, result: result));
    _drainIcons();
    return result.future;
  }

  void _drainIcons() {
    while (_loadingIcons < 4 && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _loadingIcons++;
      unawaited(() async {
        try {
          final path = await _channel.invokeMethod<String>('getPackageIcon', {
            'packageName': request.packageName,
          });
          request.result.complete(path?.isEmpty == true ? null : path);
        } on Object {
          request.result.complete(null);
        } finally {
          _loadingIcons--;
          _drainIcons();
        }
      }());
    }
  }
}

List<InstalledApp> _decodeApps(String data) {
  final entries = jsonDecode(data);
  if (entries is! List) {
    throw const FormatException('Invalid installed application list.');
  }
  final apps = <String, InstalledApp>{};
  for (final entry in entries) {
    if (entry is! Map || entry['packageName'] is! String) continue;
    final name = entry['packageName'] as String;
    if (name.isEmpty) continue;
    apps[name] = InstalledApp(
      packageName: name,
      label: entry['label'] is String && (entry['label'] as String).isNotEmpty
          ? entry['label'] as String
          : name,
      system: entry['system'] == true,
      internet: entry['internet'] == true,
    );
  }
  return apps.values.toList(growable: false);
}
