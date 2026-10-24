import 'dart:async';

import 'package:dclash_flutter/app/cloudrift_app.dart';
import 'package:dclash_flutter/app/pages/dashboard/dashboard_layout_view.dart';
import 'package:dclash_flutter/app/pages/settings/about_view.dart';
import 'package:dclash_flutter/app/pages/settings/appearance_view.dart';
import 'package:dclash_flutter/app/pages/settings/backup_view.dart';
import 'package:dclash_flutter/app/pages/settings/licenses_view.dart';
import 'package:dclash_flutter/app/pages/settings/settings_view.dart';
import 'package:dclash_flutter/app/pages/workspace/workspace_controller.dart';
import 'package:dclash_flutter/app/widgets/app_dialogs.dart';
import 'package:dclash_flutter/app/widgets/app_navigation_item.dart';
import 'package:dclash_flutter/app/widgets/app_system_ui.dart';
import 'package:dclash_flutter/app/widgets/app_workspace_surface.dart';
import 'package:dclash_flutter/app/widgets/connect_button.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:dclash_flutter/services/backup_service.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    PackageInfo.setMockInitialValues(
      appName: 'dclash',
      packageName: 'test.dclash',
      version: '2.3.4',
      buildNumber: '42',
      buildSignature: '',
    );
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

  testWidgets('desktop workspace uses the bright primary content canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1240, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AppWorkspaceSurface),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.color, Colors.white);
    expect(tester.takeException(), isNull);
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
          for (var i = 0; i < 4; i++) {
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
            const AboutView(),
            const LicensesView(),
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

  testWidgets('mobile workspace has four tabs and opens settings from header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();

    final dockItems = find.byWidgetPredicate(
      (widget) => widget is AppNavigationItem && widget.vertical,
    );
    expect(dockItems, findsNWidgets(4));
    expect(
      tester.widgetList<AppNavigationItem>(dockItems).map((item) => item.label),
      ['Home', 'Proxies', 'Profiles', 'Tools'],
    );
    await tester.tap(find.byKey(const ValueKey('dashboardSettingsAction')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile dashboard aligns header actions and status controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profiles = Get.find<ProfileService>();
    profiles.profiles.add(
      const ClashProfile(
        id: 'mobile-layout',
        name: 'Mobile layout',
        source: ProfileSource.custom,
        path: 'mobile-layout.yaml',
      ),
    );
    profiles.activeId.value = 'mobile-layout';
    Get.find<CoreService>().status.value = CoreStatus.running;
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Dashboard').first);
    final layoutAction = tester.getRect(
      find.byKey(const ValueKey('dashboardLayoutAction')),
    );
    final settingsAction = tester.getRect(
      find.byKey(const ValueKey('dashboardSettingsAction')),
    );
    expect(layoutAction.left, greaterThan(title.right));
    expect(settingsAction.left, greaterThan(layoutAction.right));
    expect((layoutAction.center.dy - title.center.dy).abs(), lessThan(14));
    expect(settingsAction.right, lessThanOrEqualTo(374));

    final statusCard = tester.getRect(
      find.byKey(const ValueKey('dashboardStatusCard')),
    );
    final controls = tester.getRect(
      find.byKey(const ValueKey('dashboardStatusControls')),
    );
    final connect = tester.getRect(find.byType(ConnectButton));
    expect(controls.bottom, closeTo(statusCard.bottom - 18, 1));
    expect(connect.right, lessThanOrEqualTo(statusCard.right - 17));
    expect(connect.center.dy, closeTo(controls.center.dy, 1));
    expect(connect.width, 68);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dashboard stacks the status controls before overflow', (
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
      const ClashProfile(
        id: 'narrow-layout',
        name: 'Narrow layout',
        source: ProfileSource.custom,
        path: 'narrow-layout.yaml',
      ),
    );
    profiles.activeId.value = 'narrow-layout';
    Get.find<CoreService>().status.value = CoreStatus.running;
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();

    final controls = tester.getRect(
      find.byKey(const ValueKey('dashboardStatusControls')),
    );
    final connect = tester.getRect(find.byType(ConnectButton));
    expect(connect.top, greaterThan(controls.top));
    expect(connect.right, lessThanOrEqualTo(controls.right));
    expect(tester.takeException(), isNull);
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
    expect(find.byKey(const ValueKey('settingsMenu:general')), findsOneWidget);
    expect(find.text('General'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'embedded about uses the settings back control and live versions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1240, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const CloudriftApp());
      await tester.pumpAndSettle();
      unawaitedNavigatorPush(tester, const SettingsView(section: 'about'));
      await tester.pumpAndSettle();

      expect(find.byType(AboutView), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('2.3.4'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Reference source'), findsNothing);
      Get.find<CoreService>().version.value = 'mihomo test';
      await tester.pumpAndSettle();
      expect(find.text('mihomo test'), findsOneWidget);

      final aboutMenu = find.byKey(const ValueKey('settingsMenu:about'));
      final licensesMenu = find.byKey(const ValueKey('settingsMenu:licenses'));
      await tester.scrollUntilVisible(
        licensesMenu,
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final groupHeading = find.text('About').first;
      expect(
        tester.getTopLeft(groupHeading).dy,
        lessThan(tester.getTopLeft(aboutMenu).dy),
      );
      expect(
        tester.getTopLeft(aboutMenu).dy,
        lessThan(tester.getTopLeft(licensesMenu).dy),
      );
      await tester.tap(licensesMenu);
      await tester.pumpAndSettle();
      expect(find.byType(LicensesView), findsOneWidget);
      expect(find.byType(AboutView), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(aboutMenu);
      await tester.pumpAndSettle();
      expect(find.byType(AboutView), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile about and licenses use back navigation', (tester) async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['Example component'], 'First license');
      yield LicenseEntryWithLineBreaks(['Example component'], 'Second license');
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const CloudriftApp());
    await tester.pumpAndSettle();
    unawaitedNavigatorPush(tester, const SettingsView());
    await tester.pumpAndSettle();
    final about = find.byKey(const ValueKey('settingsMenu:about'));
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(find.byType(AboutView), findsOneWidget);
    expect(find.byType(AboutDialog), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutView), findsNothing);
    final licenses = find.byKey(const ValueKey('settingsMenu:licenses'));
    await tester.ensureVisible(licenses);
    await tester.tap(licenses);
    await tester.pumpAndSettle();
    expect(find.byType(LicensesView), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Example component'), findsOneWidget);
    await tester.tap(find.text('Example component'));
    await tester.pumpAndSettle();
    expect(find.text('First license'), findsOneWidget);
    expect(find.text('Second license'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensesView), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensesView), findsNothing);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.byType(ConnectButton), findsOneWidget);
    final core = Get.find<CoreService>();
    core
      ..status.value = CoreStatus.running
      ..memory.value = 18 * 1024 * 1024
      ..version.value = 'mihomo test';
    core.connections.add(
      ClashConnection(
        id: 'runtime-connection',
        host: 'runtime.example',
        network: 'tcp',
        source: '127.0.0.1:7890',
        destination: '203.0.113.1:443',
        rule: 'MATCH',
        chains: const ['DIRECT'],
        upload: 0,
        download: 0,
        startedAt: DateTime(2026, 10, 23),
      ),
    );
    await tester.pump();
    expect(find.text('18.0 MB'), findsOneWidget);
    expect(find.text('mihomo test'), findsOneWidget);
    core.error.value = 'DClashCore is missing';
    await tester.pump();
    expect(find.text('Why the connection failed'), findsOneWidget);
    expect(find.text('DClashCore is missing'), findsOneWidget);
    core.error.value = null;
    await tester.pump();
    expect(find.text('Outbound mode'), findsOneWidget);
    expect(find.text('Allow LAN'), findsOneWidget);
    expect(find.text('Mixed proxy port'), findsOneWidget);
    expect(find.text('Runtime resources'), findsOneWidget);
    expect(find.text('Active connections'), findsOneWidget);
    final detailsAction = find.byKey(
      const ValueKey('dashboardProfileDetailsAction'),
    );
    await tester.ensureVisible(detailsAction);
    await tester.tap(detailsAction);
    await tester.pumpAndSettle();
    expect(find.text('Profile type'), findsOneWidget);
    expect(find.text('Last updated'), findsNWidgets(2));
    expect(find.text('Every 24 h'), findsOneWidget);
    expect(find.text('2027-01-01'), findsNWidgets(2));
    for (var i = 0; i < 4; i++) {
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
    unawaitedNavigatorPush(tester, const AboutView());
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find
          .descendant(
            of: find.byType(AboutView),
            matching: find.byType(SelectableText),
          )
          .last,
    );
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(AboutView))).pop();
    await tester.pumpAndSettle();
    unawaitedNavigatorPush(tester, const LicensesView());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(LicensesView))).pop();
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
