import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:get/get.dart';

import '../domains/diagnostic_privacy.dart';
import '../domains/network_health.dart';
import '../domains/network_health_report.dart';
import '../domains/network_timeline.dart';
import '../domains/traffic_statistics.dart';
import 'core_service.dart';
import 'health_history_service.dart';
import 'network_timeline_service.dart';
import 'settings_service.dart';
import 'traffic_statistics_service.dart';
import '../utils/format.dart';

/// Builds a local support bundle from already-collected state.
///
/// It never runs probes or sends data. Every external string is passed through
/// [DiagnosticPrivacy] before it can be copied or placed in the archive.
class DiagnosticReportService extends GetxService {
  DiagnosticReportService(
    this.core,
    this.settings,
    this.health,
    this.traffic,
    this.timeline, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const schemaVersion = 1;
  final CoreService core;
  final SettingsService settings;
  final HealthHistoryService health;
  final TrafficStatisticsService traffic;
  final NetworkTimelineService timeline;
  final DateTime Function() _clock;

  Map<String, dynamic> buildPayload() {
    final generatedAt = _clock().toUtc();
    final latest = health.entries.isEmpty ? null : health.entries.first;
    final day = traffic.usage(TrafficPeriod.today);
    final week = traffic.usage(TrafficPeriod.week);
    final errors = timeline.entries
        .where((event) => event.severity == TimelineSeverity.error)
        .take(20)
        .map(_event)
        .toList(growable: false);
    return {
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'privacy': {
        'sanitized': true,
        'omitted': [
          'profile contents',
          'subscription URLs and credentials',
          'request and DNS records',
          'raw logs',
          'private addresses',
        ],
      },
      'runtime': {
        'status': core.status.value.name,
        'version': DiagnosticPrivacy.sanitize(
          core.version.value,
          maxLength: 128,
        ),
        'mode': '${settings.fields['mode'] ?? ''}',
        'systemProxy': settings.fields['systemProxy'] == true,
        'tun': settings.fields['tunEnabled'] == true,
        'ipv6': settings.fields['ipv6'] == true,
        'activeConnections': core.connections.length,
        if (core.error.value case final error?)
          'error': DiagnosticPrivacy.sanitize(error, maxLength: 240),
      },
      'traffic': {'today': _usage(day), 'last7Days': _usage(week)},
      if (latest != null) 'healthCheck': _health(latest),
      'timeline': timeline.entries
          .take(100)
          .map(_event)
          .toList(growable: false),
      'recentErrors': errors,
    };
  }

  Map<String, dynamic> _usage(TrafficAmount usage) => {
    'upload': usage.upload,
    'download': usage.download,
    'total': usage.total,
  };

  Map<String, dynamic> _health(HealthReportEntry report) => {
    'checkedAt': report.checkedAt.toUtc().toIso8601String(),
    'target': DiagnosticPrivacy.sanitize(report.target, maxLength: 256),
    'advice': report.adviceKey,
    'checks': {
      for (final check in HealthCheck.values)
        if (report.results[check] case final result?)
          check.name: {
            'status': result.status.name,
            'message': result.message,
            'params': {
              for (final entry in result.params.entries)
                DiagnosticPrivacy.sanitize(entry.key, maxLength: 64):
                    DiagnosticPrivacy.sanitize(entry.value, maxLength: 256),
            },
            if (result.details.isNotEmpty)
              'details': DiagnosticPrivacy.sanitize(
                result.details,
                maxLength: 512,
              ),
          },
    },
  };

  Map<String, dynamic> _event(NetworkTimelineEvent event) => {
    'occurredAt': event.occurredAt.toUtc().toIso8601String(),
    'kind': event.kind.name,
    'severity': event.severity.name,
    'title': event.titleKey,
    'params': {
      for (final entry in event.params.entries)
        DiagnosticPrivacy.sanitize(entry.key, maxLength: 64):
            DiagnosticPrivacy.sanitize(entry.value, maxLength: 256),
    },
    if (event.detail.isNotEmpty)
      'detail': DiagnosticPrivacy.sanitize(event.detail, maxLength: 512),
  };

  String buildText() {
    final data = buildPayload();
    final runtime = data['runtime'] as Map;
    final traffic = data['traffic'] as Map;
    final today = traffic['today'] as Map;
    final lines = <String>[
      'diagnosticReportTitle'.tr,
      '${'diagnosticReportGenerated'.tr}: ${data['generatedAt']}',
      '',
      'diagnosticReportRuntime'.tr,
      '${'status'.tr}: ${'${runtime['status']}'.tr}',
      '${'diagnosticReportVersion'.tr}: ${runtime['version']}',
      '${'outboundMode'.tr}: ${'${runtime['mode']}'.tr}',
      '${'systemProxy'.tr}: ${runtime['systemProxy'] == true ? 'enabled'.tr : 'disabled'.tr}',
      '${'tun'.tr}: ${runtime['tun'] == true ? 'enabled'.tr : 'disabled'.tr}',
      '${'activeConnections'.tr}: ${runtime['activeConnections']}',
      '',
      'diagnosticReportTraffic'.tr,
      '${'trafficPeriod_today'.tr}: ${formatBytes(today['total'] as int)} (${'upload'.tr} ${formatBytes(today['upload'] as int)} · ${'download'.tr} ${formatBytes(today['download'] as int)})',
    ];
    if (runtime['error'] case final String error?) {
      lines.add('${'connectionError'.tr}: $error');
    }
    if (data['healthCheck'] case final Map healthCheck?) {
      lines
        ..add('')
        ..add('healthTitle'.tr)
        ..add('${'diagnosticReportTarget'.tr}: ${healthCheck['target']}')
        ..add(
          'healthCheckedAt'.trParams({'time': '${healthCheck['checkedAt']}'}),
        );
      final checks = healthCheck['checks'] as Map;
      for (final entry in checks.entries) {
        final result = entry.value as Map;
        lines.add(
          '${'healthCheck_${entry.key}'.tr}: ${'healthStatus_${result['status']}'.tr}',
        );
      }
    }
    final events = data['timeline'] as List;
    if (events.isNotEmpty) {
      lines
        ..add('')
        ..add('timelineTitle'.tr);
      for (final raw in events.take(30)) {
        final event = raw as Map;
        final title = '${event['title']}'.trParams(
          Map<String, String>.from(event['params'] as Map),
        );
        final detail = event['detail'] as String?;
        lines.add(
          '${event['occurredAt']} · $title${detail == null ? '' : '\n  $detail'}',
        );
      }
    }
    lines
      ..add('')
      ..add('diagnosticReportPrivacy'.tr);
    return lines.join('\n');
  }

  List<int> buildArchive() {
    final archive = Archive()
      ..add(ArchiveFile.string('dclash-diagnostic-report.txt', buildText()))
      ..add(
        ArchiveFile.string(
          'dclash-diagnostic-report.json',
          const JsonEncoder.withIndent('  ').convert(buildPayload()),
        ),
      );
    return ZipEncoder().encodeBytes(archive, modified: _clock().toUtc());
  }
}
