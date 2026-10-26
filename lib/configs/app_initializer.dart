import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app_services.dart';
import '../services/backup_service.dart';
import '../services/core_service.dart';
import '../services/diagnostic_report_service.dart';
import '../services/health_history_service.dart';
import '../services/desktop_integration_service.dart';
import '../services/desktop_shortcut_service.dart';
import '../services/profile_notification_service.dart';
import '../services/update_service.dart';
import '../services/link_service.dart';
import '../services/network_timeline_service.dart';
import '../services/node_quality_service.dart';
import '../services/profile_service.dart';
import '../services/resource_library_service.dart';
import '../services/script_library_service.dart';
import '../services/settings_service.dart';
import '../services/traffic_statistics_service.dart';

abstract final class AppInitializer {
  static Future<AppServices> init({bool preview = false}) async {
    ProfileService? profiles;
    CoreService? core;
    DesktopIntegrationService? desktop;
    DesktopShortcutService? shortcuts;
    ProfileNotificationService? notifications;
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
      final scripts = ScriptLibraryService(settings)..initialize();
      Get.put(settings, permanent: true);
      Get.put(scripts, permanent: true);
      final resources = ResourceLibraryService(settings);
      await resources.initialize();
      Get.put(resources, permanent: true);
      Get.put(profiles, permanent: true);
      Get.put(core, permanent: true);
      final healthHistory = HealthHistoryService(
        memoryOnly: preview,
        settings: settings,
      );
      await healthHistory.initialize();
      Get.put(healthHistory, permanent: true);
      final trafficStatistics = TrafficStatisticsService(
        core,
        memoryOnly: preview,
      );
      await trafficStatistics.initialize();
      Get.put(trafficStatistics, permanent: true);
      final nodeQuality = NodeQualityService(core, memoryOnly: preview);
      await nodeQuality.initialize();
      Get.put(nodeQuality, permanent: true);
      final timeline = NetworkTimelineService(
        core,
        settings,
        healthHistory,
        trafficStatistics,
        memoryOnly: preview,
      );
      await timeline.initialize();
      Get.put(timeline, permanent: true);
      final diagnostics = DiagnosticReportService(
        core,
        settings,
        healthHistory,
        trafficStatistics,
        timeline,
      );
      final backup = BackupService(profiles, settings);
      final link = !preview ? LinkService(profiles) : null;
      Get.put(diagnostics, permanent: true);
      Get.put(backup, permanent: true);
      if (link != null) Get.put(link, permanent: true);
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
          await shortcuts?.disposeShortcuts();
          notifications?.onClose();
          await trafficStatistics.flush().catchError((Object _) {});
          await nodeQuality.flush().catchError((Object _) {});
          await timeline.flush().catchError((Object _) {});
          profiles?.onClose();
          final directory = temporaryDirectory;
          if (directory != null && await directory.exists()) {
            await directory.delete(recursive: true);
          }
        },
      );
      await desktop.initialize();
      Get.put(desktop, permanent: true);
      if (!preview) {
        notifications = ProfileNotificationService(
          profiles,
          settings,
          showWindow: desktop.showWindow,
        )..initialize();
        Get.put(notifications, permanent: true);
        if (desktop.supported) {
          shortcuts = DesktopShortcutService(
            core,
            settings,
            toggleWindow: desktop.toggleWindow,
          )..initialize();
          Get.put(shortcuts, permanent: true);
        }
      }
      final updates = UpdateService(settings)..initialize(automatic: !preview);
      Get.put(updates, permanent: true);
      final services = AppServices(
        settings: settings,
        profiles: profiles,
        core: core,
        scripts: scripts,
        resources: resources,
        healthHistory: healthHistory,
        trafficStatistics: trafficStatistics,
        nodeQuality: nodeQuality,
        timeline: timeline,
        diagnostics: diagnostics,
        backup: backup,
        link: link,
        desktop: desktop,
        notifications: notifications,
        shortcuts: shortcuts,
        updates: updates,
      );
      Get.put(services, permanent: true);
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
      return services;
    } on Object {
      await shortcuts?.disposeShortcuts();
      notifications?.onClose();
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
