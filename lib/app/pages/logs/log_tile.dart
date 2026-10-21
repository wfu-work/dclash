import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/clash_connection.dart';
import '../../widgets/app_icon.dart';

class LogTile extends StatelessWidget {
  const LogTile({super.key, required this.log, required this.onCopy});
  final CoreLog log;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final level = log.level.toLowerCase();
    final color = switch (level) {
      'error' || 'fatal' => colors.error,
      'warning' || 'warn' => const Color(0xffb37519),
      'debug' => colors.onSurfaceVariant,
      _ => colors.primary,
    };
    final time = log.time.toLocal();
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      timeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      level.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  log.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'featureCopy'.tr,
            onPressed: onCopy,
            icon: const AppIcon(AppIcons.copy, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
