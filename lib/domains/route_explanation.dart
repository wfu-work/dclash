import 'network_diagnostics.dart';

/// A no-I/O estimate returned by the native rule matcher.
class RouteExplanation {
  const RouteExplanation({
    required this.url,
    required this.host,
    required this.port,
    required this.rule,
    required this.rulePayload,
    required this.route,
    required this.selected,
    required this.finalOutbound,
    required this.needsDns,
    required this.exact,
    required this.stamp,
  });

  factory RouteExplanation.fromMap(Map data) {
    final stamp = DiagnosticStamp.fromMap(data);
    final port = data['port'];
    if (data['url'] is! String ||
        data['host'] is! String ||
        data['route'] is! String ||
        data['final'] is! String ||
        port is! int ||
        data['needs-dns'] is! bool ||
        data['exact'] is! bool) {
      throw const FormatException('Invalid route explanation response');
    }
    return RouteExplanation(
      url: data['url'] as String,
      host: data['host'] as String,
      port: port,
      rule: data['rule'] as String? ?? '',
      rulePayload: data['rule-payload'] as String? ?? '',
      route: data['route'] as String,
      selected: data['selected'] as String? ?? '',
      finalOutbound: data['final'] as String,
      needsDns: data['needs-dns'] as bool,
      exact: data['exact'] as bool,
      stamp: stamp,
    );
  }

  final String url, host, rule, rulePayload, route, selected, finalOutbound;
  final int port;
  final bool needsDns, exact;
  final DiagnosticStamp stamp;

  String get matchedRule => [
    rule,
    if (rulePayload.isNotEmpty) rulePayload,
  ].where((value) => value.isNotEmpty).join(',');
}
