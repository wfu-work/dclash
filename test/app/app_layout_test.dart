import 'dart:async';

import 'package:dclash_flutter/app/cloudrift_app.dart';
import 'package:dclash_flutter/app/pages/dashboard/dashboard_layout_view.dart';
import 'package:dclash_flutter/app/pages/settings/appearance_view.dart';
import 'package:dclash_flutter/app/pages/settings/backup_view.dart';
import 'package:dclash_flutter/app/pages/settings/settings_view.dart';
import 'package:dclash_flutter/app/pages/workspace/workspace_controller.dart';
import 'package:dclash_flutter/app/widgets/app_dialogs.dart';
import 'package:dclash_flutter/app/widgets/app_navigation_item.dart';
import 'package:dclash_flutter/app/widgets/app_system_ui.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:dclash_flutter/services/backup_service.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Backup extends BackupService {
  _Backup(super.profiles, super.settings);
  int imports = 0;
  @override
  Future<String?> exportFile() async => null;
  @override
  Future<bool> importFile() async {
    imports++;
    return false;
  }
}

void main() {
  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    await settings.set('locale', 'en_US');
    final profiles = ProfileService();
    Get.put(settings);
    Get.put(profiles);
    Get.put(CoreService(profiles, settings, preview: true));
    Get.put<BackupService>(_Backup(profiles, settings), permanent: true);
  });
  tearDown(Get.reset);

  test('application translations have matching keys', () {
    final translations = AppTranslations().keys;
    expect(
      translations['zh_CN']!.keys.toSet(),
      translations['en_US']!.keys.toSet(),
    );
  });

  for (final size in [const Size(390, 844), const Size(1240, 850)]) {
    testWidgets(
      'application navigation and tools fit $size in light and dark',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(const CloudriftApp());
        await tester.pumpAndSettle();
        for (final mode in ['light', 'dark']) {
          await tester.runAsync(
            () => Get.find<SettingsService>().set('themeMode', mode),
          );
          for (var i = 0; i < 5; i++) {
            Get.find<WorkspaceController>().select(i);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'mode=$mode page=$i',
            );
          }
          for (final page in [
            const SettingsView(),
            const AppearanceView(),
            const BackupView(),
            const DashboardLayoutView(),
          ]) {
            unawaitedNavigatorPush(tester, page);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            Navigator.of(tester.element(find.byType(page.runtimeType))).pop();
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('mobile system bars follow theme on a pushed settings route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Dashboard').first).top,
      greaterThanOrEqualTo(28),
    );
    final dockItems = find.byWidgetPredicate(
      (widget) => widget is AppNavigationItem && widget.vertical,
    );
    expect(tester.getRect(dockItems.last).bottom, lessThanOrEqualTo(820));
    unawaitedNavigatorPush(tester, const SettingsView());
    await tester.pumpAndSettle();
    for (final mode in ['light', 'dark']) {
      await tester.runAsync(
        () => Get.find<SettingsService>().set('themeMode', mode),
      );
      await tester.pumpAndSettle();
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .descendant(
              of: find.byType(AppSystemUi),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(region.value.systemStatusBarContrastEnforced, false);
      expect(region.value.systemNavigationBarContrastEnforced, false);
      expect(
        region.value.statusBarIconBrightness,
        mode == 'dark' ? Brightness.light : Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop settings use grouped sidebar navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1240, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();
    unawaitedNavigatorPush(tester, const SettingsView());
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('General'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow navigation and settings support enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 768));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final profiles = Get.find<ProfileService>();
    profiles.profiles.add(
      ClashProfile(
        id: 'layout',
        name: 'A long subscription name / 很长的订阅名称',
        source: ProfileSource.remote,
        path: 'layout.yaml',
        download: 123456789,
        total: 987654321,
        updatedAt: DateTime(2026, 10, 19),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
    profiles.activeId.value = 'layout';
    Get.find<CoreService>().groups.add(
      const ProxyGroup(
        name: 'Proxy group',
        type: 'Selector',
        selected: 'A long proxy node name / 很长的节点名称',
        nodes: [
          ProxyNode(name: 'A long proxy node name / 很长的节点名称', type: 'VLESS'),
        ],
      ),
    );
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      Get.find<WorkspaceController>().select(i);
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(error, isNull, reason: 'enlarged page=$i');
    }
    unawaitedNavigatorPush(tester, const SettingsView());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(SettingsView))).pop();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(1240, 850));
    Get.find<WorkspaceController>().select(2);
    for (final scale in [1.0, 1.2]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'desktop profile scale=$scale',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cancelled backup pickers do not announce successful backup or restore',
    (tester) async {
      await tester.pumpWidget(const CloudriftApp());
      await tester.pumpAndSettle();
      unawaitedNavigatorPush(tester, const BackupView());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export local backup'));
      await tester.pumpAndSettle();
      expect(find.text('Backup completed'), findsNothing);
      await tester.tap(find.text('Restore local backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        Get.find<CoreService>().start(),
        throwsA(
          isA<CoreException>().having(
            (error) => error.code,
            'code',
            'maintenance',
          ),
        ),
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect((Get.find<BackupService>() as _Backup).imports, 1);
      expect(find.text('Restore completed'), findsNothing);
      Get.find<CoreService>().status.value = CoreStatus.starting;
      await tester.tap(find.text('Restore local backup'));
      await tester.pumpAndSettle();
      expect(
        find.text('Disconnect before restoring a backup.'),
        findsOneWidget,
      );
      expect((Get.find<BackupService>() as _Backup).imports, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('secret prompts obscure input and disable suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialogs.prompt(
                context,
                title: 'Password',
                initialValue: 'secret',
                obscureText: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, true);
    expect(field.enableSuggestions, false);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  });
}

void unawaitedNavigatorPush(WidgetTester tester, Widget page) {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  // The test drives the route and pops it explicitly after asserting layout.
  unawaited(
    navigator.push<void>(MaterialPageRoute<void>(builder: (_) => page)),
  );
}
