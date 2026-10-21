import 'package:dclash_flutter/app/pages/settings/access/installed_apps_controller.dart';
import 'package:dclash_flutter/platform/installed_apps.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeInstalledApps implements InstalledApps {
  bool permitted = false;
  bool fail = false;
  int requests = 0;

  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return permitted = true;
  }

  @override
  Future<List<InstalledApp>> load() async {
    if (fail) throw StateError('Inventory unavailable');
    return const [
      InstalledApp(packageName: 'org.browser', label: 'Browser'),
      InstalledApp(packageName: 'org.system', label: 'System', system: true),
      InstalledApp(
        packageName: 'org.offline',
        label: 'Offline',
        internet: false,
      ),
    ];
  }

  @override
  Future<String?> icon(String packageName) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'filters preserve hidden selections and save absent package names',
    () async {
      final catalog = FakeInstalledApps();
      List<String>? saved;
      final controller = InstalledAppsController(
        selected: ['org.missing', 'org.system'],
        persist: (packages) async => saved = packages,
        catalog: catalog,
      );
      await controller.load();
      expect(catalog.requests, 0);
      expect(controller.permissionGranted.value, isFalse);
      expect(controller.visibleApps.map((app) => app.packageName), [
        'org.browser',
        'org.missing',
        'org.system',
      ]);
      controller.query.value = 'MISSING';
      expect(controller.visibleApps.single.installed, isFalse);
      controller.query.value = '';
      controller.selectedOnly.value = true;
      controller.toggle('org.browser', true);
      expect(controller.visibleApps, hasLength(3));
      expect(await controller.save(), isTrue);
      expect(saved, ['org.browser', 'org.missing', 'org.system']);
      controller.onClose();
    },
  );

  test(
    'denied inventory and persistence errors keep the editable selection',
    () async {
      final catalog = FakeInstalledApps()..fail = true;
      final controller = InstalledAppsController(
        selected: ['org.saved'],
        persist: (_) async => throw StateError('Write failed'),
        catalog: catalog,
      );
      await controller.load();
      expect(controller.permissionGranted.value, isFalse);
      expect(controller.error.value, contains('Inventory unavailable'));
      expect(controller.visibleApps.single.packageName, 'org.saved');
      catalog.fail = false;
      await controller.load(requestPermission: true);
      expect(catalog.requests, 1);
      expect(controller.permissionGranted.value, isTrue);
      expect(await controller.save(), isFalse);
      expect(controller.error.value, contains('Write failed'));
      expect(controller.selected, contains('org.saved'));
      expect(controller.saving.value, isFalse);
      controller.onClose();
    },
  );

  test(
    'Android adapter decodes inventory and reuses bounded icon requests',
    () async {
      const channel = MethodChannel('test.cloudrift/apps');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'isInstalledAppsPermissionGranted' => true,
              'getPackages' =>
                '[{"packageName":"org.browser","label":"Browser","internet":true,"system":false},{"packageName":"org.browser","label":"Updated","internet":true}]',
              'getPackageIcon' => '/tmp/icon.png',
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final catalog = AndroidInstalledApps(channel: channel);
      expect(await catalog.hasPermission(), isTrue);
      final apps = await catalog.load();
      expect(apps.single.label, 'Updated');
      expect(apps.single.internet, isTrue);
      expect(await catalog.icon('org.browser'), '/tmp/icon.png');
      expect(await catalog.icon('org.browser'), '/tmp/icon.png');
      expect(calls.where((call) => call == 'getPackageIcon'), hasLength(1));
    },
  );
}
