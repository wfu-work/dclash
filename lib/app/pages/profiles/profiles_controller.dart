import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../domains/clash_profile.dart';
import '../../../domains/core_status.dart';
import '../../../services/config_builder.dart';
import '../../../services/core_ports.dart';
import '../../../services/profile_service.dart';
import '../../../storage/atomic_file.dart';
import '../../../utils/yaml_config.dart';

class EffectiveProfileConfig {
  const EffectiveProfileConfig({
    required this.displayContent,
    required this.exportContent,
  });
  final String displayContent;
  final String exportContent;
}

EffectiveProfileConfig _safeEffectiveConfig(String content) {
  final config = parseConfig(content);
  final exportConfig = Map<String, dynamic>.from(config)..remove('secret');
  if (config.containsKey('secret')) config['secret'] = '[redacted]';
  return EffectiveProfileConfig(
    displayContent: encodeYaml(config),
    exportContent: encodeYaml(exportConfig),
  );
}

class ProfilesController extends GetxController {
  ProfilesController(this.profiles, this.core);
  final ProfileService profiles;
  final CoreProfilePort core;
  final query = ''.obs;
  final busy = <String>{}.obs;
  bool get coreActive =>
      core.running || core.status.value == CoreStatus.starting;

  List<ClashProfile> get visibleProfiles {
    final value = query.value.trim().toLowerCase();
    return profiles.profiles
        .where(
          (item) =>
              value.isEmpty ||
              '${item.name} ${item.url}'.toLowerCase().contains(value),
        )
        .toList();
  }

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (!busy.add(id)) return;
    try {
      await action();
    } finally {
      busy.remove(id);
    }
  }

  Future<void> importUrl(String url, String name) =>
      _perform('import', () async {
        final imported = await profiles.importUrl(
          url,
          name: name.trim().isEmpty ? null : name.trim(),
        );
        if (profiles.activeId.value == imported.id && coreActive) {
          await core.reload();
        }
      });
  Future<void> importFile() => _perform('import', () async {
    await profiles.importFile();
  });

  /// Imports either a subscription link or a Clash-compatible YAML copied to
  /// the clipboard. This keeps the common mobile/desktop handoff one tap away
  /// without making the profile repository depend on Flutter services.
  Future<void> importClipboard() => _perform('import', () async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final value = clipboard?.text?.trim() ?? '';
    if (value.isEmpty) throw StateError('profileClipboardEmpty'.tr);

    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    const linkSchemes = {
      'http',
      'https',
      'file',
      'clash',
      'flclash',
      'cloudrift',
    };
    if (uri != null && scheme != null && linkSchemes.contains(scheme)) {
      final imported = await profiles.importUrl(value);
      if (profiles.activeId.value == imported.id && coreActive) {
        await core.reload();
      }
      return;
    }

    final imported = await profiles.saveContent(
      name: 'profileClipboardName'.tr,
      content: value,
    );
    if (profiles.activeId.value == imported.id && coreActive) {
      await core.reload();
    }
  });
  Future<void> save({
    String? id,
    required String name,
    required String content,
  }) => _perform(id ?? 'import', () async {
    await profiles.saveContent(id: id, name: name, content: content);
    if (id != null && profiles.activeId.value == id && coreActive) {
      await core.reload();
    }
  });
  Future<void> activate(ClashProfile profile) => _perform(profile.id, () async {
    await profiles.activate(profile.id);
    if (coreActive) await core.reload();
  });
  Future<void> refreshProfile(ClashProfile profile) =>
      _perform(profile.id, () async {
        await profiles.refresh(profile.id);
        if (profiles.activeId.value == profile.id && coreActive) {
          await core.reload();
        }
      });
  Future<void> updateProfile(ClashProfile profile) =>
      _perform(profile.id, () async {
        await profiles.update(profile);
        if (profiles.activeId.value == profile.id && coreActive) {
          await core.reload();
        }
      });
  Future<void> duplicate(ClashProfile profile) =>
      _perform(profile.id, () async {
        await profiles.duplicate(profile.id);
      });
  Future<void> remove(ClashProfile profile) => _perform(profile.id, () async {
    if (profiles.activeId.value == profile.id && coreActive) {
      await core.stop();
    }
    await profiles.remove(profile.id);
  });

  Future<EffectiveProfileConfig> effectiveConfig(ClashProfile profile) async {
    if (!busy.add(profile.id)) throw StateError('profileBusy'.tr);
    try {
      final content = await profiles.readContent(profile);
      final fields = Map<String, dynamic>.from(core.settings.fields)
        ..['providerDirectory'] = p.join(profiles.directory.path, 'providers');
      final effective = await ConfigBuilder.build(
        content,
        fields,
        script: profile.script,
        sharedScriptIds: profile.sharedScriptIds,
        profileRules: profile.standardRules,
        matchTarget: profile.matchTarget,
      );
      return await compute(_safeEffectiveConfig, effective);
    } finally {
      busy.remove(profile.id);
    }
  }

  Future<bool> exportEffectiveConfig(
    ClashProfile profile,
    EffectiveProfileConfig config,
  ) async {
    final filename = profile.name.replaceAll(
      RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]'),
      '_',
    );
    final bytes = utf8.encode(config.exportContent);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'profileAction_effectiveExport'.tr,
      fileName: '$filename-effective.yaml',
      type: FileType.custom,
      allowedExtensions: ['yaml'],
      bytes: Uint8List.fromList(bytes),
    );
    if (path == null) return false;
    if (!path.startsWith('content:')) {
      await writePrivateAtomic(File(path), bytes);
    }
    return true;
  }
}
