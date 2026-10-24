import 'clash_connection.dart';

enum TrafficDimension { application, domain, node }

enum TrafficPeriod {
  today(1),
  week(7),
  month(30);

  const TrafficPeriod(this.days);
  final int days;
}

enum TrafficSort { total, upload, download }

class TrafficAmount {
  const TrafficAmount(this.upload, this.download);
  static const zero = TrafficAmount(0, 0);
  final int upload, download;
  int get total => upload + download;

  TrafficAmount operator +(TrafficAmount other) =>
      TrafficAmount(upload + other.upload, download + other.download);

  int valueFor(TrafficSort sort) => switch (sort) {
    TrafficSort.total => total,
    TrafficSort.upload => upload,
    TrafficSort.download => download,
  };

  Map<String, int> toMap() => {'upload': upload, 'download': download};

  factory TrafficAmount.fromMap(Object? value) {
    if (value is! Map ||
        value['upload'] is! int ||
        value['download'] is! int ||
        (value['upload'] as int) < 0 ||
        (value['download'] as int) < 0) {
      throw const FormatException('Invalid traffic counters');
    }
    return TrafficAmount(value['upload'] as int, value['download'] as int);
  }
}

class TrafficRankingEntry {
  const TrafficRankingEntry(this.name, this.usage);
  final String name;
  final TrafficAmount usage;
}

class DailyTrafficUsage {
  const DailyTrafficUsage(this.date, this.usage);
  final DateTime date;
  final TrafficAmount usage;
}

class ConnectionTrafficCounter {
  const ConnectionTrafficCounter(this.id, this.upload, this.download);
  final String id;
  final int upload, download;
}

/// Cumulative counters from a single native runtime, never per-second rates.
/// A baseline is captured before listeners start, including on Android where
/// native counters may survive a reconnect.
class CoreTrafficUpdate {
  const CoreTrafficUpdate({
    required this.session,
    this.connections = const [],
    this.counters = const [],
    this.totals,
    this.baseline = false,
  });

  final int session;
  final List<ClashConnection> connections;
  final List<ConnectionTrafficCounter> counters;
  final TrafficAmount? totals;
  final bool baseline;
}
