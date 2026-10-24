import 'package:dclash_flutter/app/pages/connections/connections_controller.dart';
import 'package:dclash_flutter/app/pages/connections/connections_view.dart';
import 'package:dclash_flutter/app/pages/connections/feed_view.dart';
import 'package:dclash_flutter/app/pages/logs/logs_controller.dart';
import 'package:dclash_flutter/app/pages/logs/logs_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_health_history_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_health_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/app/pages/tools/traffic_statistics_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';
import '../support/traffic_fixture.dart';

HealthReportEntry _report() => HealthReportEntry.capture(
  id: 'latest',
  checkedAt: DateTime.utc(2026, 10, 24, 9),
  target: 'https://example.com',
  results: {
    for (final check in HealthCheck.values)
      check: const HealthResult(HealthStatus.passed, 'healthCoreRunning'),
  },
);

ClashConnection _connection(String id) => ClashConnection(
  id: id,
  host: 'example.com',
  network: 'tcp',
  source: '127.0.0.1:10000',
  destination: '203.0.113.1:443',
  rule: 'MATCH',
  chains: const ['Tokyo'],
  upload: 0,
  download: 0,
  startedAt: DateTime(2026, 10, 24, 9),
);

void main() {
  late DiagnosticCore core;
  late HealthHistoryService history;
  late TrafficStatisticsService traffic;

  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    history = HealthHistoryService(memoryOnly: true);
    await history.initialize();
    traffic = TrafficStatisticsService(
      core,
      memoryOnly: true,
      clock: () => DateTime(2026, 10, 24, 9),
    );
    await traffic.initialize();
    Get.put<CoreService>(core);
    Get.put(history);
    Get.put(traffic);
    Get.put(ConnectionsController(core));
    Get.put(LogsController(core));
  });

  tearDown(() async {
    traffic.onClose();
    await traffic.flush().catchError((Object _) {});
    Get.reset();
  });

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

  testWidgets('workbench shows live summaries and the latest health result', (
    tester,
  ) async {
    await tester.runAsync(() => history.add(_report()));
    trafficBaseline(core);
    trafficSample(core, upload: 100, download: 200);
    core.connections.assignAll([_connection('one'), _connection('two')]);
    core.requests.assignAll([
      {'id': 'request'},
    ]);
    core.dnsQueries.assignAll([
      {'id': 'dns'},
      {'id': 'dns-2'},
    ]);
    core.logs.assignAll([
      CoreLog(level: 'info', message: 'ready', time: DateTime(2026)),
      CoreLog(level: 'error', message: 'failed request', time: DateTime(2026)),
    ]);

    await tester.pumpWidget(app(const ToolsView()));
    expect(find.textContaining('Latest check passed'), findsOneWidget);
    expect(find.text('Today: 300 B'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolsConnectionsCard')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolsDnsCard')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    traffic.onClose();
    await tester.runAsync(traffic.flush);
  });

  testWidgets('primary and activity cards preserve feature navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ToolsView()));

    await tap(tester, find.byKey(const ValueKey('toolsRunHealth')));
    expect(find.byType(NetworkHealthView), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));

    await tap(tester, find.byKey(const ValueKey('toolsTrafficCard_0')));
    expect(find.byType(TrafficStatisticsView), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));

    await tap(tester, find.byKey(const ValueKey('toolsConnectionsCard')));
    expect(find.byType(ConnectionsView), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));

    await tap(tester, find.byKey(const ValueKey('toolsRequestsCard')));
    expect(find.byType(FeedView), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));

    await tap(tester, find.byKey(const ValueKey('toolsLogsCard')));
    expect(find.byType(LogsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('health history action opens records without starting probes', (
    tester,
  ) async {
    await tester.runAsync(() => history.add(_report()));
    await tester.pumpWidget(app(const ToolsView()));
    await tap(tester, find.text('Diagnostic history'));
    expect(find.byType(NetworkHealthHistoryView), findsOneWidget);
    expect(core.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 768), const Size(1200, 900)]) {
    testWidgets('workbench fits $size in both themes and languages', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      core.connections.assignAll(
        List.generate(12, (index) => _connection('$index')),
      );
      core.requests.assignAll(List.generate(120, (index) => {'id': '$index'}));
      core.dnsQueries.assignAll(List.generate(42, (index) => {'id': '$index'}));
      core.logs.assignAll(
        List.generate(
          999,
          (index) =>
              CoreLog(level: 'info', message: '$index', time: DateTime(2026)),
        ),
      );
      for (final chinese in [false, true]) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            app(const ToolsView(), dark: dark, chinese: chinese, scale: 1.5),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('toolsLogsCard')),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(chinese ? '资源管理' : 'Resources'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      traffic.onClose();
      await tester.runAsync(traffic.flush);
    });
  }
}
