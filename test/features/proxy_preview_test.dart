import 'dart:io';

import 'package:dclash_flutter/app/pages/proxies/proxies_controller.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the active profile while the core is stopped', () async {
    final directory = await Directory.systemTemp.createTemp('dclash-proxy-');
    addTearDown(() => directory.delete(recursive: true));

    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    final profiles = ProfileService(directory: directory);
    await profiles.initialize();
    await profiles.saveContent(
      name: 'Preview profile',
      content: '''
proxies:
  - name: Tokyo
    type: ss
    server: example.com
    port: 443
    cipher: aes-128-gcm
    password: secret
  - name: Seoul
    type: vmess
    server: example.net
    port: 443
proxy-groups:
  - name: 自动选择
    type: select
    proxies: [Tokyo, Seoul, DIRECT]
''',
    );

    final core = CoreService(profiles, settings);
    final controller = ProxiesController(core, settings);
    controller.onInit();
    await controller.refreshPreview();

    expect(core.running, isFalse);
    expect(controller.groups.map((group) => group.name), ['自动选择']);
    expect(controller.groups.single.nodes.map((node) => node.name), [
      'Tokyo',
      'Seoul',
      'DIRECT',
    ]);
    expect(controller.groups.single.nodes.last.type, 'Built-in');
    controller.onClose();
  });
}
