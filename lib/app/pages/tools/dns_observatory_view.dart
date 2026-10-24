import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';

class DnsObservatoryView extends StatelessWidget {
  const DnsObservatoryView({super.key, this.core});
  final CoreService? core;
  CoreService get _core => core ?? Get.find<CoreService>();

  static String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) continue;
      final text = value is List ? value.join(', ') : '$value';
      if (text.trim().isNotEmpty) return text.trim();
    }
    return '';
  }

  static bool _failed(Map<String, dynamic> item) =>
      _value(item, ['error', 'err', 'message']).isNotEmpty;

  static int? _latency(Map<String, dynamic> item) {
    final value = item['delay'] ?? item['latency'] ?? item['duration'];
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 920,
        title: 'dnsObservatory'.tr,
        subtitle: 'dnsObservatoryHelp'.tr,
        child: Obx(() {
          final records = _core.dnsQueries;
          final failed = records.where(_failed).length;
          final latencies = records
              .map(_latency)
              .whereType<int>()
              .where((value) => value >= 0)
              .toList();
          final average = latencies.isEmpty
              ? null
              : latencies.reduce((a, b) => a + b) ~/ latencies.length;
          final domains = <String, _DnsAggregate>{};
          for (final record in records) {
            final name = _value(record, ['domain', 'name', 'host', 'question']);
            if (name.isEmpty) continue;
            final aggregate = domains.putIfAbsent(name, _DnsAggregate.new);
            aggregate.count++;
            if (_failed(record)) aggregate.failed++;
            if (_latency(record) case final delay?) aggregate.delays.add(delay);
          }
          final rankings = domains.entries.toList()
            ..sort((a, b) {
              final order = b.value.count.compareTo(a.value.count);
              return order != 0 ? order : a.key.compareTo(b.key);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DnsSummary(
                total: records.length,
                failed: failed,
                average: average,
              ),
              const SizedBox(height: 24),
              Text(
                'dnsObservatoryDomains'.tr,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (rankings.isEmpty)
                AppEmpty(
                  icon: AppIcons.server,
                  title: 'dnsObservatoryEmpty'.tr,
                  message: _core.running
                      ? 'dnsObservatoryEmptyHelp'.tr
                      : 'featureStartCore'.tr,
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < rankings.length; index++) ...[
                        _DnsRow(
                          name: rankings[index].key,
                          aggregate: rankings[index].value,
                        ),
                        if (index + 1 < rankings.length)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
    ),
  );
}

class _DnsAggregate {
  int count = 0;
  int failed = 0;
  final delays = <int>[];
  int? get average =>
      delays.isEmpty ? null : delays.reduce((a, b) => a + b) ~/ delays.length;
}

class _DnsSummary extends StatelessWidget {
  const _DnsSummary({
    required this.total,
    required this.failed,
    required this.average,
  });
  final int total, failed;
  final int? average;
  @override
  Widget build(BuildContext context) => AppCard(
    child: LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < 500
            ? box.maxWidth
            : (box.maxWidth - 32) / 3;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _Metric(
              width: width,
              label: 'dnsObservatoryQueries'.tr,
              value: '$total',
            ),
            _Metric(
              width: width,
              label: 'dnsObservatoryFailures'.tr,
              value: '$failed',
              error: failed > 0,
            ),
            _Metric(
              width: width,
              label: 'dnsObservatoryLatency'.tr,
              value: average == null ? '—' : '$average ms',
            ),
          ],
        );
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    this.error = false,
  });
  final double width;
  final String label, value;
  final bool error;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: error ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    ),
  );
}

class _DnsRow extends StatelessWidget {
  const _DnsRow({required this.name, required this.aggregate});
  final String name;
  final _DnsAggregate aggregate;
  @override
  Widget build(BuildContext context) {
    final failure = aggregate.failed > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          AppIcon(
            AppIcons.server,
            color: failure
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            size: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'dnsObservatoryCount'.trParams({'count': '${aggregate.count}'}),
              ),
              Text(
                aggregate.failed > 0
                    ? 'dnsObservatoryFailed'.trParams({
                        'count': '${aggregate.failed}',
                      })
                    : aggregate.average == null
                    ? '—'
                    : '${aggregate.average} ms',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: failure ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
