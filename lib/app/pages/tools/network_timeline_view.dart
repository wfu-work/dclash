import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../domains/network_timeline.dart';
import '../../../services/diagnostic_report_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../storage/atomic_file.dart';
import '../../widgets/app_widgets.dart';

class NetworkTimelineView extends StatelessWidget {
  const NetworkTimelineView({super.key, this.timeline, this.report});

  final NetworkTimelineService? timeline;
  final DiagnosticReportService? report;

  NetworkTimelineService get _timeline =>
      timeline ?? Get.find<NetworkTimelineService>();
  DiagnosticReportService get _report =>
      report ?? Get.find<DiagnosticReportService>();

  Future<void> _clear(BuildContext context) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'timelineClear'.tr,
      message: 'timelineClearConfirm'.tr,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await _timeline.clear();
      if (context.mounted) AppMessage.success(context, 'timelineCleared'.tr);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'timelineTitle'.tr,
        subtitle: 'timelineHelp'.tr,
        actions: [
          IconButton(
            tooltip: 'diagnosticReportTitle'.tr,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DiagnosticReportView(report: _report),
              ),
            ),
            icon: const AppIcon(AppIcons.share),
          ),
          Obx(
            () => IconButton(
              tooltip: 'timelineClear'.tr,
              onPressed: _timeline.entries.isEmpty
                  ? null
                  : () => _clear(context),
              icon: const AppIcon(AppIcons.delete),
            ),
          ),
        ],
        child: Obx(() {
          final events = _timeline.entries;
          if (events.isEmpty) {
            return AppEmpty(
              icon: AppIcons.terminal,
              title: 'timelineEmpty'.tr,
              message: 'timelineEmptyHelp'.tr,
            );
          }
          return AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < events.length; index++) ...[
                  _TimelineRow(event: events[index]),
                  if (index + 1 < events.length) const Divider(height: 1),
                ],
              ],
            ),
          );
        }),
      ),
    ),
  );
}

class DiagnosticReportView extends StatelessWidget {
  const DiagnosticReportView({super.key, this.report});

  final DiagnosticReportService? report;
  DiagnosticReportService get _report =>
      report ?? Get.find<DiagnosticReportService>();

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: _report.buildText()));
      if (context.mounted) AppMessage.success(context, 'featureCopied'.tr);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final bytes = _report.buildArchive();
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[-:.]'),
        '',
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'diagnosticReportExport'.tr,
        fileName: 'dclash-diagnostic-report-$stamp.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Uint8List.fromList(bytes),
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
        title: 'diagnosticReportTitle'.tr,
        subtitle: 'diagnosticReportHelp'.tr,
        actions: [
          IconButton(
            tooltip: 'healthCopy'.tr,
            onPressed: () => _copy(context),
            icon: const AppIcon(AppIcons.copy),
          ),
          IconButton(
            tooltip: 'diagnosticReportExport'.tr,
            onPressed: () => _export(context),
            icon: const AppIcon(AppIcons.share),
          ),
        ],
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppMessage(
                message: 'diagnosticReportPrivacy'.tr,
                tone: AppMessageTone.info,
              ),
              const SizedBox(height: 16),
              SelectableText(
                _report.buildText(),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});
  final NetworkTimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (event.severity) {
      TimelineSeverity.error => colors.error,
      TimelineSeverity.warning => colors.secondary,
      TimelineSeverity.info => colors.primary,
    };
    final icon = switch (event.kind) {
      TimelineKind.core => AppIcons.power,
      TimelineKind.health => AppIcons.checkList,
      TimelineKind.route => AppIcons.route,
      TimelineKind.settings => AppIcons.settings,
      TimelineKind.error => AppIcons.warning,
      TimelineKind.traffic => AppIcons.swap,
    };
    final at = event.occurredAt.toLocal();
    final time =
        '${MaterialLocalizations.of(context).formatShortDate(at)} ${TimeOfDay.fromDateTime(at).format(context)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, color: color, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.titleKey.trParams(event.params),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (event.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    event.detail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Text(time, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
