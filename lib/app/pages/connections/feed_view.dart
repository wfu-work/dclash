import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import 'connections_controller.dart';
import 'feed_controller.dart';

class FeedView extends StatefulWidget {
  const FeedView({super.key, required this.dns});
  final bool dns;
  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  late FeedController controller;

  FeedController _createController() =>
      FeedController(Get.find<ConnectionsController>().core, dns: widget.dns);

  @override
  void initState() {
    super.initState();
    controller = _createController();
  }

  @override
  void didUpdateWidget(covariant FeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dns != widget.dns) {
      controller.dispose();
      controller = _createController();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context, String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        AppMessage.success(context, 'featureCopied'.tr);
      }
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  void _details(Map<String, dynamic> record) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(widget.dns ? 'feedDnsDetails'.tr : 'feedRequestDetails'.tr),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: SelectableText(
            FeedController.encodeRecord(record),
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () =>
              _copy(dialogContext, FeedController.encodeRecord(record)),
          icon: const AppIcon(AppIcons.copy, size: 17),
          label: Text('featureCopy'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('featureDone'.tr),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPage(
      title: widget.dns ? 'featureDns'.tr : 'featureRequests'.tr,
      subtitle: widget.dns ? 'feedDnsSubtitle'.tr : 'feedRequestsSubtitle'.tr,
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
        IconButton(
          tooltip: 'featureClear'.tr,
          onPressed: controller.clear,
          icon: const AppIcon(AppIcons.delete),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            key: ValueKey(widget.dns),
            onChanged: (value) => controller.query.value = value,
            hint: 'feedSearch'.tr,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              final list = controller.visibleRecords;
              if (list.isEmpty) {
                return AppEmpty(
                  icon: widget.dns ? AppIcons.server : AppIcons.globe,
                  title: controller.query.value.isNotEmpty
                      ? 'featureNoResults'.tr
                      : 'feedEmpty'.tr,
                  message: controller.core.running
                      ? 'feedEmptyHint'.tr
                      : 'featureStartCore'.tr,
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final item = list[index];
                  final title = FeedController.value(
                    item,
                    widget.dns
                        ? ['domain', 'name', 'host', 'question']
                        : [
                            'url',
                            'host',
                            'destinationIP',
                            'destination',
                            'name',
                          ],
                  );
                  final type = FeedController.value(
                    item,
                    widget.dns
                        ? ['type', 'queryType', 'qtype']
                        : ['method', 'network', 'type'],
                  );
                  final detail = FeedController.value(
                    item,
                    widget.dns
                        ? [
                            'error',
                            'answer',
                            'answers',
                            'upstream',
                            'result',
                            'server',
                          ]
                        : ['rule', 'chains', 'source', 'process'],
                  );
                  final time = FeedController.value(item, [
                    'time',
                    'timestamp',
                    'start',
                  ]);
                  return Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _details(item),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 58,
                              child: Text(
                                type,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    detail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (time != '—') ...[
                                    const SizedBox(height: 7),
                                    Text(
                                      time,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const AppIcon(AppIcons.chevronRight, size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
