import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import 'log_tile.dart';
import 'logs_controller.dart';

class LogsView extends GetView<LogsController> {
  const LogsView({super.key});
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _copy(BuildContext context, String value) =>
      _run(context, () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          AppMessage.success(context, 'featureCopied'.tr);
        }
      });
  Future<void> _export(BuildContext context) => _run(context, () async {
    final content = controller.exportText;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'logsExport'.tr,
      fileName:
          'dclash-${DateTime.now().toIso8601String().split('T').first}.log',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path != null) {
      await File(path).writeAsString(content);
      if (context.mounted) {
        AppMessage.success(context, 'featureExported'.tr);
      }
    }
  });
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'featureLogs'.tr,
    subtitle: 'logsSubtitle'.tr,
    scroll: false,
    actions: [
      Obx(
        () => IconButton(
          tooltip: controller.paused.value
              ? 'featureResume'.tr
              : 'featurePause'.tr,
          onPressed: controller.togglePause,
          icon: AppIcon(
            controller.paused.value ? AppIcons.play : AppIcons.pause,
          ),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: 'featureMore'.tr,
        icon: const AppIcon(AppIcons.more),
        onSelected: (value) {
          switch (value) {
            case 'copy':
              _copy(context, controller.exportText);
            case 'export':
              _export(context);
            case 'clear':
              controller.clear();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'copy', child: Text('logsCopyAll'.tr)),
          PopupMenuItem(value: 'export', child: Text('logsExport'.tr)),
          PopupMenuItem(value: 'clear', child: Text('featureClear'.tr)),
        ],
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          onChanged: (value) => controller.query.value = value,
          hint: 'logsSearch'.tr,
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Obx(
            () => Row(
              children: ['all', 'debug', 'info', 'warning', 'error']
                  .map(
                    (value) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('logsLevel_$value'.tr),
                        selected: controller.level.value == value,
                        onSelected: (_) => controller.level.value = value,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Obx(() {
            final logs = controller.visibleLogs;
            if (logs.isEmpty) {
              return AppEmpty(
                icon: AppIcons.terminal,
                title:
                    controller.query.value.isNotEmpty ||
                        controller.level.value != 'all'
                    ? 'featureNoResults'.tr
                    : 'logsEmpty'.tr,
                message: controller.core.running
                    ? 'logsEmptyHint'.tr
                    : 'featureStartCore'.tr,
              );
            }
            return ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .45),
              ),
              itemBuilder: (_, index) => LogTile(
                log: logs[index],
                onCopy: () => _copy(context, controller.format(logs[index])),
              ),
            );
          }),
        ),
      ],
    ),
  );
}
