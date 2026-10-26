import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yaml/yaml.dart';

import '../../../services/core_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/desktop_shortcut_service.dart';

class SettingsController extends GetxController {
  SettingsController(this.settings, this.core, {this.shortcuts});
  final SettingsService settings;
  final CoreService core;
  final DesktopShortcutService? shortcuts;
  final saving = false.obs;

  Future<void> set(String key, dynamic value) async {
    if (saving.value) throw StateError('loading'.tr);
    saving.value = true;
    final previous = settings.fields[key];
    var startupChanged = false;
    final shortcuts = DesktopShortcutService.keys.contains(key)
        ? this.shortcuts ??
              (Get.isRegistered<DesktopShortcutService>()
                  ? Get.find<DesktopShortcutService>()
                  : null)
        : null;
    final previousSettings = settings.export();
    var shortcutsChanged = false;
    try {
      SettingsService.validate({...settings.fields, key: value});
      if (shortcuts != null) {
        await shortcuts.apply({...settings.fields, key: value});
        shortcutsChanged = true;
      }
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
    } on Object catch (failure, stack) {
      final rollbackErrors = <Object>[];
      for (final rollback in <Future<void> Function()>[
        if (shortcutsChanged) () => shortcuts!.apply(previousSettings),
        if (startupChanged) () => core.setLaunchAtLogin(previous as bool),
        if (settings.fields[key] != previous) () => settings.set(key, previous),
      ]) {
        try {
          await rollback();
        } on Object catch (error) {
          rollbackErrors.add(error);
        }
      }
      if (rollbackErrors.isNotEmpty) {
        throw StateError('$failure\n${rollbackErrors.join('\n')}');
      }
      Error.throwWithStackTrace(failure, stack);
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
