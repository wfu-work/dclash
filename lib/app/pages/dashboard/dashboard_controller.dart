import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/settings_service.dart';

class DashboardController extends GetxController {
  DashboardController(this.core, this.profiles, this.settings);
  final CoreService core;
  final ProfileService profiles;
  final SettingsService settings;
  final uploadHistory = <double>[0].obs;
  final downloadHistory = <double>[0].obs;
  final elapsed = Duration.zero.obs;
  final outboundIp = ''.obs;
  final checking = false.obs;
  final checkingServices = false.obs;
  final serviceChecks = <Map<String, dynamic>>[].obs;
  Timer? _timer;
  Worker? _routeWorker;
  int _probeGeneration = 0;
  String _route = '';

  @override
  void onInit() {
    super.onInit();
    _route = _routeFingerprint();
    _routeWorker = everAll([core.status, core.groups, settings.fields], (_) {
      final route = _routeFingerprint();
      if (_route == route) return;
      _route = route;
      _probeGeneration++;
      outboundIp.value = '';
      serviceChecks.clear();
      checking.value = checkingServices.value = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _append(uploadHistory, core.upload.value.toDouble());
      _append(downloadHistory, core.download.value.toDouble());
      final start = core.startedAt.value;
      elapsed.value = start == null
          ? Duration.zero
          : DateTime.now().difference(start);
    });
  }

  String _routeFingerprint() => jsonEncode([
    core.status.value.name,
    settings.fields['mode'],
    for (final group in core.groups) [group.name, group.selected],
  ]);

  void _append(RxList<double> values, double value) {
    final next = [...values, value];
    values.assignAll(next.length > 45 ? next.sublist(next.length - 45) : next);
  }

  Future<void> toggle() async {
    if (!core.running && profiles.active == null) {
      throw StateError('addProfileHint'.tr);
    }
    await core.toggle();
  }

  Future<void> changeSetting(String key, dynamic value) async {
    final previous = settings.fields[key];
    await settings.set(key, value);
    try {
      if (core.running) await core.reload();
    } on Object {
      await settings.set(key, previous);
      rethrow;
    }
  }

  Future<void> detectIp() async {
    if (!core.running) throw StateError('connectFirst'.tr);
    if (checking.value) return;
    final generation = _probeGeneration;
    checking.value = true;
    try {
      final response = await core.invoke('outboundIp', {
        'proxy-name': '',
        'urls': ['https://api.ipify.org?format=json'],
        'timeout': 8000,
      });
      final result = Map<String, dynamic>.from(response as Map);
      if (result['error'] != null && result['error'] != '') {
        throw StateError('${result['error']}');
      }
      final body = result['body'] as String? ?? '';
      String ip;
      try {
        final decoded = jsonDecode(body);
        ip = decoded is Map ? '${decoded['ip'] ?? body}' : body.trim();
      } on FormatException {
        ip = body.trim();
      }
      if (InternetAddress.tryParse(ip) == null) {
        throw StateError('outboundInvalid'.tr);
      }
      if (!isClosed && generation == _probeGeneration) outboundIp.value = ip;
    } finally {
      if (generation == _probeGeneration) checking.value = false;
    }
  }

  Future<void> checkServices() async {
    if (!core.running) throw StateError('connectFirst'.tr);
    if (checkingServices.value) return;
    final generation = _probeGeneration;
    checkingServices.value = true;
    try {
      final result = await core.invoke('serviceCheck', {
        'proxy-name': '',
        'names': ['google', 'github', 'youtube', 'chatgpt'],
        'timeout': 8000,
      });
      final items = result is List
          ? result
          : (result is Map ? result['items'] as List? ?? [] : []);
      if (!isClosed && generation == _probeGeneration) {
        serviceChecks.assignAll(
          items.whereType<Map>().map(Map<String, dynamic>.from),
        );
      }
    } finally {
      if (generation == _probeGeneration) checkingServices.value = false;
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _probeGeneration++;
    _routeWorker?.dispose();
    super.onClose();
  }
}
