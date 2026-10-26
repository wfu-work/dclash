import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/core_status.dart';
import '../../../services/backup_service.dart';
import '../../widgets/app_widgets.dart';
import 'settings_dependencies.dart';

class BackupView extends StatefulWidget {
  const BackupView({super.key, this.embedded = false, this.dependencies});

  final bool embedded;
  final SettingsDependencies? dependencies;

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  bool _busy = false;
  late final _dependencies =
      widget.dependencies ?? SettingsDependencies.fromGetX();
  late final _settings = _dependencies.settings;
  late final _backup = _dependencies.backup ?? Get.find<BackupService>();

  Future<void> _run(
    Future<bool> Function() operation,
    String message, {
    bool restore = false,
  }) async {
    if (_busy) return;
    try {
      setState(() => _busy = true);
      final core = _dependencies.core;
      bool completed;
      if (restore) {
        if (![
          CoreStatus.stopped,
          CoreStatus.failed,
        ].contains(core.status.value)) {
          throw StateError('stopBeforeRestore'.tr);
        }
        completed = await core.withStoppedCore(() async {
          final confirmed = await AppDialogs.confirm(
            context,
            title: 'restoreTitle'.tr,
            message: 'restoreWarning'.tr,
          );
          if (!confirmed || !mounted) return false;
          return operation();
        });
      } else {
        completed = await operation();
      }
      if (completed && mounted) {
        AppMessage.success(context, message.tr);
      }
    } on Object catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String key, {bool secret = false}) async {
    try {
      final current = secret
          ? await _settings.readSecret(key)
          : _settings.fields[key] as String;
      if (!mounted) return;
      final next = await AppDialogs.prompt(
        context,
        title: key.tr,
        initialValue: current,
        obscureText: secret,
      );
      if (next == null) return;
      if (secret) {
        await _settings.writeSecret(key, next);
      } else {
        await _settings.set(key, next.trim());
      }
    } on Object catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPage(
      maxContentWidth: 820,
      title: 'backup'.tr,
      automaticallyImplyLeading: !widget.embedded,
      child: IgnorePointer(
        ignoring: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            AppSection(
              title: 'backup'.tr,
              child: Column(
                children: [
                  AppSettingsRow(
                    title: 'exportBackup'.tr,
                    icon: AppIcons.download,
                    onTap: () => _run(
                      () async => await _backup.exportFile() != null,
                      'backupDone',
                    ),
                  ),
                  AppSettingsRow(
                    title: 'importBackup'.tr,
                    icon: AppIcons.reset,
                    onTap: () =>
                        _run(_backup.importFile, 'restoreDone', restore: true),
                  ),
                ],
              ),
            ),
            AppSection(
              title: 'webdav'.tr,
              child: Obx(
                () => Column(
                  children: [
                    AppSettingsRow(
                      title: 'webdavUrl'.tr,
                      subtitle: _settings.fields['webdavUrl'] as String,
                      onTap: () => _edit('webdavUrl'),
                    ),
                    AppSettingsRow(
                      title: 'webdavUser'.tr,
                      subtitle: _settings.fields['webdavUser'] as String,
                      onTap: () => _edit('webdavUser'),
                    ),
                    AppSettingsRow(
                      title: 'webdavPassword'.tr,
                      trailing: const AppIcon(AppIcons.key),
                      onTap: () => _edit('webdavPassword', secret: true),
                    ),
                    AppSettingsRow(
                      title: 'uploadBackup'.tr,
                      icon: AppIcons.cloudUpload,
                      onTap: () => _run(() async {
                        await _backup.uploadWebDav();
                        return true;
                      }, 'backupDone'),
                    ),
                    AppSettingsRow(
                      title: 'downloadBackup'.tr,
                      icon: AppIcons.cloudDownload,
                      onTap: () => _run(
                        () async {
                          await _backup.downloadWebDav();
                          return true;
                        },
                        'restoreDone',
                        restore: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.embedded ? page : Scaffold(body: SafeArea(child: page));
  }
}
