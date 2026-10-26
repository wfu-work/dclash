import 'package:get/get.dart';

import '../../../configs/app_services.dart';
import '../../../services/core_service.dart';
import '../../../services/diagnostic_report_service.dart';
import '../../../services/health_history_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../services/node_quality_service.dart';
import '../../../services/script_library_service.dart';
import '../../../services/traffic_statistics_service.dart';

/// Services used by the tools workspace. Keeping this surface local to the
/// feature prevents the tools page from depending on the complete app graph.
class ToolsDependencies {
  const ToolsDependencies({
    required this.core,
    this.healthHistory,
    this.trafficStatistics,
    this.timeline,
    this.diagnostics,
    this.nodeQuality,
    this.scripts,
  });

  factory ToolsDependencies.fromAppServices(AppServices services) =>
      ToolsDependencies(
        core: services.core,
        healthHistory: services.healthHistory,
        trafficStatistics: services.trafficStatistics,
        timeline: services.timeline,
        diagnostics: services.diagnostics,
        nodeQuality: services.nodeQuality,
        scripts: services.scripts,
      );

  /// Compatibility path for standalone feature tests and embedded callers.
  factory ToolsDependencies.fromGetX() => ToolsDependencies(
    core: Get.find<CoreService>(),
    healthHistory: _find<HealthHistoryService>(),
    trafficStatistics: _find<TrafficStatisticsService>(),
    timeline: _find<NetworkTimelineService>(),
    diagnostics: _find<DiagnosticReportService>(),
    nodeQuality: _find<NodeQualityService>(),
    scripts: _find<ScriptLibraryService>(),
  );

  final CoreService core;
  final HealthHistoryService? healthHistory;
  final TrafficStatisticsService? trafficStatistics;
  final NetworkTimelineService? timeline;
  final DiagnosticReportService? diagnostics;
  final NodeQualityService? nodeQuality;
  final ScriptLibraryService? scripts;
}

T? _find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
