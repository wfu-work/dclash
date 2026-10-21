import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';

class ProvidersView extends StatelessWidget {
  const ProvidersView({super.key});

  @override
  Widget build(BuildContext context) {
    final core = Get.find<CoreService>();
    return Scaffold(
      body: SafeArea(
        child: AppPage(
          maxContentWidth: 820,
          title: 'providers'.tr,
          actions: [
            IconButton(
              tooltip: 'back'.tr,
              onPressed: () => Navigator.pop(context),
              icon: const AppIcon(AppIcons.close),
            ),
          ],
          child: Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSection(
                  title: 'providers'.tr,
                  child: core.providers.isEmpty
                      ? AppEmpty(
                          title: 'providers'.tr,
                          message: 'emptyProviders'.tr,
                        )
                      : Column(
                          children: [
                            for (final item in core.providers)
                              _ProviderRow(item: item, core: core),
                          ],
                        ),
                ),
                AppSection(
                  title: 'updateGeo'.tr,
                  child: Column(
                    children: [
                      for (final name in ['mmdb', 'geoip', 'geosite', 'asn'])
                        _GeoRow(name: name, core: core),
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
}

class _ProviderRow extends StatefulWidget {
  const _ProviderRow({required this.item, required this.core});
  final Map<String, dynamic> item;
  final CoreService core;
  @override
  State<_ProviderRow> createState() => _ProviderRowState();
}

class _ProviderRowState extends State<_ProviderRow> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => AppSettingsRow(
    title: '${widget.item['name']}',
    subtitle:
        '${widget.item['vehicle-type'] ?? widget.item['type']} · ${widget.item['count'] ?? 0}',
    trailing: IconButton(
      tooltip: 'update'.tr,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.core.updateProvider('${widget.item['name']}');
              } on Object catch (error) {
                if (context.mounted) showAppError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const AppIcon(AppIcons.refresh),
    ),
  );
}

class _GeoRow extends StatefulWidget {
  const _GeoRow({required this.name, required this.core});
  final String name;
  final CoreService core;
  @override
  State<_GeoRow> createState() => _GeoRowState();
}

class _GeoRowState extends State<_GeoRow> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => AppSettingsRow(
    title: widget.name.toUpperCase(),
    icon: AppIcons.globe,
    trailing: IconButton(
      tooltip: 'update'.tr,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.core.updateGeo(widget.name);
              } on Object catch (error) {
                if (context.mounted) showAppError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const AppIcon(AppIcons.download),
    ),
  );
}
