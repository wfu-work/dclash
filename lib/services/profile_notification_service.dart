import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:local_notifier/local_notifier.dart';

import '../app/widgets/app_message.dart';
import 'profile_service.dart';
import 'settings_service.dart';

class ProfileNotificationService extends GetxService {
  ProfileNotificationService(
    this.profiles,
    this.settings, {
    this.showWindow,
    this.deliver,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final ProfileService profiles;
  final SettingsService settings;
  final Future<void> Function()? showWindow;
  final Future<void> Function(String, String)? deliver;
  final DateTime Function() _clock;
  final _lastNotified = <String, DateTime>{};
  final error = RxnString();
  Worker? _worker;
  bool get desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  final _notifications = <LocalNotification>{};
  void initialize() {
    _worker = ever(profiles.updateFailure, (failure) {
      if (failure != null) unawaited(notifyFailure(failure));
    });
  }

  Future<void> notifyFailure(ProfileUpdateFailure failure) async {
    if (settings.fields['notifyProfileFailure'] != true) return;
    final now = _clock(), previous = _lastNotified[failure.id];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 30)) {
      return;
    }
    _lastNotified.removeWhere(
      (_, at) => now.difference(at) >= const Duration(minutes: 30),
    );
    _lastNotified[failure.id] = now;
    final title = 'profileUpdateFailedTitle'.tr;
    // No subscription URL or server response goes into an OS notification.
    final name = failure.name
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '…')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    final body = 'profileUpdateFailedBody'.trParams({
      'name': name.length > 80 ? '${name.substring(0, 79)}…' : name,
    });
    final context = Get.context;
    if (context != null && context.mounted) AppMessage.error(context, body);
    if (settings.fields['nativeNotifications'] == true &&
        (desktop || deliver != null)) {
      try {
        final delivery = deliver;
        if (delivery != null) {
          await delivery(title, body);
        } else {
          await sendNative(title, body);
        }
        error.value = null;
      } on Object catch (failure) {
        error.value = failure.toString();
      }
    }
  }

  Future<void> sendNative(String title, String body) async {
    await localNotifier.setup(
      appName: 'dclash',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    final notification = LocalNotification(title: title, body: body);
    _notifications.add(notification);
    notification.onClick = () {
      unawaited(showWindow?.call().catchError((Object _) {}) ?? Future.value());
    };
    notification.onClose = (_) {
      if (!_notifications.remove(notification)) return;
      unawaited(notification.destroy().catchError((Object _) {}));
    };
    try {
      await notification.show();
    } on Object {
      _notifications.remove(notification);
      await notification.destroy().catchError((Object _) {});
      rethrow;
    }
  }

  @override
  void onClose() {
    _worker?.dispose();
    final notifications = _notifications.toList();
    _notifications.clear();
    for (final notification in notifications) {
      unawaited(notification.destroy().catchError((Object _) {}));
    }
    super.onClose();
  }
}
