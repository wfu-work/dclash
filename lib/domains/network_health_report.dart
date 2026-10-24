import 'dart:math';

import 'network_health.dart';

/// A bounded, local snapshot of a completed network health check.
///
/// The target and textual details are sanitized before they reach persistent
/// storage so URL query strings, fragments, and credentials are not retained.
class HealthReportEntry {
  const HealthReportEntry({
    required this.id,
    required this.checkedAt,
    required this.target,
    required this.results,
    this.adviceKey,
  });

  static const schemaVersion = 1;
  static const maxTargetLength = 1024;
  static const maxDetailLength = 2048;
  static const maxParams = 8;

  final String id;
  final DateTime checkedAt;
  final String target;
  final Map<HealthCheck, HealthResult> results;
  final String? adviceKey;

  factory HealthReportEntry.capture({
    required DateTime checkedAt,
    required String target,
    required Map<HealthCheck, HealthResult> results,
    String? adviceKey,
    String? id,
  }) {
    final snapshot = <HealthCheck, HealthResult>{
      for (final check in HealthCheck.values)
        if (results[check] case final result?)
          check: HealthResult(
            result.status,
            _limit(result.message, maxTargetLength),
            params: Map<String, String>.unmodifiable({
              for (final entry in result.params.entries.take(maxParams))
                _limit(entry.key, 64): _limit(entry.value, 256),
            }),
            details: sanitizeText(result.details, maxLength: maxDetailLength),
            action: result.action,
          ),
    };
    return HealthReportEntry(
      id:
          id ??
          '${checkedAt.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}',
      checkedAt: checkedAt.toUtc(),
      target: sanitizeTarget(target),
      results: Map<HealthCheck, HealthResult>.unmodifiable(snapshot),
      adviceKey: adviceKey,
    );
  }

  factory HealthReportEntry.fromMap(Map data) {
    if (data['version'] != schemaVersion ||
        data['id'] is! String ||
        data['target'] is! String ||
        data['checkedAt'] is! String ||
        data['checks'] is! Map) {
      throw const FormatException('Invalid network health history entry');
    }
    final id = data['id'] as String;
    final checkedAt = DateTime.tryParse(data['checkedAt'] as String);
    final target = sanitizeTarget(data['target'] as String);
    if (id.isEmpty ||
        id.length > 128 ||
        checkedAt == null ||
        target.isEmpty ||
        target.length > maxTargetLength) {
      throw const FormatException('Invalid network health history entry');
    }
    final rawChecks = data['checks'] as Map;
    final results = <HealthCheck, HealthResult>{};
    for (final check in HealthCheck.values) {
      final raw = rawChecks[check.name];
      if (raw is! Map ||
          raw['status'] is! String ||
          raw['message'] is! String ||
          raw['params'] is! Map ||
          raw['details'] is! String) {
        throw const FormatException('Invalid network health history check');
      }
      final status = HealthStatus.values.where(
        (value) => value.name == raw['status'],
      );
      if (status.length != 1 ||
          (raw['action'] != null && raw['action'] is! String)) {
        throw const FormatException('Invalid network health history check');
      }
      final actionName = raw['action'] as String?;
      final matchingActions = actionName == null
          ? const <HealthAction>[]
          : HealthAction.values
                .where((value) => value.name == actionName)
                .toList(growable: false);
      if (actionName != null && matchingActions.length != 1) {
        throw const FormatException('Invalid network health history check');
      }
      final action = matchingActions.isEmpty ? null : matchingActions.single;
      final params = <String, String>{};
      for (final entry in (raw['params'] as Map).entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            params.length >= maxParams) {
          throw const FormatException(
            'Invalid network health history parameters',
          );
        }
        params[_limit(entry.key as String, 64)] = _limit(
          entry.value as String,
          256,
        );
      }
      results[check] = HealthResult(
        status.single,
        _limit(raw['message'] as String, maxTargetLength),
        params: Map.unmodifiable(params),
        details: sanitizeText(
          raw['details'] as String,
          maxLength: maxDetailLength,
        ),
        action: action,
      );
    }
    final advice = data['advice'] as String?;
    if (advice != null && advice.length > 128) {
      throw const FormatException('Invalid network health history advice');
    }
    return HealthReportEntry(
      id: id,
      checkedAt: checkedAt.toUtc(),
      target: target,
      results: Map.unmodifiable(results),
      adviceKey: advice,
    );
  }

  Map<String, dynamic> toMap() => {
    'version': schemaVersion,
    'id': id,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'target': target,
    'checks': {
      for (final check in HealthCheck.values)
        if (results[check] case final result?)
          check.name: {
            'status': result.status.name,
            'message': result.message,
            'params': result.params,
            'details': result.details,
            'action': result.action?.name,
          },
    },
    if (adviceKey != null) 'advice': adviceKey,
  };

  static String sanitizeTarget(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return '';
    }
    // Construct a fresh URI instead of using [Uri.replace]: omitted nullable
    // arguments can preserve the original query on some URI implementations.
    return _limit(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString(),
      maxTargetLength,
    );
  }

  static String sanitizeText(String value, {required int maxLength}) {
    final redacted = value.replaceAllMapped(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      (match) {
        final target = sanitizeTarget(match.group(0)!);
        return target.isEmpty ? '<invalid-url>' : target;
      },
    );
    return _limit(redacted.replaceAll('\u0000', ''), maxLength);
  }

  static String _limit(String value, int maxLength) => value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength - 1)}…';
}
