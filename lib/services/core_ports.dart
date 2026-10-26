import 'package:get/get.dart';

import '../domains/clash_connection.dart';
import '../domains/core_status.dart';
import '../domains/proxy_group.dart';
import 'profile_service.dart';
import 'settings_service.dart';

/// The runtime activity surface used by connections, requests, DNS and logs.
///
/// Keeping this port separate from [CoreService] lets these feature modules
/// evolve without depending on the core's lifecycle, profile and platform
/// implementation details.
abstract interface class CoreActivityPort {
  bool get running;
  RxList<ClashConnection> get connections;
  RxList<CoreLog> get logs;
  RxList<Map<String, dynamic>> get requests;
  RxList<Map<String, dynamic>> get dnsQueries;
  Future<void> closeConnection(String id);
  Future<void> closeAll();
}

/// Lifecycle and recovery controls exposed to feature modules.
abstract interface class CoreLifecyclePort {
  bool get running;
  Rx<CoreStatus> get status;
  Future<void> start();
  Future<void> stop();
  Future<void> toggle();
  Future<void> reload();
  Future<void> restart();
  Future<T> withStoppedCore<T>(Future<T> Function() action);
}

/// Profile-facing core surface. Profile actions only need lifecycle controls,
/// the current profile repository and settings used to render effective YAML.
abstract interface class CoreProfilePort implements CoreLifecyclePort {
  ProfileService get profiles;
  SettingsService get settings;
}

/// Proxy-facing core surface. Runtime groups and proxy operations are kept
/// separate from the core's process, diagnostics and platform internals.
abstract interface class CoreProxyPort implements CoreLifecyclePort {
  ProfileService get profiles;
  SettingsService get settings;
  RxList<ProxyGroup> get groups;
  RxMap<String, int> get delays;
  Future<void> refreshRuntime();
  Future<void> setMode(String mode);
  Future<void> selectProxy(String group, String name);
  Future<int?> testDelay(String name);
  Future<void> testAll();
}
