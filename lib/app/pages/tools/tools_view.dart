import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';
import '../connections/connections_view.dart';
import '../connections/feed_view.dart';
import '../logs/logs_view.dart';
import '../settings/providers_view.dart';
import '../settings/scripts/script_library_view.dart';
import 'resource_library_view.dart';

class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    maxContentWidth: 820,
    title: 'tools'.tr,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSection(
          title: 'diagnostics'.tr,
          child: Column(
            children: [
              _row(
                context,
                'connections',
                AppIcons.connections,
                const _FeatureRoute(
                  title: 'connections',
                  child: ConnectionsView(),
                ),
              ),
              _row(
                context,
                'requests',
                AppIcons.swap,
                const _FeatureRoute(
                  title: 'requests',
                  child: FeedView(dns: false),
                ),
              ),
              _row(
                context,
                'dnsQueries',
                AppIcons.server,
                const _FeatureRoute(
                  title: 'dnsQueries',
                  child: FeedView(dns: true),
                ),
              ),
              _row(
                context,
                'logs',
                AppIcons.terminal,
                const _FeatureRoute(title: 'logs', child: LogsView()),
              ),
            ],
          ),
        ),
        AppSection(
          title: 'resources'.tr,
          child: Column(
            children: [
              _row(
                context,
                'resourceLibrary',
                AppIcons.layers,
                const ResourceLibraryView(),
              ),
              _row(context, 'providers', AppIcons.cloud, const ProvidersView()),
              _row(
                context,
                'scriptLibrary',
                AppIcons.code,
                const ScriptLibraryView(),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, String title, IconData icon, Widget page) =>
      AppSettingsRow(
        title: title.tr,
        icon: icon,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => page)),
      );
}

class _FeatureRoute extends StatelessWidget {
  const _FeatureRoute({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
              child: IconButton(
                tooltip: 'back'.tr,
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(AppIcons.arrowLeft),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
