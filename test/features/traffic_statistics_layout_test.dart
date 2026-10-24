import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/app/pages/tools/traffic_statistics_view.dart';
import 'package:dclash_flutter/app/widgets/app_dropdown.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/traffic_statistics.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';
import '../support/traffic_fixture.dart';

void main() {
  late DiagnosticCore core;
  late TrafficStatisticsService statistics;
  late DateTime now;

  setUp(() async {
    Get.testMode = true;
    now = DateTime(2026, 10, 22, 12);
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    statistics = TrafficStatisticsService(
      core,
      memoryOnly: true,
      clock: () => now,
    );
    await statistics.initialize();
    Get.put<CoreService>(core);
    Get.put(statistics);
  });
  tearDown(Get.reset);

  void seed() {
    trafficBaseline(core);
    trafficSample(
      core,
      upload: 1000,
      download: 3000,
      connections: [
        trafficConnection(
          id: 'up',
          app: 'Uploader',
          host: 'upload.example',
          upload: 1000,
          download: 1000,
        ),
        trafficConnection(
          id: 'down',
          app: 'Downloader',
          host: 'download.example',
          upload: 0,
          download: 2000,
          chains: ['Singapore', 'Proxy'],
        ),
      ],
    );
    now = DateTime(2026, 10, 23, 12);
    trafficSample(
      core,
      upload: 3000,
      download: 6000,
      connections: [
        trafficConnection(
          id: 'up',
          app: 'Uploader',
          host: 'upload.example',
          upload: 3000,
          download: 1100,
        ),
        trafficConnection(
          id: 'down',
          app: 'Downloader',
          host: 'download.example',
          upload: 0,
          download: 4900,
          chains: ['Singapore', 'Proxy'],
        ),
      ],
    );
  }

  Widget app(
    Widget page, {
    bool dark = false,
    bool chinese = false,
    double scale = 1,
  }) => GetMaterialApp(
    translations: AppTranslations(),
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

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder topRank() => find.byKey(const ValueKey('trafficRank_0'));
  Finder summary() => find.byKey(const ValueKey('trafficSummary_trafficTotal'));

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    statistics.onClose();
    await tester.runAsync(statistics.flush);
  }

  testWidgets(
    'tools opens statistics without starting the core or making requests',
    (tester) async {
      await tester.pumpWidget(app(const ToolsView()));
      await tap(tester, find.text('Traffic statistics'));
      expect(find.byType(TrafficStatisticsView), findsOneWidget);
      expect(find.text('No traffic recorded yet'), findsOneWidget);
      expect(core.calls, isEmpty);
      await tap(tester, find.byTooltip('Back'));
      expect(find.byType(ToolsView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'switches app/domain/proxy rankings, sorts uploads and filters names',
    (tester) async {
      seed();
      await tester.pumpWidget(app(const TrafficStatisticsView()));
      expect(
        find.descendant(of: topRank(), matching: find.text('Downloader')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary(), matching: find.text('4.9 KB')),
        findsOneWidget,
      );

      await tap(tester, find.byKey(const ValueKey('trafficDimension_domain')));
      expect(
        find.descendant(of: topRank(), matching: find.text('download.example')),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const ValueKey('trafficDimension_node')));
      expect(
        find.descendant(of: topRank(), matching: find.text('Singapore')),
        findsOneWidget,
      );

      await tap(tester, find.byKey(const ValueKey('trafficSort')));
      await tester.tap(find.widgetWithText(MenuItemButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: topRank(), matching: find.text('Tokyo')),
        findsOneWidget,
      );
      final input = find.byKey(const ValueKey('trafficSearch'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Singapore');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('trafficRank_1')), findsNothing);
      expect(
        find.descendant(of: topRank(), matching: find.text('Singapore')),
        findsOneWidget,
      );
      await tester.enterText(input, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching traffic records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('period selection and daily drilldown use historical deltas', (
    tester,
  ) async {
    seed();
    await tester.pumpWidget(app(const TrafficStatisticsView()));
    await tap(tester, find.byKey(const ValueKey('trafficPeriod_week')));
    expect(
      find.descendant(of: summary(), matching: find.text('8.8 KB')),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('trafficDay_2026-10-22')));
    expect(
      find.descendant(of: summary(), matching: find.text('3.9 KB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topRank(), matching: find.text('Downloader')),
      findsOneWidget,
    );
    await tap(tester, find.text('All dates in this period'));
    expect(
      find.descendant(of: summary(), matching: find.text('8.8 KB')),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('trafficPeriod_month')));
    expect(find.byKey(const ValueKey('trafficDay_2026-09-24')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'keeps collecting after navigation and shows disconnected status',
    (tester) async {
      await tester.pumpWidget(app(const ToolsView()));
      trafficBaseline(core);
      trafficSample(
        core,
        upload: 100,
        download: 200,
        connections: [trafficConnection(app: '')],
      );
      await tap(tester, find.text('Traffic statistics'));
      expect(find.text('Unknown'), findsOneWidget);
      await tap(tester, find.byTooltip('Back'));
      trafficSample(
        core,
        upload: 200,
        download: 500,
        counters: [const ConnectionTrafficCounter('one', 200, 500)],
      );
      core.status.value = CoreStatus.stopped;
      await tap(tester, find.text('Traffic statistics'));
      expect(
        find.descendant(of: summary(), matching: find.text('700 B')),
        findsOneWidget,
      );
      expect(find.text('Collection paused while disconnected'), findsOneWidget);
      expect(core.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  for (final size in [const Size(320, 768), const Size(1200, 900)]) {
    testWidgets(
      'long rankings and 30 daily rows fit $size in both languages and themes',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        seed();
        trafficSample(
          core,
          connections: [
            trafficConnection(
              id: 'long',
              app: 'VeryLongApplicationName' * 10,
              host: '${'verylongdomain' * 12}.example.com',
              chains: ['超长节点名称' * 25, 'Proxy'],
              upload: 10000,
              download: 20000,
            ),
          ],
        );
        for (final chinese in [false, true]) {
          for (final dark in [false, true]) {
            await tester.pumpWidget(
              app(
                const TrafficStatisticsView(),
                dark: dark,
                chinese: chinese,
                scale: 1.5,
              ),
            );
            await tap(
              tester,
              find.byKey(const ValueKey('trafficPeriod_month')),
            );
            for (final dimension in TrafficDimension.values) {
              await tap(
                tester,
                find.byKey(ValueKey('trafficDimension_${dimension.name}')),
              );
              expect(find.byType(AppDropdown<TrafficSort>), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('trafficDay_2026-09-24')),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
        await finish(tester);
      },
    );
  }
}
