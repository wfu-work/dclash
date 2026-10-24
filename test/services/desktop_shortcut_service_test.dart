import 'package:dclash_flutter/app/pages/settings/settings_controller.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/desktop_shortcut_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class _FailingSettings extends SettingsService {
  _FailingSettings() : super(memoryOnly: true);
  bool fail = false;
  @override
  Future<void> set(String key, dynamic value) async {
    if (fail) throw StateError('disk full');
    await super.set(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FailingSettings settings;
  late DesktopShortcutService service;
  late Map<String, HotKey> registered;
  late Map<String, void Function()> actions;
  late CoreService core;
  var failRegistration = false;
  var toggled = 0;

  setUp(() async {
    Get.testMode = true;
    settings = _FailingSettings();
    await settings.initialize();
    core = CoreService(ProfileService(), settings, preview: true);
    registered = {};
    actions = {};
    failRegistration = false;
    toggled = 0;
    service = DesktopShortcutService(
      core,
      settings,
      toggleWindow: () async {
        toggled++;
      },
      register: (key, action) async {
        if (failRegistration && key.logicalKey.keyLabel == 'Z') {
          throw StateError('shortcut occupied');
        }
        registered[key.identifier] = key;
        actions[key.identifier] = action;
      },
      unregister: (key) async {
        registered.remove(key.identifier);
        actions.remove(key.identifier);
      },
    );
  });
  tearDown(() async {
    await service.disposeShortcuts();
    Get.reset();
  });

  test(
    'enabling installs actions and disabling removes all bindings',
    () async {
      await service.apply({...settings.fields, 'shortcutsEnabled': true});
      expect(registered, hasLength(3));
      actions['shortcutWindow']!();
      await Future<void>.delayed(Duration.zero);
      expect(toggled, 1);
      await service.apply({...settings.fields, 'shortcutsEnabled': false});
      expect(registered, isEmpty);
    },
  );

  test(
    'a partial registration failure restores every original binding',
    () async {
      final original = {...settings.fields, 'shortcutsEnabled': true};
      await service.apply(original);
      failRegistration = true;
      await expectLater(
        service.apply({...original, 'shortcutConnection': 'ctrl+alt+z'}),
        throwsStateError,
      );
      expect(registered, hasLength(3));
      expect(registered['shortcutConnection']!.logicalKey.keyLabel, 'C');
      expect(service.error.value, contains('occupied'));
      failRegistration = false;
      await service.apply({...original, 'shortcutConnection': 'ctrl+alt+z'});
      expect(registered['shortcutConnection']!.logicalKey.keyLabel, 'Z');
      expect(service.error.value, isNull);
    },
  );

  test(
    'settings save failure rolls native bindings back before reporting error',
    () async {
      await settings.set('shortcutsEnabled', true);
      await service.apply(settings.fields);
      Get.put(service);
      settings.fail = true;
      final controller = SettingsController(settings, core);
      await expectLater(
        controller.set('shortcutWindow', 'ctrl+alt+z'),
        throwsStateError,
      );
      expect(settings.fields['shortcutWindow'], 'ctrl+alt+w');
      expect(registered['shortcutWindow']!.logicalKey.keyLabel, 'W');
      expect(controller.saving.value, isFalse);
    },
  );
}
