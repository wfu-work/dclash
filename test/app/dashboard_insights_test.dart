import 'package:dclash_flutter/app/pages/dashboard/dashboard_controller.dart';
import 'package:dclash_flutter/app/pages/dashboard/dashboard_view.dart';
import 'package:dclash_flutter/app/pages/dashboard/widgets/dashboard_insights.dart';
import 'package:dclash_flutter/app/pages/tools/network_health_history_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_health_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_timeline_view.dart';
import 'package:dclash_flutter/app/pages/tools/traffic_statistics_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/domains/network_timeline.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/diagnostic_report_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/network_timeline_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';
import '../support/traffic_fixture.dart';

void main() {
  late SettingsService settings;
  late DiagnosticCore core;
  late HealthHistoryService health;
  late TrafficStatisticsService traffic;
  late NetworkTimelineService timeline;
  var closed = false;
  late DateTime now;

  setUp(() async {
    closed = false;
    now = DateTime(2026, 10, 24, 12);
    Get.testMode = true;
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings);
    core.status.value = CoreStatus.running;
    health = HealthHistoryService(memoryOnly: true);
    traffic = TrafficStatisticsService(
      core,
      memoryOnly: true,
      clock: () => now,
    );
    await traffic.initialize();
    timeline = NetworkTimelineService(
      core,
      settings,
      health,
      traffic,
      memoryOnly: true,
      clock: () => now,
    );
  });

  tearDown(() async {
    if (closed) {
      Get.reset();
      return;
    }
    timeline.onClose();
    traffic.onClose();
    Get.reset();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 900,
    double scale = 1,
    String locale = 'en',
    bool scroll = true,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1200));
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(locale, locale == 'zh' ? 'CN' : 'US'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.resolve(Brightness.light, 'blue'),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1200),
              textScaler: TextScaler.linear(scale),
            ),
            child: scroll ? SingleChildScrollView(child: child) : child,
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
  }

  HealthReportEntry report({HealthStatus status = HealthStatus.passed}) =>
      HealthReportEntry.capture(
        id: 'report-1',
        checkedAt: now,
        target: 'https://example.com/health',
        results: {
          for (final check in HealthCheck.values)
            check: HealthResult(status, '${check.name} result'),
        },
      );

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (Get.isRegistered<DashboardController>()) {
      await Get.delete<DashboardController>(force: true);
    }
    timeline.onClose();
    traffic.onClose();
    closed = true;
    await tester.pump();
  }

  testWidgets('insight cards render health and traffic snapshots', (
    tester,
  ) async {
    health.entries.add(report(status: HealthStatus.warning));
    trafficBaseline(core);
    trafficSample(core, upload: 1024, download: 2048);
    await tester.pump();

    var healthOpened = false;
    await mount(
      tester,
      DashboardInsightPair(
        children: [
          DashboardHealthSummary(
            history: health,
            onRunCheck: () => healthOpened = true,
            onOpenReport: (_) {},
          ),
          DashboardTodayTraffic(statistics: traffic),
        ],
      ),
    );

    expect(find.text('Recent check needs attention'), findsOneWidget);
    expect(find.text('Today\'s traffic'), findsOneWidget);
    expect(find.text('3.0 KB'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('dashboardHealthSummary')))
          .dy,
      tester.getTopLeft(find.byKey(const ValueKey('dashboardTodayTraffic'))).dy,
    );
    expect(find.byKey(const ValueKey('dashboardDailyBar:6')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboardRunHealthCheck')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('dashboardRunHealthCheck')));
    expect(healthOpened, isTrue);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('health summary updates and distinguishes incomplete reports', (
    tester,
  ) async {
    HealthReportEntry? opened;
    await mount(
      tester,
      DashboardHealthSummary(
        history: health,
        onRunCheck: () {},
        onOpenReport: (entry) => opened = entry,
      ),
    );
    expect(find.text('No completed checks yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboardOpenHealthReport')),
      findsNothing,
    );
    health.entries.assignAll([
      HealthReportEntry.capture(
        checkedAt: now,
        target: 'https://example.com',
        results: const {
          HealthCheck.core: HealthResult(HealthStatus.passed, 'OK'),
          HealthCheck.dns: HealthResult(HealthStatus.skipped, 'Skipped'),
        },
      ),
    ]);
    await tester.pump();
    expect(find.text('Recent check completed'), findsOneWidget);
    expect(find.text('Latest check passed'), findsNothing);
    expect(find.text('System DNS · Skipped'), findsOneWidget);
    expect(find.text('Current routing rules · No result'), findsOneWidget);
    expect(find.textContaining('manual diagnostic snapshot'), findsOneWidget);

    final latest = report();
    health.entries.assignAll([latest]);
    await tester.pump();
    expect(find.text('Latest check passed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dashboardOpenHealthReport')));
    expect(opened, same(latest));
    expect(core.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('daily traffic shows seven days and reacts to collection state', (
    tester,
  ) async {
    final today = now;
    now = now.subtract(const Duration(days: 1));
    trafficBaseline(core);
    trafficSample(core, upload: 1024, download: 3072);
    now = today;
    trafficSample(core, upload: 3072, download: 9216);
    var opened = false;
    await mount(
      tester,
      DashboardTodayTraffic(statistics: traffic, onOpen: () => opened = true),
    );
    expect(find.text('8.0 KB'), findsOneWidget);
    expect(find.text('Upload ↑ 2.0 KB'), findsOneWidget);
    expect(find.text('Download ↓ 6.0 KB'), findsOneWidget);
    for (var day = 0; day < 7; day++) {
      expect(find.byKey(ValueKey('dashboardDailyBar:$day')), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('dashboardDailyBar:5'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('dashboardDailyBar:6'))).height,
      72,
    );
    trafficSample(core, upload: 4096, download: 12288);
    await tester.pump();
    expect(find.text('12.0 KB'), findsOneWidget);
    core.status.value = CoreStatus.stopped;
    await tester.pump();
    expect(find.text('Collection paused while disconnected'), findsOneWidget);
    expect(find.text('12.0 KB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dashboardOpenTraffic')));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'recent events keeps the newest three and translates parameters',
    (tester) async {
      for (var index = 0; index < 4; index++) {
        timeline.add(
          kind: TimelineKind.core,
          severity: TimelineSeverity.info,
          titleKey: 'timelineCoreStatus',
          params: {'status': index.isEven ? 'running' : 'stopped'},
          occurredAt: now.subtract(Duration(minutes: index)),
        );
      }
      var opened = 0;
      await mount(
        tester,
        DashboardRecentEvents(timeline: timeline, onOpen: () => opened++),
      );

      expect(
        find.byKey(ValueKey('dashboardEvent:${timeline.entries[0].id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('dashboardEvent:${timeline.entries[2].id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('dashboardEvent:${timeline.entries[3].id}')),
        findsNothing,
      );
      expect(find.text('Core status changed to Running'), findsNWidgets(2));
      expect(find.byType(IconButton), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dashboardOpenTimeline')));
      expect(opened, 1);
      final oldestVisible = timeline.entries[2].id;
      timeline.add(
        kind: TimelineKind.route,
        severity: TimelineSeverity.warning,
        titleKey: 'timelineRouteChanged',
        occurredAt: now.add(const Duration(seconds: 1)),
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey('dashboardEvent:$oldestVisible')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('dashboardEvent:${timeline.entries.first.id}')),
      );
      expect(opened, 2);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  for (final spec in [(320.0, 'en'), (320.0, 'zh'), (1000.0, 'en')]) {
    testWidgets('insights fit large text at width ${spec.$1} in ${spec.$2}', (
      tester,
    ) async {
      health.entries.add(report(status: HealthStatus.warning));
      trafficBaseline(core);
      trafficSample(core, upload: 1024, download: 2048);
      await mount(
        tester,
        DashboardInsightPair(
          children: [
            DashboardHealthSummary(
              history: health,
              onRunCheck: () {},
              onOpenReport: (_) {},
            ),
            DashboardTodayTraffic(statistics: traffic),
          ],
        ),
        width: spec.$1,
        scale: 2,
        locale: spec.$2,
      );
      final healthCard = tester.getRect(
        find.byKey(const ValueKey('dashboardHealthSummary')),
      );
      final trafficCard = tester.getRect(
        find.byKey(const ValueKey('dashboardTodayTraffic')),
      );
      expect(healthCard.bottom, lessThan(trafficCard.top));
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }

  testWidgets('homepage preserves insight order and opens the detail pages', (
    tester,
  ) async {
    await tester.runAsync(
      () => settings.set('dashboardCards', [
        'recentEvents',
        'todayTraffic',
        'healthSummary',
      ]),
    );
    // Health diagnostics resolve the base service, as in application startup.
    Get.put<CoreService>(core);
    Get.put(settings);
    Get.put(health);
    Get.put(traffic);
    Get.put(timeline);
    Get.put(DiagnosticReportService(core, settings, health, traffic, timeline));
    Get.put(DashboardController(core, core.profiles, settings));
    final latest = report();
    health.entries.add(latest);
    await mount(tester, const DashboardView(), scroll: false);
    final events = find.byKey(const ValueKey('dashboardRecentEvents'));
    final todayTraffic = find.byKey(const ValueKey('dashboardTodayTraffic'));
    final summary = find.byKey(const ValueKey('dashboardHealthSummary'));
    expect(
      tester.getTopLeft(events).dy,
      lessThan(tester.getTopLeft(todayTraffic).dy),
    );
    expect(
      tester.getTopLeft(todayTraffic).dy,
      lessThan(tester.getTopLeft(summary).dy),
    );
    expect(core.calls, isEmpty);

    Future<void> open(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }

    await open('dashboardOpenTimeline');
    expect(find.byType(NetworkTimelineView), findsOneWidget);
    await back();
    await open('dashboardOpenTraffic');
    expect(find.byType(TrafficStatisticsView), findsOneWidget);
    await back();
    await open('dashboardRunHealthCheck');
    expect(find.byType(NetworkHealthView), findsOneWidget);
    expect(core.calls, isEmpty);
    await back();
    await open('dashboardOpenHealthReport');
    expect(
      tester
          .widget<NetworkHealthReportView>(find.byType(NetworkHealthReportView))
          .entry,
      same(latest),
    );
    await back();
    await tester.runAsync(
      () => settings.set('dashboardCards', ['recentEvents']),
    );
    await tester.pump();
    expect(events, findsOneWidget);
    expect(todayTraffic, findsNothing);
    expect(summary, findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
