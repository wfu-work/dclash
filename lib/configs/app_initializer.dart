import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../services/backup_service.dart';
import '../services/core_service.dart';
import '../services/desktop_integration_service.dart';
import '../services/link_service.dart';
import '../services/profile_service.dart';
import '../services/resource_library_service.dart';
import '../services/script_library_service.dart';
import '../services/settings_service.dart';

abstract final class AppInitializer {
  static Future<void> init({bool preview = false}) async {
    ProfileService? profiles;
    CoreService? core;
    DesktopIntegrationService? desktop;
    Directory? temporaryDirectory;
    try {
      final settings = SettingsService(memoryOnly: preview);
      await settings.initialize();
      if (preview) {
        temporaryDirectory = await Directory.systemTemp.createTemp(
          'cloudrift-preview-',
        );
      }
      profiles = ProfileService(directory: temporaryDirectory);
      await profiles.initialize();
      core = CoreService(profiles, settings, preview: preview);
      await core.initialize();
      Get.put(settings, permanent: true);
      Get.put(ScriptLibraryService(settings)..initialize(), permanent: true);
      final resources = ResourceLibraryService(settings);
      await resources.initialize();
      Get.put(resources, permanent: true);
      Get.put(profiles, permanent: true);
      Get.put(core, permanent: true);
      Get.put(BackupService(profiles, settings), permanent: true);
      if (!preview) Get.put(LinkService(profiles), permanent: true);
      if (!preview &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        await settings.set(
          'launchAtLogin',
          await core.isLaunchAtLoginEnabled(),
        );
      }
      desktop = DesktopIntegrationService(
        core,
        settings,
        preview: preview,
        beforeExit: () async {
          profiles?.onClose();
          final directory = temporaryDirectory;
          if (directory != null && await directory.exists()) {
            await directory.delete(recursive: true);
          }
        },
      );
      await desktop.initialize();
      Get.put(desktop, permanent: true);
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'FlClash / dclash',
        ], await rootBundle.loadString('third_party/FlClash-LICENSE'));
        yield LicenseEntryWithLineBreaks([
          'JetBrains Mono',
        ], await rootBundle.loadString('assets/fonts/OFL.txt'));
        yield LicenseEntryWithLineBreaks([
          'Lucide Icons',
        ], await rootBundle.loadString('third_party/lucide-icons-LICENSE.txt'));
      });
    } on Object {
      await desktop?.disposeIntegration();
      await core?.disposeRuntime();
      profiles?.onClose();
      Get.reset();
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }
}
