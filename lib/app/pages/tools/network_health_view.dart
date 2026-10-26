import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../configs/app_services_bridge.dart';
import '../../../domains/network_health.dart';
import '../../../platform/network_health_host.dart';
import '../../../services/core_service.dart';
import '../../../services/health_history_service.dart';
import '../../widgets/app_widgets.dart';
import '../logs/logs_view.dart';
import '../settings/settings_view.dart';
import '../workspace/workspace_controller.dart';
import 'network_diagnostics_controller.dart';
import 'network_diagnostics_view.dart';
import 'network_health_controller.dart';
import 'network_health_history_view.dart';

class NetworkHealthView extends StatefulWidget {
  const NetworkHealthView({super.key, this.host, this.history, this.core});

  final NetworkHealthHost? host;
  final HealthHistoryService? history;
  final CoreService? core;

  @override
  State<NetworkHealthView> createState() => _NetworkHealthViewState();
}

class _NetworkHealthViewState extends State<NetworkHealthView> {
  late final controller = NetworkHealthController(
    widget.core ?? coreFromGetX(),
    host: widget.host,
    history: widget.history ?? optionalServiceFromGetX<HealthHistoryService>(),
  );
  late final _url = TextEditingController(text: controller.defaultUrl);
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    controller.onInit();
  }

  @override
  void dispose() {
    controller.onClose();
    _url.dispose();
    super.dispose();
  }

  void _run() {
    if (_form.currentState!.validate()) controller.run(_url.text);
  }

  void _open(HealthAction action) {
    if (action == HealthAction.overview || action == HealthAction.profiles) {
      Get.find<WorkspaceController>().select(
        action == HealthAction.profiles ? 2 : 0,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final page = switch (action) {
      HealthAction.networkSettings => const SettingsView(section: 'network'),
      HealthAction.urlDiagnostics => UrlDiagnosticsView(
        initialUrl: controller.testedUrl,
      ),
      _ => const Scaffold(body: SafeArea(child: LogsView())),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: controller.report));
      if (mounted) AppMessage.success(context, 'featureCopied'.tr);
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'healthTitle'.tr,
        subtitle: 'healthHelp'.tr,
        actions: [
          Obx(
            () => IconButton(
              tooltip: 'healthCopy'.tr,
              onPressed: controller.finishedAt.value != null ? _copy : null,
              icon: const AppIcon(AppIcons.copy),
            ),
          ),
          if (controller.history != null)
            IconButton(
              tooltip: 'healthHistory'.tr,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      NetworkHealthHistoryView(history: controller.history),
                ),
              ),
              icon: const AppIcon(AppIcons.list),
            ),
        ],
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.notice.value case final notice?) ...[
                AppMessage(message: notice.tr, tone: AppMessageTone.warning),
                const SizedBox(height: 16),
              ],
              AppCard(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('healthUrlInput'),
                        controller: _url,
                        enabled: !controller.running.value,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'diagnosticUrlLabel'.tr,
                        ),
                        validator: (value) =>
                            NetworkDiagnosticsController.parseUrl(
                                  value ?? '',
                                ) ==
                                null
                            ? 'diagnosticInvalidUrl'.tr
                            : null,
                        onChanged: (_) {
                          // A completed report always belongs to its tested URL.
                          if (controller.results.isNotEmpty) {
                            controller.network.invalidateContext();
                            controller.notice.value = null;
                          }
                        },
                        onFieldSubmitted: (_) => _run(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'healthScope'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const ValueKey('healthRun'),
                          onPressed:
                              controller.running.value ||
                                  controller.core.preview
                              ? null
                              : _run,
                          icon: const AppIcon(AppIcons.checkList, size: 18),
                          label: Text(
                            (controller.running.value
                                    ? 'diagnosticRunning'
                                    : 'diagnosticRun')
                                .tr,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.error.value case final error?) ...[
                const SizedBox(height: 16),
                AppMessage(message: error.tr, tone: AppMessageTone.error),
              ],
              if (controller.historyError.value case final historyError?) ...[
                const SizedBox(height: 16),
                AppMessage(
                  message: historyError.tr,
                  tone: AppMessageTone.warning,
                ),
              ],
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      controller.summaryKey.tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (controller.results.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'diagnosticProgress'.trParams({
                          'done': '${controller.completed}',
                          'total': '${HealthCheck.values.length}',
                        }),
                      ),
                      if (controller.finishedAt.value != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'healthCounts'.trParams({
                            'failed': '${controller.failures}',
                            'warnings': '${controller.warnings}',
                          }),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'healthCheckedAt'.trParams({
                            'time':
                                '${MaterialLocalizations.of(context).formatShortDate(controller.finishedAt.value!)} ${TimeOfDay.fromDateTime(controller.finishedAt.value!).format(context)}',
                          }),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                    if (controller.running.value) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: controller.completed / HealthCheck.values.length,
                      ),
                    ],
                    if (controller.routingAdvice case final advice?) ...[
                      const SizedBox(height: 12),
                      Text(advice.tr),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final check in HealthCheck.values) ...[
                      if (check != HealthCheck.values.first)
                        const Divider(height: 32),
                      _CheckRow(
                        check: check,
                        result: controller.results[check],
                        onOpen: _open,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _open(HealthAction.logs),
                  icon: const AppIcon(AppIcons.terminal, size: 18),
                  label: Text('healthAction_logs'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.check,
    required this.result,
    required this.onOpen,
  });

  final HealthCheck check;
  final HealthResult? result;
  final ValueChanged<HealthAction> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = result?.status;
    final color = switch (status) {
      HealthStatus.passed => colors.primary,
      HealthStatus.failed => colors.error,
      HealthStatus.warning => colors.secondary,
      _ => colors.onSurfaceVariant,
    };
    return Column(
      key: ValueKey('healthCheck_${check.name}'),
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
              label: status == null
                  ? 'diagnosticNotChecked'.tr
                  : 'healthStatus_${status.name}'.tr,
              color: color,
            ),
          ],
        ),
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(result!.message.trParams(result!.params)),
          if (result!.details.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              result!.details,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (result!.action case final action?)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onOpen(action),
                child: Text('healthAction_${action.name}'.tr),
              ),
            ),
        ],
      ],
    );
  }
}
