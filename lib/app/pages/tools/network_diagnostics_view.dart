import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../domains/network_diagnostics.dart';
import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';
import 'network_diagnostics_controller.dart';

class UrlDiagnosticsView extends StatefulWidget {
  const UrlDiagnosticsView({super.key, this.initialUrl = ''});

  final String initialUrl;

  @override
  State<UrlDiagnosticsView> createState() => _UrlDiagnosticsViewState();
}

class _UrlDiagnosticsViewState extends State<UrlDiagnosticsView> {
  late final controller = NetworkDiagnosticsController(Get.find<CoreService>());
  late final _url = TextEditingController(text: widget.initialUrl);
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

  Future<void> _run() async {
    if (_form.currentState!.validate()) await controller.diagnoseUrl(_url.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'diagnosticUrl'.tr,
        subtitle: 'diagnosticUrlHelp'.tr,
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiagnosticNotice(controller: controller),
              AppCard(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('diagnosticUrlInput'),
                        controller: _url,
                        enabled: !controller.busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'diagnosticUrlLabel'.tr,
                          hintText: 'https://example.com',
                        ),
                        validator: (value) =>
                            NetworkDiagnosticsController.parseUrl(
                                  value ?? '',
                                ) ==
                                null
                            ? 'diagnosticInvalidUrl'.tr
                            : null,
                        onFieldSubmitted: (_) => _run(),
                      ),
                      const SizedBox(height: 18),
                      _RouteControls(controller: controller),
                      const SizedBox(height: 10),
                      MergeSemantics(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('diagnosticCompareRoutes'.tr),
                          subtitle: Text('diagnosticCompareRoutesHelp'.tr),
                          trailing: AppSwitch(
                            value: controller.compareEnabled.value,
                            onChanged: controller.busy
                                ? null
                                : (value) =>
                                      controller.compareEnabled.value = value,
                          ),
                          onTap: controller.busy
                              ? null
                              : () => controller.compareEnabled.toggle(),
                        ),
                      ),
                      if (controller.compareEnabled.value) ...[
                        const SizedBox(height: 10),
                        AppDropdownFormField<String>(
                          key: ValueKey(
                            'compare:${controller.comparisonProxyName.value}',
                          ),
                          initialValue: controller.comparisonProxyName.value,
                          decoration: InputDecoration(
                            labelText: 'diagnosticComparisonRoute'.tr,
                          ),
                          items: [
                            for (final name in controller.routes.where(
                              (name) => name != controller.proxyName.value,
                            ))
                              DropdownMenuItem(
                                value: name,
                                child: Text(
                                  _routeLabel(name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: controller.busy
                              ? null
                              : (value) =>
                                    controller.selectComparisonRoute(value!),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: controller.busy || !controller.core.running
                              ? null
                              : _run,
                          icon: const AppIcon(AppIcons.play, size: 18),
                          label: Text(
                            (controller.probing.value
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
              if (controller.probing.value) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (controller.urlResults.isEmpty && !controller.probing.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: AppEmpty(
                    icon: AppIcons.globe,
                    title: 'diagnosticUrlEmpty'.tr,
                    message: 'diagnosticUrlEmptyHelp'.tr,
                  ),
                ),
              if (controller.urlResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 640 &&
                              controller.urlResults.length > 1
                          ? 2
                          : 1;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final result in controller.urlResults)
                            SizedBox(
                              width:
                                  (constraints.maxWidth - (columns - 1) * 16) /
                                  columns,
                              child: _UrlResultCard(result: result),
                            ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ServiceDiagnosticsView extends StatefulWidget {
  const ServiceDiagnosticsView({super.key});

  @override
  State<ServiceDiagnosticsView> createState() => _ServiceDiagnosticsViewState();
}

class _ServiceDiagnosticsViewState extends State<ServiceDiagnosticsView> {
  late final controller = NetworkDiagnosticsController(Get.find<CoreService>());

  @override
  void initState() {
    super.initState();
    controller.onInit();
  }

  @override
  void dispose() {
    controller.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'diagnosticServices'.tr,
        subtitle: 'diagnosticServicesHelp'.tr,
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiagnosticNotice(controller: controller),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RouteControls(controller: controller),
                    const SizedBox(height: 14),
                    Text(
                      'diagnosticServiceHelp'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: controller.busy || !controller.core.running
                            ? null
                            : () => controller.checkServices(),
                        icon: const AppIcon(AppIcons.verified, size: 18),
                        label: Text(
                          (controller.checkingServices.value
                                  ? 'diagnosticRunning'
                                  : 'diagnosticCheckAll')
                              .tr,
                        ),
                      ),
                    ),
                    if (controller.checkingServices.value) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value:
                            controller.serviceResults.length /
                            (controller.serviceResults.length +
                                controller.pendingServices.length),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'diagnosticProgress'.trParams({
                          'done': '${controller.serviceResults.length}',
                          'total':
                              '${controller.serviceResults.length + controller.pendingServices.length}',
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              for (final category in [
                'diagnosticGeneral',
                'diagnosticAi',
                'diagnosticMedia',
              ])
                AppSection(
                  title: category.tr,
                  child: Column(
                    children: [
                      for (final service in DiagnosticService.all.where(
                        (item) => item.category == category,
                      ))
                        _ServiceRow(service: service, controller: controller),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RouteControls extends StatelessWidget {
  const _RouteControls({required this.controller});
  final NetworkDiagnosticsController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final route = AppDropdownFormField<String>(
            key: ValueKey(controller.proxyName.value),
            initialValue: controller.proxyName.value,
            decoration: InputDecoration(labelText: 'diagnosticRoute'.tr),
            items: [
              for (final name in controller.routes)
                DropdownMenuItem(
                  value: name,
                  child: Text(
                    _routeLabel(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: controller.busy
                ? null
                : (value) => controller.selectRoute(value!),
          );
          final timeout = AppDropdownFormField<int>(
            initialValue: controller.timeout.value,
            decoration: InputDecoration(labelText: 'diagnosticTimeout'.tr),
            items: [
              for (final millis in [5000, 10000, 20000])
                DropdownMenuItem(
                  value: millis,
                  child: Text(
                    'diagnosticTimeoutSeconds'.trParams({
                      'seconds': '${millis ~/ 1000}',
                    }),
                  ),
                ),
            ],
            onChanged: controller.busy
                ? null
                : (value) => controller.timeout.value = value!,
          );
          return constraints.maxWidth < 500
              ? Column(children: [route, const SizedBox(height: 14), timeout])
              : Row(
                  children: [
                    Expanded(child: route),
                    const SizedBox(width: 16),
                    SizedBox(width: 160, child: timeout),
                  ],
                );
        },
      ),
      const SizedBox(height: 10),
      Text(
        'diagnosticRouteHelp'.tr,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _DiagnosticNotice extends StatelessWidget {
  const _DiagnosticNotice({required this.controller});
  final NetworkDiagnosticsController controller;

  @override
  Widget build(BuildContext context) {
    final message =
        controller.error.value ??
        controller.notice.value?.tr ??
        (controller.core.running ? null : 'diagnosticConnectFirst'.tr);
    return message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppMessage(
              message: message,
              tone: controller.error.value == null
                  ? AppMessageTone.info
                  : AppMessageTone.error,
            ),
          );
  }
}

class _UrlResultCard extends StatelessWidget {
  const _UrlResultCard({required this.result});
  final UrlDiagnosticResult result;

  String get _summary => result.receivedResponse
      ? '${(result.successful ? 'diagnosticResponse' : 'diagnosticHttpError').tr} · HTTP ${result.statusCode}'
      : (result.error == 'timeout' ? 'diagnosticTimedOut' : 'diagnosticFailed')
            .tr;

  @override
  Widget build(BuildContext context) {
    final details = <String, String>{
      'diagnosticRequestedUrl'.tr: result.requestedUrl,
      if (result.url != result.requestedUrl)
        'diagnosticFinalUrl'.tr: result.url,
      if (result.receivedResponse) 'diagnosticLatency'.tr: '${result.delay} ms',
      'diagnosticMatchedRule'.tr: result.proxyName.isNotEmpty
          ? 'diagnosticPinnedRule'.tr
          : (result.matchedRule.isEmpty
                ? 'diagnosticNoRule'.tr
                : result.matchedRule),
      'diagnosticChain'.tr: result.chains.isEmpty
          ? 'diagnosticNoChain'.tr
          : result.chains.reversed.join(' → '),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _routeLabel(result.proxyName),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'featureCopy'.tr,
                onPressed: () => _copy(
                  context,
                  [
                    _routeLabel(result.proxyName),
                    _summary,
                    for (final entry in details.entries)
                      '${entry.key}: ${entry.value}',
                    if (result.message.isNotEmpty) result.message,
                  ].join('\n'),
                ),
                icon: const AppIcon(AppIcons.copy, size: 18),
              ),
            ],
          ),
          Text(
            _summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: result.successful
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          if (result.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(result.message),
          ],
          const SizedBox(height: 12),
          _Details(values: details),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.controller});
  final DiagnosticService service;
  final NetworkDiagnosticsController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.serviceResults[service.id];
    final pending = controller.pendingServices.contains(service.id);
    final statusKey = 'diagnosticStatus_${result?.status}';
    final status = pending
        ? 'diagnosticQueued'.tr
        : result == null
        ? 'diagnosticNotChecked'.tr
        : (statusKey.tr == statusKey
              ? 'diagnosticStatus_unknown'.tr
              : statusKey.tr);
    return ExpansionTile(
      key: ValueKey(service.id),
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              service.name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: 'diagnosticCheckOne'.trParams({'name': service.name}),
            onPressed: controller.busy || !controller.core.running
                ? null
                : () => controller.checkServices(service),
            icon: const AppIcon(AppIcons.refresh, size: 18),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppPill(
              label: status,
              color: result == null || pending
                  ? null
                  : result.status == 'available'
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            if (result != null && !pending) ...[
              if (result.region.isNotEmpty) Text(result.region),
              if (result.delay > 0) Text('${result.delay} ms'),
            ],
          ],
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: result == null
              ? Align(alignment: Alignment.centerLeft, child: Text(status))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (result.message.isNotEmpty) ...[
                      SelectableText(result.message),
                      const SizedBox(height: 10),
                    ],
                    _Details(
                      values: {
                        'diagnosticRoute'.tr: _routeLabel(
                          controller.proxyName.value,
                        ),
                        if (result.region.isNotEmpty)
                          'diagnosticRegion'.tr: result.region,
                        'diagnosticChain'.tr: result.chains.isEmpty
                            ? 'diagnosticNoChain'.tr
                            : result.chains.reversed.join(' → '),
                        'diagnosticCheckedAt'.tr: result.checkedAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first,
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.values});
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in values.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              SelectableText(entry.value),
            ],
          ),
        ),
    ],
  );
}

String _routeLabel(String name) => switch (name) {
  '' => 'diagnosticCurrentRoute'.tr,
  'DIRECT' => 'diagnosticDirect'.tr,
  _ => 'diagnosticPinnedRoute'.trParams({'name': name}),
};

Future<void> _copy(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) AppMessage.success(context, 'featureCopied'.tr);
  } catch (error) {
    if (context.mounted) showAppError(context, error);
  }
}
