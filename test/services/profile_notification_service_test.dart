import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/services/profile_notification_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsService settings;
  late ProfileService profiles;
  late DateTime now;
  late List<String> messages;
  late ProfileNotificationService service;
  setUp(() async {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    profiles = ProfileService();
    now = DateTime(2026, 10, 24);
    messages = [];
    service = ProfileNotificationService(
      profiles,
      settings,
      clock: () => now,
      deliver: (title, body) async {
        messages.add('$title: $body');
      },
    );
  });
  tearDown(() {
    service.onClose();
    Get.reset();
  });
  ProfileUpdateFailure failure(String id) =>
      ProfileUpdateFailure(id, 'My profile');

  test(
    'native notifications are opt-in and repeated failures are rate limited',
    () async {
      await service.notifyFailure(failure('disabled'));
      expect(messages, isEmpty);
      await settings.set('nativeNotifications', true);
      await service.notifyFailure(failure('one'));
      await service.notifyFailure(failure('one'));
      await service.notifyFailure(failure('two'));
      expect(messages, hasLength(2));
      now = now.add(const Duration(minutes: 30));
      await service.notifyFailure(failure('one'));
      expect(messages, hasLength(3));
      await settings.set('notifyProfileFailure', false);
      await service.notifyFailure(failure('three'));
      expect(messages, hasLength(3));
    },
  );

  test(
    'notification text excludes subscription URLs and control characters',
    () async {
      await settings.set('nativeNotifications', true);
      await service.notifyFailure(
        ProfileUpdateFailure(
          'private',
          'Office\nhttps://user:secret@example.com/sub?token=private',
        ),
      );
      expect(messages.single, contains('Office'));
      expect(messages.single, isNot(contains('secret')));
      expect(messages.single, isNot(contains('example.com')));
      expect(messages.single, isNot(contains('\n')));
    },
  );

  test('delivery errors are available to the settings page', () async {
    service.onClose();
    service = ProfileNotificationService(
      profiles,
      settings,
      deliver: (_, _) async =>
          throw StateError('notification permission denied'),
    );
    await settings.set('nativeNotifications', true);
    await service.notifyFailure(failure('one'));
    expect(service.error.value, contains('permission denied'));
  });
}
