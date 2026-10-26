import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../configs/app_services_bridge.dart';
import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';

class AboutView extends StatefulWidget {
  const AboutView({super.key, this.embedded = false, this.core});

  final bool embedded;
  final CoreService? core;

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  late final _packageInfo = PackageInfo.fromPlatform();

  String get _platform => switch (Platform.operatingSystem) {
    'macos' => 'macOS',
    'ios' => 'iOS',
    'android' => 'Android',
    'windows' => 'Windows',
    'linux' => 'Linux',
    final name => name,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final brand = 'brandName'.tr == 'appName'.tr
        ? 'appName'.tr
        : '${'brandName'.tr} · ${'appName'.tr}';
    final page = AppPage(
      title: 'about'.tr,
      maxContentWidth: 820,
      automaticallyImplyLeading: !widget.embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      colors.primary.withValues(alpha: .07),
                      colors.surfaceContainerHigh,
                    ),
                    colors.surfaceContainerHigh,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  children: [
                    const AppLogo(size: 88),
                    const SizedBox(height: 18),
                    Text(
                      brand,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'appTagline'.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        'aboutDescription'.tr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              final unavailable =
                  snapshot.connectionState == ConnectionState.done
                  ? 'aboutInfoUnavailable'.tr
                  : 'loading'.tr;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('aboutAppInfo'.tr, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 18),
                    Obx(() {
                      final coreVersion =
                          (widget.core ?? coreFromGetX()).version.value;
                      final details = <(String, String)>[
                        ('version'.tr, info?.version ?? unavailable),
                        (
                          'aboutBuildNumber'.tr,
                          info == null
                              ? unavailable
                              : info.buildNumber.isEmpty
                              ? 'aboutInfoUnavailable'.tr
                              : info.buildNumber,
                        ),
                        (
                          'coreVersion'.tr,
                          coreVersion.isEmpty
                              ? 'aboutCoreUnavailable'.tr
                              : coreVersion,
                        ),
                        ('aboutPlatform'.tr, _platform),
                      ];
                      return _Details(details: details);
                    }),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'aboutAcknowledgements'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
    return widget.embedded ? page : Scaffold(body: SafeArea(child: page));
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.details});

  final List<(String, String)> details;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final theme = Theme.of(context);
      final columns =
          box.maxWidth >= 500 &&
              MediaQuery.textScalerOf(context).scale(14) <= 19
          ? 2
          : 1;
      final width = (box.maxWidth - 24 * (columns - 1)) / columns;
      return Wrap(
        spacing: 24,
        runSpacing: 22,
        children: [
          for (final (label, value) in details)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 6),
                  SelectableText(value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      );
    },
  );
}
