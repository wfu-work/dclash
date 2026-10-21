import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import '../../../widgets/traffic_chart.dart';

class TrafficCard extends StatelessWidget {
  const TrafficCard({
    super.key,
    required this.upload,
    required this.rate,
    required this.total,
    required this.history,
  });
  final bool upload;
  final int rate, total;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = upload
        ? colors.primary.withValues(alpha: .55)
        : colors.primary;
    final parts = formatBytes(rate).split(' ');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Row(
              children: [
                AppIcon(
                  upload ? AppIcons.arrowUp : AppIcons.arrowDown,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (upload ? 'upload' : 'download').tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: parts.first,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: ' ${parts.last}/s',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 12),
            child: Text(
              '${'total'.tr} ${formatBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TrafficChart(values: history, color: color, height: 50),
        ],
      ),
    );
  }
}
