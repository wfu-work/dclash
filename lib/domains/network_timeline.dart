import 'dart:math';

import 'diagnostic_privacy.dart';

enum TimelineKind { core, health, route, settings, error, traffic }

enum TimelineSeverity { info, warning, error }

class NetworkTimelineEvent {
  const NetworkTimelineEvent({
    required this.id,
    required this.occurredAt,
    required this.kind,
    required this.severity,
    required this.titleKey,
    this.params = const {},
    this.detail = '',
  });

  static const schemaVersion = 1;
  final String id;
  final DateTime occurredAt;
  final TimelineKind kind;
  final TimelineSeverity severity;
  final String titleKey;
  final Map<String, String> params;
  final String detail;

  factory NetworkTimelineEvent.create({
    required TimelineKind kind,
    required TimelineSeverity severity,
    required String titleKey,
    Map<String, String> params = const {},
    String detail = '',
    DateTime? occurredAt,
  }) {
    final at = (occurredAt ?? DateTime.now()).toUtc();
    return NetworkTimelineEvent(
      id: '${at.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}',
      occurredAt: at,
      kind: kind,
      severity: severity,
      titleKey: titleKey,
      params: Map.unmodifiable(params),
      detail: detail,
    );
  }

  factory NetworkTimelineEvent.fromMap(Object? data) {
    if (data is! Map ||
        data['version'] != schemaVersion ||
        data['id'] is! String ||
        data['occurredAt'] is! String ||
        data['kind'] is! String ||
        data['severity'] is! String ||
        data['title'] is! String ||
        data['params'] is! Map ||
        data['detail'] is! String) {
      throw const FormatException('Invalid network timeline event');
    }
    final id = data['id'] as String;
    final occurredAt = DateTime.tryParse(data['occurredAt'] as String);
    final kind = TimelineKind.values.where(
      (value) => value.name == data['kind'],
    );
    final severity = TimelineSeverity.values.where(
      (value) => value.name == data['severity'],
    );
    if (id.isEmpty ||
        id.length > 128 ||
        occurredAt == null ||
        kind.length != 1 ||
        severity.length != 1 ||
        (data['title'] as String).isEmpty ||
        (data['title'] as String).length > 128 ||
        (data['detail'] as String).length > 512) {
      throw const FormatException('Invalid network timeline event');
    }
    final params = <String, String>{};
    for (final entry in (data['params'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          entry.key.length > 64 ||
          entry.value.length > 256 ||
          params.length >= 8) {
        throw const FormatException('Invalid network timeline parameters');
      }
      params[DiagnosticPrivacy.sanitize(entry.key as String, maxLength: 64)] =
          DiagnosticPrivacy.sanitize(entry.value as String, maxLength: 256);
    }
    return NetworkTimelineEvent(
      id: id,
      occurredAt: occurredAt.toUtc(),
      kind: kind.single,
      severity: severity.single,
      titleKey: data['title'] as String,
      params: Map.unmodifiable(params),
      detail: DiagnosticPrivacy.sanitize(
        data['detail'] as String,
        maxLength: 512,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'version': schemaVersion,
    'id': id,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'kind': kind.name,
    'severity': severity.name,
    'title': titleKey,
    'params': params,
    'detail': detail,
  };
}
