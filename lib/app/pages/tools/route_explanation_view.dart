import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/route_explanation.dart';
import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';
import 'network_diagnostics_controller.dart';
import 'network_diagnostics_view.dart';
import 'route_explanation_controller.dart';

class RouteExplanationView extends StatefulWidget {
  const RouteExplanationView({super.key, this.core});
  final CoreService? core;
  @override
  State<RouteExplanationView> createState() => _RouteExplanationViewState();
}

class _RouteExplanationViewState extends State<RouteExplanationView> {
  late final controller = RouteExplanationController(
    widget.core ?? Get.find<CoreService>(),
  );
  late final url = TextEditingController(text: controller.defaultUrl);
  final form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    controller.onInit();
  }

  @override
  void dispose() {
    controller.onClose();
    url.dispose();
    super.dispose();
  }

  void _explain() {
    if (form.currentState!.validate()) controller.explain(url.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 820,
        title: 'routeExplain'.tr,
        subtitle: 'routeExplainHelp'.tr,
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('routeExplainUrl'),
                        controller: url,
                        enabled: !controller.loading.value,
                        keyboardType: TextInputType.url,
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
                        onFieldSubmitted: (_) => _explain(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'routeExplainScope'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const ValueKey('routeExplainRun'),
                          onPressed: controller.loading.value ? null : _explain,
                          icon: controller.loading.value
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const AppIcon(AppIcons.route, size: 17),
                          label: Text(
                            controller.loading.value
                                ? 'routeExplainLoading'.tr
                                : 'routeExplainRun'.tr,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.notice.value case final notice?) ...[
                const SizedBox(height: 16),
                AppMessage(message: notice.tr, tone: AppMessageTone.warning),
              ],
              if (controller.error.value case final error?) ...[
                const SizedBox(height: 16),
                AppMessage(message: error.tr, tone: AppMessageTone.error),
              ],
              const SizedBox(height: 16),
              if (controller.result.value case final result?)
                _RouteResult(
                  result: result,
                  onDiagnose: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          UrlDiagnosticsView(initialUrl: result.url),
                    ),
                  ),
                )
              else
                AppEmpty(
                  icon: AppIcons.route,
                  title: 'routeExplainEmpty'.tr,
                  message: 'routeExplainEmptyHelp'.tr,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RouteResult extends StatelessWidget {
  const _RouteResult({required this.result, required this.onDiagnose});
  final RouteExplanation result;
  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (
        'routeExplainRule'.tr,
        result.matchedRule.isEmpty
            ? 'routeExplainNoRule'.tr
            : result.matchedRule,
      ),
      ('routeExplainGroup'.tr, result.route),
      (
        'routeExplainSelected'.tr,
        result.selected.isEmpty ? result.route : result.selected,
      ),
      ('routeExplainFinal'.tr, result.finalOutbound),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppMessage(
            message: result.exact
                ? 'routeExplainExact'.tr
                : result.needsDns
                ? 'routeExplainNeedsDns'.tr
                : 'routeExplainEstimated'.tr,
            tone: result.exact
                ? AppMessageTone.success
                : AppMessageTone.warning,
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 28),
            Text(rows[index].$1, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            SelectableText(rows[index].$2),
          ],
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('routeExplainDiagnose'),
              onPressed: onDiagnose,
              icon: const AppIcon(AppIcons.globe, size: 17),
              label: Text('routeExplainRunDiagnostics'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
