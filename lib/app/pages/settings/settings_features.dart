part of 'settings_view.dart';

extension _SettingsFeatures on _SettingsViewState {
  bool get _desktopPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Widget _rows(List<Widget> children) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _hint(String key) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(key.tr, style: Theme.of(context).textTheme.bodySmall),
  );

  Widget _startup(BuildContext context) => Column(
    children: [
      _rows([
        _switch(context, 'launchAtLogin'),
        _switch(context, 'startHidden', subtitle: 'startHiddenHint'),
        _switch(context, 'minimizeToTray'),
        _switch(
          context,
          'rememberWindowSize',
          subtitle: 'rememberWindowSizeHint',
        ),
      ]),
      _hint('settingsStartupHint'),
    ],
  );

  Widget _shortcuts(BuildContext context) {
    final service = Get.isRegistered<DesktopShortcutService>()
        ? Get.find<DesktopShortcutService>()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          _switch(
            context,
            'shortcutsEnabled',
            subtitle: 'shortcutsEnabledHint',
          ),
          for (final key in DesktopShortcutService.keys.skip(1))
            AppSettingsRow(
              title: key.tr,
              subtitle: '${controller.settings.fields[key]}',
              onTap: () async {
                final value = await AppDialogs.prompt(
                  context,
                  title: key.tr,
                  initialValue: controller.settings.fields[key] as String,
                  hint: 'shortcutInputHint'.tr,
                );
                if (value != null && context.mounted) {
                  await _run(
                    context,
                    () => controller.set(
                      key,
                      value.toLowerCase().replaceAll(' ', ''),
                    ),
                  );
                }
              },
            ),
        ]),
        _hint('shortcutInputHint'),
        if (service?.error.value case final error?) _errorPanel(error),
      ],
    );
  }

  Widget _notifications(BuildContext context) {
    final service = Get.isRegistered<ProfileNotificationService>()
        ? Get.find<ProfileNotificationService>()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          _switch(
            context,
            'notifyProfileFailure',
            subtitle: 'notifyProfileFailureHint',
          ),
          if (_desktopPlatform)
            _switch(
              context,
              'nativeNotifications',
              subtitle: 'nativeNotificationsHint',
            ),
        ]),
        _hint('settingsNotificationPrivacy'),
        if (service?.error.value case final error?) _errorPanel(error),
      ],
    );
  }

  Widget _performance(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _rows([
        _integerChoice(context, 'pollIntervalSeconds', [
          1,
          2,
          5,
        ], 'settingsSeconds'),
        _switch(
          context,
          'reduceBackgroundRefresh',
          subtitle: 'reduceBackgroundRefreshHint',
        ),
        if (controller.settings.fields['reduceBackgroundRefresh'] == true)
          _integerChoice(context, 'backgroundIntervalSeconds', [
            5,
            10,
            30,
          ], 'settingsSeconds'),
      ]),
      _hint('settingsPerformanceHint'),
    ],
  );

  Widget _integerChoice(
    BuildContext context,
    String key,
    List<int> options,
    String label,
  ) => AppSettingsRow(
    title: key.tr,
    trailing: AppDropdown<int>(
      value: controller.settings.fields[key] as int,
      items: [
        for (final value in options)
          DropdownMenuItem(
            value: value,
            child: Text(label.trParams({'value': '$value'})),
          ),
      ],
      onChanged: (value) {
        if (value != null) _run(context, () => controller.set(key, value));
      },
    ),
  );

  Widget _kernel(BuildContext context) {
    final core = controller.core;
    final active = _helperCoreActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          AppSettingsRow(
            title: 'settingsCoreStatus'.tr,
            subtitle: core.status.value.name.tr,
            icon: AppIcons.server,
          ),
          AppSettingsRow(
            title: 'coreVersion'.tr,
            subtitle: core.version.value.isEmpty
                ? 'aboutCoreUnavailable'.tr
                : core.version.value,
          ),
          AppSettingsRow(
            title: 'currentProfile'.tr,
            subtitle:
                core.profiles.active?.name ?? 'settingsNoActiveProfile'.tr,
          ),
        ]),
        AppSection(
          title: 'settingsMaintenance'.tr,
          child: Column(
            children: [
              _actionRow(
                'settingsReloadCore',
                AppIcons.refresh,
                core.running ? () => _maintenance(context, core.reload) : null,
              ),
              _actionRow(
                'settingsRestartCore',
                AppIcons.reset,
                core.running
                    ? () => _maintenance(
                        context,
                        core.restart,
                        confirm: 'settingsRestartCoreHint',
                      )
                    : null,
              ),
              if (Platform.isMacOS &&
                  Get.isRegistered<DesktopIntegrationService>())
                _actionRow(
                  'settingsRecoverProxy',
                  AppIcons.shield,
                  !active
                      ? () => _maintenance(
                          context,
                          Get.find<DesktopIntegrationService>()
                              .recoverSystemProxy,
                          confirm: 'settingsRecoverProxyHint',
                        )
                      : null,
                  subtitle: 'settingsRecoverProxyHint',
                ),
              if (Platform.isWindows || Platform.isLinux)
                HelperManagementRows(
                  coreActive: active || _maintenanceBusy,
                  onManage: (uninstall) => _manageHelper(context, uninstall),
                ),
            ],
          ),
        ),
        if (core.error.value case final error?) ...[
          const SizedBox(height: 16),
          _errorPanel(error),
        ],
        _hint('settingsKernelHint'),
      ],
    );
  }

  Widget _actionRow(
    String title,
    IconData icon,
    VoidCallback? action, {
    String? subtitle,
  }) => AppSettingsRow(
    title: title.tr,
    icon: icon,
    subtitle: subtitle?.tr,
    onTap: _maintenanceBusy ? null : action,
    trailing: _maintenanceBusy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : action == null
        ? const AppIcon(AppIcons.pause, size: 16)
        : null,
  );

  Widget _errorPanel(String error) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'settingsLastError'.tr,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 8),
        SelectableText(AppMessage.formatError(error)),
      ],
    ),
  );

  Future<void> _maintenance(
    BuildContext context,
    Future<void> Function() action, {
    String? confirm,
  }) async {
    if (_maintenanceBusy) return;
    if (confirm != null) {
      final accepted = await AppDialogs.confirm(
        context,
        title: 'settingsMaintenance'.tr,
        message: confirm.tr,
      );
      if (!accepted || !context.mounted || _maintenanceBusy) return;
    }
    _setMaintenanceBusy(true);
    try {
      await action();
      if (context.mounted) AppMessage.success(context, 'settingsActionDone'.tr);
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    } finally {
      if (mounted) _setMaintenanceBusy(false);
    }
  }

  Widget _privacy(BuildContext context) {
    final traffic = Get.isRegistered<TrafficStatisticsService>()
        ? Get.find<TrafficStatisticsService>()
        : null;
    final timeline = Get.isRegistered<NetworkTimelineService>()
        ? Get.find<NetworkTimelineService>()
        : null;
    final quality = Get.isRegistered<NodeQualityService>()
        ? Get.find<NodeQualityService>()
        : null;
    final health = Get.isRegistered<HealthHistoryService>()
        ? Get.find<HealthHistoryService>()
        : null;
    // These histories expose revision counters rather than mutable collections.
    traffic?.revision.value;
    quality?.revision.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          _integerChoice(context, 'historyRetentionDays', [
            7,
            14,
            30,
            90,
          ], 'settingsDays'),
          for (final key in [
            'recordTraffic',
            'recordTimeline',
            'recordNodeQuality',
            'recordHealthHistory',
          ])
            _switch(context, key),
        ]),
        _hint('settingsHistoryHint'),
        AppSection(
          title: 'settingsLocalData'.tr,
          child: Column(
            children: [
              if (traffic != null)
                _dataRow(
                  context,
                  'trafficStatistics',
                  traffic.storedBytes,
                  traffic.clear,
                ),
              if (timeline != null)
                _dataRow(
                  context,
                  'networkTimeline',
                  timeline.storedBytes,
                  timeline.clear,
                ),
              if (quality != null)
                _dataRow(
                  context,
                  'nodeQuality',
                  quality.storedBytes,
                  quality.clear,
                ),
              if (health != null)
                _dataRow(
                  context,
                  'healthHistory',
                  health.storedBytes,
                  health.clear,
                ),
              _actionRow(
                'settingsClearLogs',
                AppIcons.delete,
                () => _maintenance(context, () async {
                  controller.core.logs.clear();
                  controller.core.dnsQueries.clear();
                }, confirm: 'settingsClearLogsHint'),
                subtitle: 'settingsClearLogsHint',
              ),
            ],
          ),
        ),
        _hint('settingsLocalDataHint'),
      ],
    );
  }

  Widget _dataRow(
    BuildContext context,
    String title,
    int bytes,
    Future<void> Function() clear,
  ) => AppSettingsRow(
    title: title.tr,
    subtitle: 'settingsDataSize'.trParams({
      'size': bytes < 1024
          ? '$bytes B'
          : '${(bytes / 1024).toStringAsFixed(1)} KB',
    }),
    trailing: IconButton(
      tooltip: 'delete'.tr,
      icon: const AppIcon(AppIcons.delete, size: 18),
      onPressed: _maintenanceBusy
          ? null
          : () => _maintenance(
              context,
              clear,
              confirm: 'settingsClearHistoryHint',
            ),
    ),
  );

  Widget _updates(BuildContext context) {
    if (!Get.isRegistered<UpdateService>()) {
      return _hint('settingsServiceUnavailable');
    }
    final updates = Get.find<UpdateService>();
    final latest = updates.release.value;
    final checked = updates.checkedAt.value;
    final current = updates.currentVersion.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows([
          _switch(
            context,
            'autoCheckUpdates',
            subtitle: 'autoCheckUpdatesHint',
          ),
          AppSettingsRow(
            title: 'settingsInstalledVersion'.tr,
            subtitle: current.isEmpty ? 'loading'.tr : current,
          ),
          AppSettingsRow(
            title: 'settingsLatestVersion'.tr,
            subtitle:
                latest?.version ??
                (updates.noRelease.value
                    ? 'settingsNoReleases'.tr
                    : 'settingsNotChecked'.tr),
          ),
          AppSettingsRow(
            title: 'settingsLastChecked'.tr,
            subtitle: checked == null
                ? 'settingsNotChecked'.tr
                : checked.toLocal().toString().split('.').first,
          ),
          AppSettingsRow(
            title:
                (updates.checking.value
                        ? 'settingsCheckingUpdates'
                        : 'settingsCheckNow')
                    .tr,
            icon: AppIcons.refresh,
            onTap: updates.checking.value ? null : updates.check,
          ),
          if (latest != null)
            AppSettingsRow(
              title:
                  (updates.available
                          ? 'settingsOpenRelease'
                          : 'settingsUpToDate')
                      .tr,
              subtitle: updates.available
                  ? 'settingsManualUpdateHint'.tr
                  : null,
              icon: AppIcons.externalLink,
              onTap: () => _run(context, () async {
                if (!await launchUrl(
                  Uri.parse(latest.url),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw StateError('settingsOpenReleaseFailed'.tr);
                }
              }),
            ),
        ]),
        if (updates.error.value case final error?) ...[
          const SizedBox(height: 16),
          _errorPanel(error),
        ],
        if (latest != null && latest.notes.isNotEmpty)
          AppSection(
            title: 'settingsReleaseNotes'.tr,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(latest.notes),
            ),
          ),
        _hint('settingsUpdatePrivacy'),
      ],
    );
  }
}
