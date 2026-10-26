import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../configs/app_services_bridge.dart';
import '../../../services/core_service.dart';
import '../../../services/diagnostic_report_service.dart';
import '../../../services/health_history_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/traffic_statistics_service.dart';
import 'dashboard_controller.dart';

/// Services needed to render the dashboard and its insight cards.
class DashboardDependencies {
  const DashboardDependencies({
    required this.core,
    required this.profiles,
    required this.settings,
    this.healthHistory,
    this.trafficStatistics,
    this.timeline,
    this.diagnostics,
  });

  factory DashboardDependencies.fromAppServices(AppServices services) =>
      DashboardDependencies(
        core: services.core,
        profiles: services.profiles,
        settings: services.settings,
        healthHistory: services.healthHistory,
        trafficStatistics: services.trafficStatistics,
        timeline: services.timeline,
        diagnostics: services.diagnostics,
      );

  factory DashboardDependencies.fromController(
    DashboardController controller,
  ) => DashboardDependencies(
    core: controller.core,
    profiles: controller.profiles,
    settings: controller.settings,
    healthHistory: _find<HealthHistoryService>(),
    trafficStatistics: _find<TrafficStatisticsService>(),
    timeline: _find<NetworkTimelineService>(),
    diagnostics: _find<DiagnosticReportService>(),
  );

  /// Compatibility path for standalone tests and legacy routes.
  factory DashboardDependencies.fromGetX() =>
      DashboardDependencies.fromAppServices(appServicesFromGetX());

  final CoreService core;
  final ProfileService profiles;
  final SettingsService settings;
  final HealthHistoryService? healthHistory;
  final TrafficStatisticsService? trafficStatistics;
  final NetworkTimelineService? timeline;
  final DiagnosticReportService? diagnostics;
}

T? _find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
