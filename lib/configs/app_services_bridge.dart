import 'package:get/get.dart';

import '../services/backup_service.dart';
import '../services/core_service.dart';
import '../services/diagnostic_report_service.dart';
import '../services/desktop_integration_service.dart';
import '../services/desktop_shortcut_service.dart';
import '../services/health_history_service.dart';
import '../services/link_service.dart';
import '../services/network_timeline_service.dart';
import '../services/node_quality_service.dart';
import '../services/profile_notification_service.dart';
import '../services/profile_service.dart';
import '../services/resource_library_service.dart';
import '../services/script_library_service.dart';
import '../services/settings_service.dart';
import '../services/traffic_statistics_service.dart';
import '../services/update_service.dart';
import 'app_services.dart';

/// Transitional adapter for tests and legacy entry points that still register
/// services one by one in GetX. Production startup passes [AppServices]
/// directly to the widget tree and does not need this lookup path.
AppServices appServicesFromGetX() => AppServices(
  settings: Get.find<SettingsService>(),
  profiles: Get.find<ProfileService>(),
  core: Get.find<CoreService>(),
  scripts: _find<ScriptLibraryService>(),
  resources: _find<ResourceLibraryService>(),
  healthHistory: _find<HealthHistoryService>(),
  trafficStatistics: _find<TrafficStatisticsService>(),
  nodeQuality: _find<NodeQualityService>(),
  timeline: _find<NetworkTimelineService>(),
  diagnostics: _find<DiagnosticReportService>(),
  backup: _find<BackupService>(),
  link: _find<LinkService>(),
  desktop: _find<DesktopIntegrationService>(),
  notifications: _find<ProfileNotificationService>(),
  shortcuts: _find<DesktopShortcutService>(),
  updates: _find<UpdateService>(),
);

CoreService coreFromGetX() => Get.find<CoreService>();

T? optionalServiceFromGetX<T>() => _find<T>();

T? _find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
