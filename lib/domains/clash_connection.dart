class ClashConnection {
  const ClashConnection({
    required this.id,
    required this.host,
    required this.network,
    required this.source,
    required this.destination,
    required this.rule,
    required this.chains,
    required this.upload,
    required this.download,
    required this.startedAt,
    this.process = '',
  });
  final String id, host, network, source, destination, rule, process;
  final List<String> chains;
  final int upload, download;
  final DateTime startedAt;
}

class CoreLog {
  const CoreLog({
    required this.level,
    required this.message,
    required this.time,
  });
  final String level, message;
  final DateTime time;
}
