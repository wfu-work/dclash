class NodeQualitySample {
  const NodeQualitySample({required this.at, required this.delay});
  final DateTime at;
  final int delay;

  Map<String, dynamic> toMap() => {
    'at': at.toUtc().toIso8601String(),
    'delay': delay,
  };

  factory NodeQualitySample.fromMap(Object? value) {
    if (value is! Map || value['at'] is! String || value['delay'] is! int) {
      throw const FormatException('Invalid node quality sample');
    }
    final at = DateTime.tryParse(value['at'] as String);
    final delay = value['delay'] as int;
    if (at == null || delay < -1 || delay > 300000) {
      throw const FormatException('Invalid node quality sample');
    }
    return NodeQualitySample(at: at.toUtc(), delay: delay);
  }
}

class NodeQualitySummary {
  const NodeQualitySummary({
    required this.name,
    required this.samples,
    required this.average,
    required this.jitter,
    required this.failureRate,
    required this.lastDelay,
  });
  final String name;
  final List<NodeQualitySample> samples;
  final int? average, jitter, lastDelay;
  final double failureRate;
  bool get unavailable => lastDelay == null || lastDelay! < 0;
}
