import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../services/backup_service.dart';
import '../../../services/core_service.dart';
import '../../../services/desktop_integration_service.dart';
import '../../../services/desktop_shortcut_service.dart';
import '../../../services/health_history_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../services/node_quality_service.dart';
import '../../../services/profile_notification_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/traffic_statistics_service.dart';
import '../../../services/update_service.dart';

/// Feature-local dependency surface for the settings module.
class SettingsDependencies {
  const SettingsDependencies({
    required this.settings,
    required this.core,
    this.backup,
    this.desktop,
    this.shortcuts,
    this.notifications,
    this.healthHistory,
    this.trafficStatistics,
    this.nodeQuality,
    this.timeline,
    this.updates,
  });

  factory SettingsDependencies.fromAppServices(AppServices services) =>
      SettingsDependencies(
        settings: services.settings,
        core: services.core,
        backup: services.backup,
        desktop: services.desktop,
        shortcuts: services.shortcuts,
        notifications: services.notifications,
        healthHistory: services.healthHistory,
        trafficStatistics: services.trafficStatistics,
        nodeQuality: services.nodeQuality,
        timeline: services.timeline,
        updates: services.updates,
      );

  factory SettingsDependencies.fromGetX() => SettingsDependencies(
    settings: Get.find<SettingsService>(),
    core: Get.find<CoreService>(),
    backup: _find<BackupService>(),
    desktop: _find<DesktopIntegrationService>(),
    shortcuts: _find<DesktopShortcutService>(),
    notifications: _find<ProfileNotificationService>(),
    healthHistory: _find<HealthHistoryService>(),
    trafficStatistics: _find<TrafficStatisticsService>(),
    nodeQuality: _find<NodeQualityService>(),
    timeline: _find<NetworkTimelineService>(),
    updates: _find<UpdateService>(),
  );

  final SettingsService settings;
  final CoreService core;
  final BackupService? backup;
  final DesktopIntegrationService? desktop;
  final DesktopShortcutService? shortcuts;
  final ProfileNotificationService? notifications;
  final HealthHistoryService? healthHistory;
  final TrafficStatisticsService? trafficStatistics;
  final NodeQualityService? nodeQuality;
  final NetworkTimelineService? timeline;
  final UpdateService? updates;
}

T? _find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
