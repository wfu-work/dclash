import 'dart:io';

import 'package:dclash_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:dclash_flutter/services/config_builder.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'effective preview merges settings while core remains stopped',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cloudrift-preview-test-',
      );
      final profiles = ProfileService(directory: directory);
      await profiles.initialize();
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      await settings.set('mode', 'global');
      await settings.set('controllerEnabled', true);
      await settings.set('addedRules', '- DOMAIN,example.com,REJECT');
      final core = CoreService(profiles, settings, preview: true);
      final controller = ProfilesController(profiles, core);
      try {
        final profile = await profiles.saveContent(
          name: 'Preview',
          content: 'proxies: []\nrules: ["MATCH,DIRECT"]',
        );
        final preview = await controller.effectiveConfig(profile);
        final shown = loadYaml(preview.displayContent);
        final exported = loadYaml(preview.exportContent);
        expect(shown['mode'], 'global');
        expect(shown['rules'].first, 'DOMAIN,example.com,REJECT');
        expect(shown['secret'], '[redacted]');
        expect(
          preview.displayContent.contains(ConfigBuilder.sessionSecret),
          false,
        );
        expect(exported.containsKey('secret'), false);
        expect(
          preview.exportContent.contains(ConfigBuilder.sessionSecret),
          false,
        );
        expect(core.running, false);
        expect(controller.busy, isEmpty);
      } finally {
        profiles.onClose();
        await core.disposeRuntime();
        await directory.delete(recursive: true);
      }
    },
  );
}
