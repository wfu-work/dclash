enum HealthCheck { core, listener, systemProxy, dns, direct, routing }

enum HealthStatus { checking, passed, warning, failed, skipped }

enum HealthAction { overview, profiles, networkSettings, urlDiagnostics, logs }

class HealthResult {
  const HealthResult(
    this.status,
    this.message, {
    this.params = const {},
    this.details = '',
    this.action,
  });

  final HealthStatus status;
  final String message;
  final Map<String, String> params;
  final String details;
  final HealthAction? action;
}

class SystemProxyEndpoint {
  const SystemProxyEndpoint({
    required this.enabled,
    this.host = '',
    this.port = 0,
  });

  final bool enabled;
  final String host;
  final int port;

  bool matches(int expectedPort) =>
      enabled &&
      const {
        '127.0.0.1',
        'localhost',
        '::1',
        '[::1]',
      }.contains(host.toLowerCase()) &&
      port == expectedPort;

  @override
  String toString() => enabled ? '$host:$port' : '—';
}

/// Observed OS settings, independent of the app's requested proxy switch.
class SystemProxySnapshot {
  const SystemProxySnapshot({
    required this.http,
    required this.https,
    this.automatic = false,
    this.otherEnabled = false,
  });

  final SystemProxyEndpoint http, https;
  final bool automatic, otherEnabled;

  bool matches(int port) =>
      !automatic && http.matches(port) && https.matches(port);

  bool get enabled =>
      automatic || otherEnabled || http.enabled || https.enabled;

  String get details =>
      'HTTP: $http\nHTTPS: $https${automatic ? '\nPAC / WPAD' : ''}';
}
