import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaml/yaml.dart';

import '../../../services/core_service.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController(this.settings, this.core);
  final SettingsService settings;
  final CoreService core;
  final saving = false.obs;

  Future<void> set(String key, dynamic value) async {
    if (saving.value) throw StateError('loading'.tr);
    saving.value = true;
    final previous = settings.fields[key];
    var startupChanged = false;
    try {
      if (key == 'launchAtLogin') {
        await core.setLaunchAtLogin(value as bool);
        startupChanged = true;
      }
      await settings.set(key, value);
      if (key == 'locale') {
        final parts = (value as String).split('_');
        await Get.updateLocale(Locale(parts[0], parts[1]));
      }
      if (_runtimeKeys.contains(key) && core.running) await core.reload();
    } on Object {
      if (startupChanged) await core.setLaunchAtLogin(previous as bool);
      if (settings.fields[key] != previous) await settings.set(key, previous);
      rethrow;
    } finally {
      saving.value = false;
    }
  }

  Future<void> saveYaml(String key, String content) async {
    if (content.trim().isNotEmpty) {
      final parsed = loadYaml(content);
      if (key == 'addedRules') {
        if (parsed is! YamlList || parsed.any((entry) => entry is! String)) {
          throw const FormatException('Expected a YAML list of rules.');
        }
      } else if (parsed is! YamlMap) {
        throw const FormatException('Expected a YAML mapping.');
      }
    }
    await set(key, content);
  }

  static const _runtimeKeys = {
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
  };
}
