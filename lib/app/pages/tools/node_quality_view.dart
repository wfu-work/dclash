import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/node_quality.dart';
import '../../../services/node_quality_service.dart';
import '../../widgets/app_widgets.dart';

class NodeQualityView extends StatefulWidget {
  const NodeQualityView({super.key, this.quality});
  final NodeQualityService? quality;
  @override
  State<NodeQualityView> createState() => _NodeQualityViewState();
}

class _NodeQualityViewState extends State<NodeQualityView> {
  late final quality = widget.quality ?? Get.find<NodeQualityService>();
  var window = const Duration(minutes: 15);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 920,
        title: 'nodeQuality'.tr,
        subtitle: 'nodeQualityHelp'.tr,
        actions: [
          Obx(
            () => FilledButton.icon(
              key: const ValueKey('nodeQualityTestAll'),
              onPressed: quality.core.running && !quality.running.value
                  ? quality.testAll
                  : null,
              icon: quality.running.value
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon(AppIcons.gauge, size: 17),
              label: Text(
                quality.running.value
                    ? 'nodeQualityTesting'.tr
                    : 'nodeQualityTestAll'.tr,
              ),
            ),
          ),
        ],
        child: Obx(() {
          quality.revision.value;
          final nodes = quality.summaries(window);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <(String, Duration)>[
                    ('nodeQualityWindow_short', const Duration(minutes: 15)),
                    ('nodeQualityWindow_day', const Duration(days: 1)),
                    ('nodeQualityWindow_month', const Duration(days: 30)),
                  ])
                    ChoiceChip(
                      key: ValueKey('nodeQualityWindow_${entry.$1}'),
                      label: Text(entry.$1.tr),
                      selected: window == entry.$2,
                      onSelected: (_) => setState(() => window = entry.$2),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _QualitySummary(nodes: nodes),
              const SizedBox(height: 24),
              Text(
                'nodeQualityNodes'.tr,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (nodes.isEmpty)
                AppEmpty(
                  icon: AppIcons.gauge,
                  title: 'nodeQualityEmpty'.tr,
                  message: quality.core.running
                      ? 'nodeQualityEmptyHelp'.tr
                      : 'featureStartCore'.tr,
                  action: quality.core.running
                      ? FilledButton.icon(
                          onPressed: quality.running.value
                              ? null
                              : quality.testAll,
                          icon: const AppIcon(AppIcons.gauge, size: 17),
                          label: Text('nodeQualityTestAll'.tr),
                        )
                      : null,
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < nodes.length; index++) ...[
                        _NodeRow(
                          summary: nodes[index],
                          testing: quality.running.value,
                          onTest: () => quality.test(nodes[index].name),
                        ),
                        if (index + 1 < nodes.length) const Divider(height: 1),
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

class _QualitySummary extends StatelessWidget {
  const _QualitySummary({required this.nodes});
  final List<NodeQualitySummary> nodes;
  @override
  Widget build(BuildContext context) {
    final successful = nodes.where((node) => !node.unavailable).toList();
    final average = successful.isEmpty
        ? null
        : successful.map((node) => node.average!).reduce((a, b) => a + b) ~/
              successful.length;
    final failures = nodes.where((node) => node.failureRate > 0).length;
    return AppCard(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth < 500
              ? box.maxWidth
              : (box.maxWidth - 32) / 3;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _QualityMetric(
                width: width,
                label: 'nodeQualityTracked'.tr,
                value: '${nodes.length}',
              ),
              _QualityMetric(
                width: width,
                label: 'nodeQualityAverage'.tr,
                value: average == null ? '—' : '$average ms',
              ),
              _QualityMetric(
                width: width,
                label: 'nodeQualityUnstable'.tr,
                value: '$failures',
                error: failures > 0,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QualityMetric extends StatelessWidget {
  const _QualityMetric({
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

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.summary,
    required this.testing,
    required this.onTest,
  });
  final NodeQualitySummary summary;
  final bool testing;
  final VoidCallback onTest;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final trouble = summary.unavailable || summary.failureRate >= .25;
    final color = trouble ? colors.error : colors.primary;
    final delays = summary.samples
        .map((sample) => sample.delay < 0 ? 0.0 : sample.delay.toDouble())
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(AppIcons.gauge, color: color, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  summary.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'nodeQualityTestOne'.trParams({'name': summary.name}),
                onPressed: testing ? null : onTest,
                icon: const AppIcon(AppIcons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text(
                'nodeQualityLatest'.trParams({
                  'delay': summary.lastDelay == null || summary.lastDelay! < 0
                      ? '—'
                      : '${summary.lastDelay} ms',
                }),
              ),
              Text(
                'nodeQualityAverageValue'.trParams({
                  'delay': summary.average == null
                      ? '—'
                      : '${summary.average} ms',
                }),
              ),
              Text(
                'nodeQualityJitter'.trParams({
                  'delay': summary.jitter == null
                      ? '—'
                      : '${summary.jitter} ms',
                }),
              ),
              Text(
                'nodeQualityFailure'.trParams({
                  'percent': '${(summary.failureRate * 100).round()}%',
                }),
                style: TextStyle(color: trouble ? colors.error : null),
              ),
            ],
          ),
          if (delays.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 28,
              child: CustomPaint(
                painter: _DelaySparkline(delays, color),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DelaySparkline extends CustomPainter {
  const _DelaySparkline(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final max = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, double.infinity)
        .toDouble();
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i * size.width / (values.length - 1);
      final y = (size.height - 3 - values[i] / max * (size.height - 6))
          .toDouble();
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DelaySparkline old) =>
      old.values != values || old.color != color;
}
