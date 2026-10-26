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

/// Dependencies assembled once by the application composition root.
///
/// Widgets and feature bindings should receive this object (or a smaller
/// feature-specific interface) instead of looking up every service globally.
/// The nullable integrations are unavailable in preview and on unsupported
/// desktop platforms.
class AppServices {
  const AppServices({
    required this.settings,
    required this.profiles,
    required this.core,
    this.scripts,
    this.resources,
    this.healthHistory,
    this.trafficStatistics,
    this.nodeQuality,
    this.timeline,
    this.diagnostics,
    this.backup,
    this.link,
    this.desktop,
    this.notifications,
    this.shortcuts,
    this.updates,
  });

  final SettingsService settings;
  final ProfileService profiles;
  final CoreService core;
  final ScriptLibraryService? scripts;
  final ResourceLibraryService? resources;
  final HealthHistoryService? healthHistory;
  final TrafficStatisticsService? trafficStatistics;
  final NodeQualityService? nodeQuality;
  final NetworkTimelineService? timeline;
  final DiagnosticReportService? diagnostics;
  final BackupService? backup;
  final LinkService? link;
  final DesktopIntegrationService? desktop;
  final ProfileNotificationService? notifications;
  final DesktopShortcutService? shortcuts;
  final UpdateService? updates;
}
