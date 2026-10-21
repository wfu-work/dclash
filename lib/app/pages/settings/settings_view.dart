import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../configs/theme/app_theme.dart';
import '../../../domains/core_status.dart';
import '../../../services/config_builder.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/app_workspace_surface.dart';
import 'access/installed_apps_controller.dart';
import 'access/installed_apps_view.dart';
import 'appearance_view.dart';
import 'backup_view.dart';
import 'config_editor/config_schema.dart';
import 'config_editor_view.dart';
import 'helper_management_rows.dart';
import 'settings_controller.dart';
import 'settings_navigation.dart';
import 'settings_sidebar.dart';
import 'structured_config_editor_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, this.section});
  final String? section;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsSection _selected;

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
    if (widget.section == 'appearance') return const AppearanceView();
    if (widget.section == 'backup') return const BackupView();
    return Scaffold(
      body: SafeArea(
        child: AppPage(
          maxContentWidth: 820,
          title: (widget.section ?? 'settings').tr,
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
                if (widget.section == null || widget.section == 'general')
                  _general(context),
                if (widget.section == null || widget.section == 'network')
                  _network(context),
                if (Platform.isAndroid &&
                    (widget.section == null || widget.section == 'network'))
                  _access(context),
                if (widget.section == null || widget.section == 'advanced')
                  _advanced(context),
                if (widget.section == null) _appPreferences(context),
              ],
            ),
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
              child: Obx(() => _desktopContent(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopContent(BuildContext context) => switch (_selected) {
    SettingsSection.general => _desktopPage(
      context,
      _selected,
      _general(context, showTitle: false),
    ),
    SettingsSection.network => _desktopPage(
      context,
      _selected,
      _network(context, showTitle: false),
    ),
    SettingsSection.access => _desktopPage(
      context,
      _selected,
      _access(context, showTitle: false),
    ),
    SettingsSection.advanced => _desktopPage(
      context,
      _selected,
      _advanced(context, showTitle: false),
    ),
    SettingsSection.appearance => const AppearanceView(embedded: true),
    SettingsSection.backup => const BackupView(embedded: true),
    SettingsSection.about => _aboutPage(context),
  };

  Widget _desktopPage(
    BuildContext context,
    SettingsSection section,
    Widget content,
  ) =>
      AppPage(maxContentWidth: 860, title: section.titleKey.tr, child: content);

  Widget _appPreferences(BuildContext context) => AppSection(
    title: 'appPreferences'.tr,
    child: Column(
      children: [
        _route(context, 'appearance', AppIcons.palette, const AppearanceView()),
        _route(context, 'backup', AppIcons.cloudSync, const BackupView()),
        AppSettingsRow(
          title: 'about'.tr,
          icon: AppIcons.info,
          onTap: () => showAbout(context),
        ),
      ],
    ),
  );

  Widget _aboutPage(BuildContext context) => _desktopPage(
    context,
    SettingsSection.about,
    AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Text(
              'aboutDescription'.tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const Divider(height: 1),
          AppSettingsRow(title: 'version'.tr, subtitle: '0.1.0'),
          AppSettingsRow(
            title: 'sourceCode'.tr,
            icon: AppIcons.externalLink,
            onTap: () async {
              await launchUrl(
                Uri.parse('https://github.com/chen08209/FlClash'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          AppSettingsRow(
            title: 'licenses'.tr,
            icon: AppIcons.info,
            onTap: () => showAbout(context),
          ),
        ],
      ),
    ),
  );

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
        _choice(context, 'logLevel', [
          'silent',
          'error',
          'warning',
          'info',
          'debug',
        ]),
        _input(context, 'testUrl'),
        _input(context, 'testTimeout', number: true),
        _switch(context, 'autoStart'),
        if (!Platform.isAndroid) _switch(context, 'launchAtLogin'),
        if (!Platform.isAndroid) _switch(context, 'minimizeToTray'),
      ],
    ),
  );

  Widget _network(BuildContext context, {bool showTitle = true}) => _section(
    'network'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
        _switch(context, 'systemProxy'),
        _switch(context, 'tunEnabled', title: 'tun'),
        _switch(context, 'allowLan'),
        _switch(context, 'ipv6'),
        _choice(context, 'stack', [
          'mixed',
          'system',
          'gvisor',
        ], title: 'tunStack'),
        AppSettingsRow(
          title: 'bypassDomains'.tr,
          subtitle: (controller.settings.fields['bypassDomains'] as List).join(
            ', ',
          ),
          onTap: () => _editList(context, 'bypassDomains', 'bypassHint'),
        ),
        _switch(context, 'controllerEnabled', subtitle: 'controllerHint'),
        if (controller.settings.fields['controllerEnabled'] == true) ...[
          _input(context, 'controllerPort', number: true),
          AppSettingsRow(
            title: 'controllerAccess'.tr,
            icon: AppIcons.key,
            onTap: () => _controllerAccess(context),
          ),
        ],
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
        if (Platform.isWindows || Platform.isLinux)
          HelperManagementRows(
            coreActive: _helperCoreActive,
            onManage: (uninstall) => _manageHelper(context, uninstall),
          ),
      ],
    ),
  );

  Widget _advanced(BuildContext context, {bool showTitle = true}) => _section(
    'advanced'.tr,
    showTitle: showTitle,
    child: Column(
      children: [
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

  Widget _route(
    BuildContext context,
    String title,
    IconData icon,
    Widget page,
  ) => AppSettingsRow(
    title: title.tr,
    icon: icon,
    onTap: () => _push(context, page),
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

  Future<void> _manageHelper(
    BuildContext context,
    bool uninstall,
  ) => _run(context, () async {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((uninstall ? 'helperUninstalled' : 'helperInstalled').tr),
      ),
    );
  });

  static void showAbout(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: 'dclash',
    applicationVersion: '0.1.0',
    applicationIcon: const AppLogo(size: 48),
    applicationLegalese: 'GPL-3.0 · Based on FlClash & mihomo',
    children: [
      const SizedBox(height: 16),
      Text('aboutDescription'.tr),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () async {
          await launchUrl(
            Uri.parse('https://github.com/chen08209/FlClash'),
            mode: LaunchMode.externalApplication,
          );
        },
        icon: const AppIcon(AppIcons.externalLink),
        label: Text('sourceCode'.tr),
      ),
    ],
  );
}
