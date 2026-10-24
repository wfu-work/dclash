import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../domains/network_health.dart';
import '../../../domains/network_health_report.dart';
import '../../../services/health_history_service.dart';
import '../../../storage/atomic_file.dart';
import '../../widgets/app_widgets.dart';

class NetworkHealthHistoryView extends StatelessWidget {
  const NetworkHealthHistoryView({super.key, this.history});

  final HealthHistoryService? history;

  HealthHistoryService get _history =>
      history ?? Get.find<HealthHistoryService>();

  Future<void> _clear(BuildContext context) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'healthHistoryClear'.tr,
      message: 'healthHistoryClearConfirm'.tr,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await _history.clear();
      if (context.mounted) {
        AppMessage.success(context, 'healthHistoryCleared'.tr);
      }
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'healthHistory'.tr,
        subtitle: 'healthHistoryHelp'.tr,
        actions: [
          Obx(
            () => IconButton(
              tooltip: 'healthHistoryClear'.tr,
              onPressed: _history.entries.isEmpty
                  ? null
                  : () => _clear(context),
              icon: const AppIcon(AppIcons.delete),
            ),
          ),
        ],
        child: Obx(() {
          final entries = _history.entries;
          if (entries.isEmpty) {
            return AppEmpty(
              icon: AppIcons.checkList,
              title: 'healthHistoryEmpty'.tr,
              message: 'healthHistoryEmptyHelp'.tr,
            );
          }
          return AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  _HistoryRow(entry: entries[index]),
                  if (index + 1 < entries.length) const Divider(height: 1),
                ],
              ],
            ),
          );
        }),
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HealthReportEntry entry;

  @override
  Widget build(BuildContext context) {
    final failures = entry.results.values
        .where((result) => result.status == HealthStatus.failed)
        .length;
    final warnings = entry.results.values
        .where((result) => result.status == HealthStatus.warning)
        .length;
    return AppSettingsRow(
      key: ValueKey('healthHistory_${entry.id}'),
      title: entry.target,
      subtitle:
          '${_date(context, entry.checkedAt)} · ${'healthCounts'.trParams({'failed': '$failures', 'warnings': '$warnings'})}',
      icon: AppIcons.checkList,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NetworkHealthReportView(entry: entry),
        ),
      ),
    );
  }
}

class NetworkHealthReportView extends StatelessWidget {
  const NetworkHealthReportView({super.key, required this.entry});

  final HealthReportEntry entry;

  String _report() => formatHealthReport(entry);

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: _report()));
      if (context.mounted) AppMessage.success(context, 'featureCopied'.tr);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final report = _report();
      final bytes = Uint8List.fromList(utf8.encode(report));
      final stamp = entry.checkedAt.toUtc().toIso8601String().replaceAll(
        RegExp(r'[-:.]'),
        '',
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'healthExport'.tr,
        fileName: 'dclash-network-health-$stamp.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );
      if (path != null && !path.startsWith('content:')) {
        await writePrivateAtomic(File(path), bytes);
      }
      if (path != null && context.mounted) {
        AppMessage.success(context, 'featureExported'.tr);
      }
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'healthReport'.tr,
        subtitle: '${entry.target} · ${_date(context, entry.checkedAt)}',
        actions: [
          IconButton(
            tooltip: 'healthCopy'.tr,
            onPressed: () => _copy(context),
            icon: const AppIcon(AppIcons.copy),
          ),
          IconButton(
            tooltip: 'healthExport'.tr,
            onPressed: () => _export(context),
            icon: const AppIcon(AppIcons.share),
          ),
        ],
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final check in HealthCheck.values)
                if (entry.results[check] case final result?) ...[
                  _HistoryResult(check: check, result: result),
                  if (check != HealthCheck.values.last)
                    const Divider(height: 32),
                ],
              if (entry.adviceKey case final advice?) ...[
                const SizedBox(height: 4),
                Text(advice.tr),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _HistoryResult extends StatelessWidget {
  const _HistoryResult({required this.check, required this.result});

  final HealthCheck check;
  final HealthResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (result.status) {
      HealthStatus.passed => colors.primary,
      HealthStatus.failed => colors.error,
      HealthStatus.warning => colors.secondary,
      _ => colors.onSurfaceVariant,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'healthCheck_${check.name}'.tr,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            AppPill(
              label: 'healthStatus_${result.status.name}'.tr,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(result.message.trParams(result.params)),
        if (result.details.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(
            result.details,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

String formatHealthReport(HealthReportEntry entry) => [
  'healthTitle'.tr,
  entry.target,
  entry.checkedAt.toLocal().toIso8601String(),
  for (final check in HealthCheck.values)
    if (entry.results[check] case final result?) ...[
      '',
      '${'healthCheck_${check.name}'.tr} · ${'healthStatus_${result.status.name}'.tr}',
      result.message.trParams(result.params),
      if (result.details.isNotEmpty) result.details,
    ],
  if (entry.adviceKey case final advice?) ...['', advice.tr],
].join('\n');

String _date(BuildContext context, DateTime value) =>
    '${MaterialLocalizations.of(context).formatShortDate(value.toLocal())} ${TimeOfDay.fromDateTime(value.toLocal()).format(context)}';
