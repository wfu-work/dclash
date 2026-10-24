import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/traffic_statistics.dart';
import 'package:dclash_flutter/services/core_service.dart';

ClashConnection trafficConnection({
  String id = 'one',
  String app = '/Applications/Browser.app/Browser',
  String host = 'EXAMPLE.com.',
  List<String> chains = const ['Tokyo', 'Proxy'],
  int upload = 100,
  int download = 200,
  DateTime? startedAt,
}) => ClashConnection(
  id: id,
  host: host,
  network: 'tcp',
  source: '127.0.0.1:12345',
  destination: '203.0.113.1:443',
  rule: 'MATCH',
  chains: chains,
  upload: upload,
  download: download,
  startedAt: startedAt ?? DateTime(2026, 10, 23, 12),
  process: app,
);

void trafficBaseline(
  CoreService core, {
  int session = 1,
  int upload = 0,
  int download = 0,
}) {
  core.trafficUpdate.value = CoreTrafficUpdate(
    session: session,
    baseline: true,
    totals: TrafficAmount(upload, download),
  );
}

void trafficSample(
  CoreService core, {
  int session = 1,
  int? upload,
  int? download,
  List<ClashConnection> connections = const [],
  List<ConnectionTrafficCounter> counters = const [],
}) {
  core.trafficUpdate.value = CoreTrafficUpdate(
    session: session,
    totals: upload != null && download != null
        ? TrafficAmount(upload, download)
        : null,
    connections: connections,
    counters: counters,
  );
}
