import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../domains/core_status.dart';
import '../../../services/config_builder.dart';
import '../../../services/desktop_integration_service.dart';
import '../../../services/desktop_shortcut_service.dart';
import '../../../services/health_history_service.dart';
import '../../../services/network_timeline_service.dart';
import '../../../services/node_quality_service.dart';
import '../../../services/profile_notification_service.dart';
import '../../../services/traffic_statistics_service.dart';
import '../../../services/update_service.dart';
import '../dashboard/dashboard_layout_view.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/app_workspace_surface.dart';
import 'access/installed_apps_controller.dart';
import 'access/installed_apps_view.dart';
import 'about_view.dart';
import 'appearance_view.dart';
import 'backup_view.dart';
import 'config_editor/config_schema.dart';
import 'config_editor_view.dart';
import 'helper_management_rows.dart';
import 'licenses_view.dart';
import 'settings_controller.dart';
import 'settings_navigation.dart';
import 'settings_sidebar.dart';
import 'structured_config_editor_view.dart';

part 'settings_features.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, this.section});
  final String? section;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsSection _selected;
  bool _maintenanceBusy = false;

  void _setMaintenanceBusy(bool value) =>
      setState(() => _maintenanceBusy = value);

  SettingsController get controller => Get.find<SettingsController>();

  @override
  void initState() {
    super.initState();
    _selected = SettingsNavigation.resolve(widget.section);
  }

  @override
  void didUpdateWidget(SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _selected = SettingsNavigation.resolve(widget.section);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final desktop =
          bounds.maxWidth >= 900 && !Platform.isAndroid && !Platform.isIOS;
      return desktop ? _desktop(context) : _mobile(context);
    },
  );

  Widget _mobile(BuildContext context) {
    if (widget.section != null) return _content(context, _selected);
    return Scaffold(
      body: SafeArea(
        child: AppPage(
          maxContentWidth: 820,
          title: 'settings'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in SettingsNavigation.visibleGroups)
                AppSection(
                  title: group.titleKey.tr,
                  child: Column(
                    children: [
                      for (final section in group.sections)
                        AppSettingsRow(
                          key: ValueKey('settingsMenu:${section.key}'),
                          title: section.titleKey.tr,
                          icon: section.icon,
                          onTap: () => _push(
                            context,
                            SettingsView(section: section.key),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    final surfaces = Theme.of(context).extension<AppSurfaces>()!;
    return Scaffold(
      backgroundColor: surfaces.window,
      body: Row(
        children: [
          SizedBox(
            width: 236,
            child: SafeArea(
              top: true,
              bottom: false,
              child: SettingsSidebar(
                selected: _selected,
                onSelected: (section) => setState(() => _selected = section),
                onBack: () => Navigator.maybePop(context),
              ),
            ),
          ),
          Expanded(
            child: AppWorkspaceSurface(
              desktop: true,
              child: _content(context, _selected, embedded: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    SettingsSection section, {
    bool embedded = false,
  }) {
    switch (section) {
      case SettingsSection.appearance:
        return AppearanceView(embedded: embedded);
      case SettingsSection.dashboard:
        return DashboardLayoutView(embedded: embedded);
      case SettingsSection.backup:
        return BackupView(embedded: embedded);
      case SettingsSection.about:
        return AboutView(embedded: embedded);
      case SettingsSection.licenses:
        return LicensesView(embedded: embedded);
      default:
        break;
    }
    final page = AppPage(
      maxContentWidth: 860,
      title: section.titleKey.tr,
      automaticallyImplyLeading: !embedded,
      child: Obx(() {
        // Also observes pending writes when a service is unavailable in preview.
        final saving = controller.saving.value;
        return AbsorbPointer(
          absorbing: saving,
          child: switch (section) {
            SettingsSection.startup => _startup(context),
            SettingsSection.shortcuts => _shortcuts(context),
            SettingsSection.notifications => _notifications(context),
            SettingsSection.general => _general(context, showTitle: false),
            SettingsSection.network => _network(context, showTitle: false),
            SettingsSection.advanced => _advanced(context, showTitle: false),
            SettingsSection.access => _access(context, showTitle: false),
            SettingsSection.kernel => _kernel(context),
            SettingsSection.privacy => _privacy(context),
            SettingsSection.performance => _performance(context),
            SettingsSection.updates => _updates(context),
            _ => const SizedBox.shrink(),
          },
        );
      }),
    );
    return embedded ? page : Scaffold(body: SafeArea(child: page));
  }

  Widget _section(
    String title, {
    required Widget child,
    required bool showTitle,
  }) => showTitle
      ? AppSection(title: title, child: child)
      : AppCard(padding: EdgeInsets.zero, child: child);

  Widget _general(BuildContext context, {bool showTitle = true}) => _section(
    'general'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
        _input(context, 'mixedPort', number: true),
        if (!Platform.isAndroid && !Platform.isIOS)
          _switch(context, 'systemProxy'),
        _switch(context, 'allowLan'),
        AppSettingsRow(
          title: 'bypassDomains'.tr,
          subtitle: (controller.settings.fields['bypassDomains'] as List).join(
            ', ',
          ),
          onTap: () => _editList(context, 'bypassDomains', 'bypassHint'),
        ),
        _input(context, 'testUrl'),
        _input(context, 'testTimeout', number: true),
      ],
    ),
  );

  Widget _network(BuildContext context, {bool showTitle = true}) => _section(
    'network'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
        _switch(context, 'tunEnabled', title: 'tun'),
        _switch(context, 'ipv6'),
        _choice(context, 'stack', [
          'mixed',
          'system',
          'gvisor',
        ], title: 'tunStack'),
        _yaml(
          context,
          'dns',
          'dnsOverride',
          'enable: true\nenhanced-mode: fake-ip\nnameserver:\n  - https://dns.alidns.com/dns-query',
        ),
        _yaml(
          context,
          'tun',
          'tunOverride',
          'mtu: 9000\nstrict-route: true\ndns-hijack:\n  - any:53',
        ),
      ],
    ),
  );

  Widget _advanced(BuildContext context, {bool showTitle = true}) => _section(
    'advanced'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
        _choice(context, 'logLevel', [
          'silent',
          'error',
          'warning',
          'info',
          'debug',
        ]),
        _switch(context, 'controllerEnabled', subtitle: 'controllerHint'),
        if (controller.settings.fields['controllerEnabled'] == true) ...[
          _input(context, 'controllerPort', number: true),
          AppSettingsRow(
            title: 'controllerAccess'.tr,
            icon: AppIcons.key,
            onTap: () => _controllerAccess(context),
          ),
        ],
        _switch(context, 'unifiedDelay'),
        _switch(context, 'tcpConcurrent'),
        _yaml(
          context,
          'sniffer',
          'snifferOverride',
          'enable: true\nsniff:\n  TLS:\n    ports: [443]\n  HTTP:\n    ports: [80, 8080-8880]',
        ),
        _yaml(
          context,
          'ntp',
          'ntpOverride',
          'enable: true\nserver: time.apple.com\nport: 123\ninterval: 30\nwrite-to-system: false',
        ),
        _yaml(
          context,
          'addedRules',
          'addedRules',
          '- DOMAIN-SUFFIX,example.com,DIRECT\n- IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
        ),
        _yaml(
          context,
          'hosts',
          'hosts',
          "example.com: 127.0.0.1\n'*.example.org': 192.168.1.1",
        ),
      ],
    ),
  );

  Widget _access(BuildContext context, {bool showTitle = true}) => _section(
    'accessControl'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
        _switch(context, 'accessControlEnabled'),
        _choice(context, 'accessControlMode', [
          'rejectSelected',
          'acceptSelected',
        ]),
        AppSettingsRow(
          title: 'installedApps'.tr,
          icon: AppIcons.apps,
          subtitle: 'appsSelectedCount'.trParams({
            'count':
                '${(controller.settings.fields['accessControlPackages'] as List).length}',
          }),
          onTap: () => Navigator.of(context).push<void>(
            GetPageRoute<void>(
              page: () => const InstalledAppsView(),
              binding: BindingsBuilder(() {
                Get.put(
                  InstalledAppsController(
                    selected:
                        (controller.settings.fields['accessControlPackages']
                                as List)
                            .cast<String>(),
                    persist: (packages) =>
                        controller.set('accessControlPackages', packages),
                  ),
                );
              }),
            ),
          ),
        ),
        AppSettingsRow(
          title: 'appPackages'.tr,
          subtitle:
              '${(controller.settings.fields['accessControlPackages'] as List).length}',
          onTap: () =>
              _editList(context, 'accessControlPackages', 'appPackagesHint'),
        ),
        _switch(context, 'allowBypass'),
      ],
    ),
  );

  Widget _switch(
    BuildContext context,
    String key, {
    String? title,
    String? subtitle,
  }) => AppSettingsRow(
    title: (title ?? key).tr,
    subtitle: subtitle?.tr,
    trailing: AppSwitch(
      value: controller.settings.fields[key] == true,
      onChanged: (value) => _run(context, () => controller.set(key, value)),
    ),
  );

  Widget _input(BuildContext context, String key, {bool number = false}) =>
      AppSettingsRow(
        title: key.tr,
        subtitle: '${controller.settings.fields[key]}',
        onTap: () async {
          final next = await AppDialogs.prompt(
            context,
            title: key.tr,
            initialValue: '${controller.settings.fields[key]}',
          );
          if (next == null || !context.mounted) return;
          await _run(context, () async {
            final dynamic value = number ? int.parse(next.trim()) : next.trim();
            if (key == 'testUrl' &&
                !(Uri.tryParse(value as String)?.isScheme('https') ?? false)) {
              throw const FormatException('Use an HTTPS test URL.');
            }
            await controller.set(key, value);
          });
        },
      );

  Widget _choice(
    BuildContext context,
    String key,
    List<String> options, {
    String? title,
  }) => AppSettingsRow(
    title: (title ?? key).tr,
    trailing: AppDropdown<String>(
      value: controller.settings.fields[key] as String,
      items: [
        for (final value in options)
          DropdownMenuItem(value: value, child: Text(value.tr)),
      ],
      onChanged: (value) {
        if (value != null) _run(context, () => controller.set(key, value));
      },
    ),
  );

  Widget _yaml(
    BuildContext context,
    String title,
    String key,
    String example,
  ) => AppSettingsRow(
    title: title.tr,
    subtitle:
        ((controller.settings.fields[key] as String).isEmpty
                ? 'defaultValue'
                : 'configured')
            .tr,
    onTap: () => _push(
      context,
      ConfigSchemas.supported.contains(key)
          ? StructuredConfigEditorView(
              setting: key,
              title: title,
              example: example,
            )
          : ConfigEditorView(setting: key, title: title, example: example),
    ),
  );

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _editList(BuildContext context, String key, String hint) async {
    final next = await AppDialogs.prompt(
      context,
      title: key.tr,
      initialValue: (controller.settings.fields[key] as List).join('\n'),
      multiline: true,
      hint: hint.tr,
    );
    if (next == null || !context.mounted) return;
    await _run(
      context,
      () => controller.set(
        key,
        next
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _controllerAccess(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('controllerAccess'.tr),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'http://127.0.0.1:${controller.settings.fields['controllerPort']}',
              ),
              const SizedBox(height: 16),
              Text(
                'controllerSecretHint'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                ConfigBuilder.sessionSecret,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _run(dialogContext, () async {
              await Clipboard.setData(
                ClipboardData(text: ConfigBuilder.sessionSecret),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }),
            icon: const AppIcon(AppIcons.copy),
            label: Text('copy'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  bool get _helperCoreActive => switch (controller.core.status.value) {
    CoreStatus.starting || CoreStatus.running || CoreStatus.stopping => true,
    CoreStatus.stopped || CoreStatus.failed => false,
  };

  Future<void> _manageHelper(BuildContext context, bool uninstall) => _run(
    context,
    () async {
      if (_helperCoreActive) throw StateError('helperStopFirst'.tr);
      final confirmed = await AppDialogs.confirm(
        context,
        title: (uninstall ? 'helperUninstall' : 'helperInstall').tr,
        message:
            (uninstall ? 'helperUninstallConfirm' : 'helperInstallConfirm').tr,
      );
      if (!confirmed || !context.mounted) return;
      if (_helperCoreActive) throw StateError('helperStopFirst'.tr);
      await controller.core.invoke(
        uninstall ? 'uninstallHelper' : 'installHelper',
      );
      if (!context.mounted) return;
      AppMessage.success(
        context,
        (uninstall ? 'helperUninstalled' : 'helperInstalled').tr,
      );
    },
  );
}
