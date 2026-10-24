class DiagnosticService {
  const DiagnosticService(this.id, this.name, this.category);

  final String id;
  final String name;
  final String category;

  static const all = [
    DiagnosticService('google', 'Google', 'diagnosticGeneral'),
    DiagnosticService('github', 'GitHub', 'diagnosticGeneral'),
    DiagnosticService('discord', 'Discord', 'diagnosticGeneral'),
    DiagnosticService('chatgpt', 'ChatGPT', 'diagnosticAi'),
    DiagnosticService('claude', 'Claude', 'diagnosticAi'),
    DiagnosticService('gemini', 'Gemini', 'diagnosticAi'),
    DiagnosticService('youtube', 'YouTube Premium', 'diagnosticMedia'),
    DiagnosticService('netflix', 'Netflix', 'diagnosticMedia'),
    DiagnosticService('disney-plus', 'Disney+', 'diagnosticMedia'),
    DiagnosticService('prime-video', 'Prime Video', 'diagnosticMedia'),
    DiagnosticService('spotify', 'Spotify', 'diagnosticMedia'),
    DiagnosticService('tiktok', 'TikTok', 'diagnosticMedia'),
    DiagnosticService('bilibili', 'Bilibili', 'diagnosticMedia'),
  ];
}

/// A result is only valid for the applied configuration and proxy selections
/// that produced it, including automatic selections made inside the core.
class DiagnosticStamp {
  const DiagnosticStamp(this.coreEpoch, this.picksVersion);

  factory DiagnosticStamp.fromMap(Map data) =>
      DiagnosticStamp(data['core-epoch'] as int, data['picks-version'] as int);

  final int coreEpoch;
  final int picksVersion;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticStamp &&
      other.coreEpoch == coreEpoch &&
      other.picksVersion == picksVersion;

  @override
  int get hashCode => Object.hash(coreEpoch, picksVersion);
}

class UrlDiagnosticResult {
  UrlDiagnosticResult({
    required this.requestedUrl,
    required this.proxyName,
    required Map data,
  }) : url = data['url'] as String? ?? requestedUrl,
       statusCode = data['status-code'] as int? ?? 0,
       delay = data['delay'] as int? ?? 0,
       rule = data['rule'] as String? ?? '',
       rulePayload = data['rule-payload'] as String? ?? '',
       chains = List<String>.from(data['chains'] as List? ?? []),
       error = data['error'] as String? ?? '',
       message = data['message'] as String? ?? '',
       stamp = DiagnosticStamp.fromMap(data);

  final String requestedUrl, proxyName, url, rule, rulePayload, error, message;
  final int statusCode, delay;
  final List<String> chains;
  final DiagnosticStamp stamp;

  bool get receivedResponse => error.isEmpty && statusCode >= 100;
  bool get successful => receivedResponse && statusCode < 400;
  String get matchedRule =>
      [rule, if (rulePayload.isNotEmpty) rulePayload].join(',');
}

class ServiceDiagnosticResult {
  ServiceDiagnosticResult.fromMap(Map data)
    : status = data['status'] as String,
      region = data['region'] as String? ?? '',
      delay = data['delay'] as int? ?? 0,
      chains = List<String>.from(data['chains'] as List? ?? []),
      checkedAt = DateTime.fromMillisecondsSinceEpoch(
        data['checked-at'] as int,
      ),
      stamp = DiagnosticStamp.fromMap(data),
      message = '';

  ServiceDiagnosticResult.failure(this.status, this.message)
    : region = '',
      delay = 0,
      chains = const [],
      checkedAt = DateTime.now(),
      stamp = null;

  final String status, region, message;
  final int delay;
  final List<String> chains;
  final DateTime checkedAt;
  final DiagnosticStamp? stamp;
}
