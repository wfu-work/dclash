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

  Widget app(Widget page, {bool dark = false}) => GetMaterialApp(
    translations: _Translations(),
    locale: const Locale('en', 'US'),
    theme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: dark ? Brightness.dark : Brightness.light,
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
    controller.grid.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ProxyNodeTile), findsNWidgets(2));
    controller.core.delays['Tokyo'] = 88;
    await tester.pump();
    expect(find.text('88 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
