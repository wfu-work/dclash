import 'package:dclash_flutter/app/pages/connections/connections_controller.dart';
import 'package:dclash_flutter/app/pages/connections/connections_view.dart';
import 'package:dclash_flutter/app/pages/connections/feed_view.dart';
import 'package:dclash_flutter/app/pages/logs/logs_controller.dart';
import 'package:dclash_flutter/app/pages/logs/logs_view.dart';
import 'package:dclash_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:dclash_flutter/app/pages/profiles/profiles_view.dart';
import 'package:dclash_flutter/app/pages/proxies/proxies_controller.dart';
import 'package:dclash_flutter/app/pages/proxies/proxies_view.dart';
import 'package:dclash_flutter/app/pages/proxies/widgets/proxy_node_tile.dart';
import 'package:dclash_flutter/configs/localization/feature_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Translations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': FeatureTranslations.en,
    'zh_CN': FeatureTranslations.zh,
  };
}

void main() {
  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    final profiles = ProfileService();
    final core = CoreService(profiles, settings, preview: true);
    Get.put(ProxiesController(core, settings));
    Get.put(ProfilesController(profiles, core));
    Get.put(ConnectionsController(core));
    Get.put(LogsController(core));
  });
  tearDown(Get.reset);

  Widget app(
    Widget page, {
    bool dark = false,
    bool chinese = false,
    double scale = 1,
  }) => GetMaterialApp(
    translations: _Translations(),
    locale: chinese ? const Locale('zh', 'CN') : const Locale('en', 'US'),
    theme: AppTheme.resolve(dark ? Brightness.dark : Brightness.light, 'blue'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: page),
  );

  test('feature translation maps remain complete', () {
    expect(
      FeatureTranslations.zh.keys.toSet(),
      FeatureTranslations.en.keys.toSet(),
    );
  });

  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('empty feature pages fit $size in both themes', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final dark in [false, true]) {
        for (final page in [
          const ProxiesView(),
          const ProfilesView(),
          const ConnectionsView(),
          const LogsView(),
          const FeedView(dns: true),
          const FeedView(dns: false),
        ]) {
          await tester.pumpWidget(app(page, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets('proxy grid reacts to layout toggles and latency changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.find<ProxiesController>();
    controller.core.status.value = CoreStatus.running;
    controller.core.groups.add(
      const ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Tokyo',
        nodes: [
          ProxyNode(name: 'Tokyo', type: 'VLESS'),
          ProxyNode(name: 'Singapore', type: 'SS'),
        ],
      ),
    );
    await tester.pumpWidget(app(const ProxiesView()));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Protocol · VLESS'), findsOneWidget);
    expect(find.text('Protocol · SS'), findsOneWidget);
    controller.grid.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ProxyNodeTile), findsNWidgets(2));
    expect(find.byKey(const ValueKey('proxyProtocol_Tokyo')), findsOneWidget);
    controller.core.delays['Tokyo'] = 88;
    await tester.pump();
    expect(find.text('88 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy toolbar locates a selected node outside the viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.find<ProxiesController>();
    controller.core.status.value = CoreStatus.running;
    final nodes = [
      for (var index = 0; index < 30; index++)
        ProxyNode(name: 'Node $index', type: 'VLESS'),
    ];
    controller.core.groups.add(
      ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Node 29',
        nodes: nodes,
      ),
    );
    await tester.pumpWidget(app(const ProxiesView()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxyProtocol_Node 29')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('proxyLocateSelectedAction')));
    await tester.pumpAndSettle();

    final protocol = find.byKey(const ValueKey('proxyProtocol_Node 29'));
    expect(protocol, findsOneWidget);
    final viewport = tester.getRect(find.byType(GridView));
    final nodeRect = tester.getRect(protocol);
    expect(nodeRect.top, greaterThanOrEqualTo(viewport.top));
    expect(nodeRect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy group toolbar fits on a small screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.find<ProxiesController>();
    controller.core.status.value = CoreStatus.running;
    controller.core.groups.add(
      const ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Tokyo',
        nodes: [ProxyNode(name: 'Tokyo', type: 'VLESS')],
      ),
    );
    await tester.pumpWidget(app(const ProxiesView()));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(ProxyNodeTile), findsOneWidget);
    final title = tester.getRect(find.text('Proxies').first);
    final action = tester.getRect(
      find.byKey(const ValueKey('proxyTestAllAction')),
    );
    expect(action.left, greaterThan(title.right));
    expect((action.center.dy - title.center.dy).abs(), lessThan(14));
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (size: const Size(320, 844), scale: 1.0),
    (size: const Size(390, 844), scale: 1.0),
    (size: const Size(647, 900), scale: 1.0),
    (size: const Size(648, 900), scale: 1.0),
    (size: const Size(947, 900), scale: 1.0),
    (size: const Size(948, 900), scale: 1.0),
    (size: const Size(390, 1000), scale: 1.5),
    (size: const Size(390, 1100), scale: 2.0),
    (size: const Size(1200, 1000), scale: 2.0),
  ]) {
    testWidgets('long proxy names and protocol badges fit ${scenario.size} '
        'at text scale ${scenario.scale}', (tester) async {
      await tester.binding.setSurfaceSize(scenario.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = Get.find<ProxiesController>();
      controller.core.status.value = CoreStatus.running;
      const nodes = [
        ProxyNode(name: '⛔ 软件需要升级才能用，请按照教程安装新软件', type: 'Trojan'),
        ProxyNode(name: '🆔 我的账号：1076516794@qq.com', type: 'Trojan'),
        ProxyNode(name: '🕒 过期时间：2027-01-04 20:41:11', type: 'Trojan'),
      ];
      controller.core.groups.add(
        const ProxyGroup(
          name: 'Proxy',
          type: 'Selector',
          selected: '⛔ 软件需要升级才能用，请按照教程安装新软件',
          nodes: nodes,
        ),
      );
      controller.core.delays[nodes[0].name] = 1234;
      controller.core.delays[nodes[1].name] = -1;

      for (final dark in [false, true]) {
        for (final chinese in [false, true]) {
          Get.locale = chinese
              ? const Locale('zh', 'CN')
              : const Locale('en', 'US');
          await tester.pumpWidget(
            app(
              const ProxiesView(),
              dark: dark,
              chinese: chinese,
              scale: scenario.scale,
            ),
          );
          await tester.pumpAndSettle();

          void expectContentInsideCards() {
            expect(find.byType(ProxyNodeTile), findsWidgets);
            for (final element in find.byType(ProxyNodeTile).evaluate()) {
              final tile = find.byWidget(element.widget);
              final node = (element.widget as ProxyNodeTile).node;
              final nameRect = tester.getRect(
                find.descendant(of: tile, matching: find.text(node.name)),
              );
              final badgeRect = tester.getRect(
                find.byKey(ValueKey('proxyProtocol_${node.name}')),
              );
              final tileRect = tester.getRect(tile);
              expect(badgeRect.top, greaterThanOrEqualTo(nameRect.bottom));
              expect(badgeRect.bottom, lessThanOrEqualTo(tileRect.bottom));
              expect(badgeRect.left, greaterThanOrEqualTo(tileRect.left));
              expect(badgeRect.right, lessThanOrEqualTo(tileRect.right));
              expect(
                find.descendant(
                  of: tile,
                  matching: find.text(
                    '${chinese ? '协议' : 'Protocol'} · Trojan',
                  ),
                ),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          }

          expectContentInsideCards();
          controller.grid.value = false;
          await tester.pumpAndSettle();
          expectContentInsideCards();
          controller.grid.value = true;
          await tester.pumpAndSettle();
        }
      }
    });
  }

  testWidgets('latency testing explains that the core must be connected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.find<ProxiesController>();
    controller.previewGroups.add(
      const ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Tokyo',
        nodes: [ProxyNode(name: 'Tokyo', type: 'VLESS')],
      ),
    );
    await tester.pumpWidget(app(const ProxiesView()));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Test latency');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();
    expect(
      find.text('Start the service from Overview to see live activity.'),
      findsOneWidget,
    );
  });
}
