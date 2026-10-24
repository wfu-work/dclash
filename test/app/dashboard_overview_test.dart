import 'dart:async';

import 'package:dclash_flutter/app/pages/dashboard/dashboard_controller.dart';
import 'package:dclash_flutter/app/pages/dashboard/dashboard_view.dart';
import 'package:dclash_flutter/app/pages/dashboard/widgets/dashboard_summary.dart';
import 'package:dclash_flutter/app/pages/dashboard/widgets/network_overview.dart';
import 'package:dclash_flutter/app/pages/dashboard/widgets/runtime_resources.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Core extends CoreService {
  _Core(super.profiles, super.settings) : super(preview: true);
  Completer<dynamic> response = Completer<dynamic>();
  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) => response.future;
}

void main() {
  late SettingsService settings;
  late ProfileService profiles;
  late _Core core;
  late DashboardController controller;
  setUp(() async {
    Get.testMode = true;
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    profiles = ProfileService();
    profiles.profiles.add(
      ClashProfile(
        id: 'subscription',
        name: 'My subscription',
        source: ProfileSource.remote,
        path: 'subscription.yaml',
        url: 'https://example.com/subscribe?token=private',
        download: 1024,
        total: 10240,
        updatedAt: DateTime(2026, 10, 20),
        expiresAt: DateTime(2027, 1, 1),
      ),
    );
    profiles.activeId.value = 'subscription';
    core = _Core(profiles, settings)..status.value = CoreStatus.running;
    controller = Get.put(DashboardController(core, profiles, settings));
  });
  tearDown(Get.reset);

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 1000,
    double scale = 1,
    bool scroll = true,
    String locale = 'en',
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1200));
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(locale, locale == 'zh' ? 'CN' : 'US'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.resolve(brightness, 'blue'),
        home: Scaffold(
          body: scroll ? SingleChildScrollView(child: child) : child,
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  DashboardSummary summary() => DashboardSummary(
    controller: controller,
    sections: const ['currentProfile', 'currentOutbound'],
    onOpenProfiles: () {},
  );

  testWidgets('summary cards align and details expand below the full row', (
    tester,
  ) async {
    await mount(tester, summary());
    final profile = find.byKey(const ValueKey('dashboardProfileCard'));
    final outbound = find.byKey(const ValueKey('dashboardOutboundCard'));
    final before = tester.getRect(profile);
    expect(before.top, tester.getRect(outbound).top);
    expect(before.height, tester.getSize(outbound).height);
    expect(find.text('Every 24 h'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('dashboardProfileDetailsAction')),
    );
    await tester.pump();
    final details = tester.getRect(
      find.byKey(const ValueKey('dashboardProfileDetails')),
    );
    expect(details.width, 1000);
    expect(details.top, greaterThan(tester.getRect(profile).bottom));
    expect(tester.getSize(profile).height, before.height);
    expect(tester.getSize(outbound).height, before.height);
    expect(find.text('Every 24 h'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.textContaining('token='), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final spec in [(1000.0, 4), (500.0, 2), (320.0, 1)]) {
    testWidgets('runtime metrics use ${spec.$2} columns at width ${spec.$1}', (
      tester,
    ) async {
      core.memory.value = 18 * 1024 * 1024;
      core.version.value = 'mihomo test';
      await mount(
        tester,
        DashboardRuntimeResources(controller: controller),
        width: spec.$1,
      );
      final positions = [
        for (final name in [
          'memory',
          'activeConnections',
          'uptime',
          'coreVersion',
        ])
          tester.getTopLeft(find.byKey(ValueKey('dashboardMetric:$name'))),
      ];
      expect(positions.map((point) => point.dy).toSet().length, 4 ~/ spec.$2);
      expect(find.text('18.0 MB'), findsOneWidget);
      expect(find.text('mihomo test'), findsOneWidget);
      core.status.value = CoreStatus.stopped;
      await tester.pump();
      expect(find.text('18.0 MB'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'outbound failure stays inline and retry updates the IP and time',
    (tester) async {
      core.response = Completer<dynamic>();
      await mount(tester, summary());
      final action = find.byKey(
        const ValueKey('dashboardDetectOutboundAction'),
      );
      expect(core.running, true);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      await tester.tap(action);
      await tester.pump();
      expect(controller.checking.value, true);
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      core.response.completeError(StateError('connection timed out'));
      await tester.pump();
      expect(find.text('connection timed out'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('connection timed out'), findsOneWidget);
      core.response = Completer<dynamic>();
      await tester.tap(action);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('dashboardOutboundError')),
        findsNothing,
      );
      core.response.complete({'body': '{"ip":"203.0.113.8"}'});
      await tester.pump();
      expect(find.text('203.0.113.8'), findsOneWidget);
      expect(find.textContaining('Checked at'), findsOneWidget);
      core.status.value = CoreStatus.stopped;
      await tester.pump();
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(find.text('203.0.113.8'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network tabs preview three real items and view all follows selection',
    (tester) async {
      core.groups.assignAll([
        for (var i = 0; i < 4; i++)
          ProxyGroup(
            name: 'Group $i',
            type: 'Selector',
            selected: 'Node $i',
            nodes: const [],
          ),
      ]);
      core.connections.assignAll([
        for (var i = 0; i < 4; i++)
          ClashConnection(
            id: '$i',
            host: 'host$i.example',
            network: 'tcp',
            source: '127.0.0.1',
            destination: '203.0.113.1',
            rule: 'MATCH',
            chains: const ['DIRECT'],
            upload: 0,
            download: 1024,
            startedAt: DateTime(2026, 10, 24, 10, i),
          ),
      ]);
      var groupsOpened = 0, connectionsOpened = 0;
      await mount(
        tester,
        DashboardNetworkOverview(
          controller: controller,
          sections: const ['proxyGroups', 'connections'],
          onOpenGroups: () => groupsOpened++,
          onOpenConnections: () => connectionsOpened++,
        ),
      );
      expect(find.text('Group 0'), findsOneWidget);
      expect(find.text('Group 3'), findsNothing);
      final viewAll = find.byKey(const ValueKey('dashboardNetworkViewAll'));
      await tester.tap(viewAll);
      expect(groupsOpened, 1);
      await tester.tap(
        find.byKey(const ValueKey('dashboardNetworkTab:connections')),
      );
      await tester.pump();
      expect(find.text('Group 0'), findsNothing);
      expect(find.text('host0.example'), findsNothing);
      expect(
        tester.getTopLeft(find.text('host3.example')).dy,
        lessThan(tester.getTopLeft(find.text('host2.example')).dy),
      );
      await tester.tap(viewAll);
      expect(connectionsOpened, 1);
      core.connections.clear();
      await tester.pump();
      expect(find.text('No active connections'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard respects hidden sections and custom order without regrouping',
    (tester) async {
      await tester.runAsync(
        () => settings.set('dashboardCards', [
          'currentOutbound',
          'runtimeResources',
          'currentProfile',
          'connections',
        ]),
      );
      await mount(tester, const DashboardView(), scroll: false);
      expect(find.byType(DashboardSummary), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('dashboardNetworkTab:proxyGroups')),
        findsNothing,
      );
      expect(find.text('Proxy groups'), findsNothing);
      final outbound = tester.getTopLeft(
        find.byKey(const ValueKey('dashboardOutboundCard')),
      );
      final runtime = tester.getTopLeft(
        find.byKey(const ValueKey('dashboardRuntimeResources')),
      );
      final profile = tester.getTopLeft(
        find.byKey(const ValueKey('dashboardProfileCard')),
      );
      expect(outbound.dy, lessThan(runtime.dy));
      expect(runtime.dy, lessThan(profile.dy));
      await tester.runAsync(
        () => settings.set('dashboardCards', [
          'connections',
          'proxyGroups',
          'currentOutbound',
        ]),
      );
      await tester.pump();
      expect(find.byType(DashboardNetworkOverview), findsOneWidget);
      expect(find.byType(DashboardRuntimeResources), findsNothing);
      expect(find.byKey(const ValueKey('dashboardProfileCard')), findsNothing);
      final tabs = tester.widget<DashboardNetworkOverview>(
        find.byType(DashboardNetworkOverview),
      );
      expect(tabs.sections, ['connections', 'proxyGroups']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'zh']) {
    testWidgets('overview fits a narrow window at large text in $locale', (
      tester,
    ) async {
      core.version.value = 'mihomo long version string';
      core.groups.add(
        const ProxyGroup(
          name: 'A long group name / 很长的分组名称',
          type: 'Selector',
          selected: 'A long selected proxy node name / 很长的节点名称',
          nodes: [],
        ),
      );
      await mount(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardRuntimeResources(controller: controller),
            summary(),
            DashboardNetworkOverview(
              controller: controller,
              sections: const ['proxyGroups', 'connections'],
              onOpenGroups: () {},
              onOpenConnections: () {},
            ),
          ],
        ),
        width: 320,
        scale: 2,
        locale: locale,
        brightness: Brightness.dark,
      );
      final profile = tester.getRect(
        find.byKey(const ValueKey('dashboardProfileCard')),
      );
      final outbound = tester.getRect(
        find.byKey(const ValueKey('dashboardOutboundCard')),
      );
      expect(profile.bottom, lessThan(outbound.top));
      final details = find.byKey(
        const ValueKey('dashboardProfileDetailsAction'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pump();
      expect(find.text('example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
