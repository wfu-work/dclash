import 'package:dclash_flutter/app/pages/connections/connections_controller.dart';
import 'package:dclash_flutter/app/pages/logs/logs_controller.dart';
import 'package:dclash_flutter/app/pages/tools/connection_governance_view.dart';
import 'package:dclash_flutter/app/pages/tools/dns_observatory_view.dart';
import 'package:dclash_flutter/app/pages/tools/node_quality_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/diagnostic_report_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/network_timeline_service.dart';
import 'package:dclash_flutter/services/node_quality_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Core extends CoreService {
  _Core(super.profiles, super.settings);
  final calls = <String>[];
  @override
  Future<void> testAll() async => calls.add('all');
  @override
  Future<int?> testDelay(String name) async {
    calls.add('test:$name');
    delays[name] = 50;
    return 50;
  }

  @override
  Future<void> closeConnection(String id) async {
    calls.add('close:$id');
    connections.removeWhere((connection) => connection.id == id);
  }
}

ClashConnection connection({
  required String id,
  String process = '/Applications/Browser.app/Browser',
  String host = 'example.com',
  List<String> chains = const ['Tokyo', 'Proxy'],
  int upload = 100,
  int download = 200,
}) => ClashConnection(
  id: id,
  host: host,
  network: 'tcp',
  source: '127.0.0.1:1000',
  destination: '203.0.113.1:443',
  rule: 'MATCH',
  chains: chains,
  upload: upload,
  download: download,
  startedAt: DateTime(2026, 10, 24, 12),
  process: process,
);

void main() {
  late _Core core;
  late SettingsService settings;
  late NodeQualityService quality;
  late TrafficStatisticsService traffic;
  late HealthHistoryService health;
  late NetworkTimelineService timeline;

  setUp(() async {
    Get.testMode = true;
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = _Core(ProfileService(), settings)..status.value = CoreStatus.running;
    quality = NodeQualityService(core, memoryOnly: true);
    await quality.initialize();
    health = HealthHistoryService(memoryOnly: true);
    await health.initialize();
    traffic = TrafficStatisticsService(core, memoryOnly: true);
    await traffic.initialize();
    timeline = NetworkTimelineService(
      core,
      settings,
      health,
      traffic,
      memoryOnly: true,
    );
    await timeline.initialize();
    Get.put<CoreService>(core);
    Get.put(settings);
    Get.put(quality);
    Get.put(health);
    Get.put(traffic);
    Get.put(timeline);
    Get.put(DiagnosticReportService(core, settings, health, traffic, timeline));
    Get.put(ConnectionsController(core));
    Get.put(LogsController(core));
  });

  tearDown(() async {
    quality.onClose();
    timeline.onClose();
    traffic.onClose();
    await quality.flush().catchError((Object _) {});
    await timeline.flush().catchError((Object _) {});
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

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    quality.onClose();
    timeline.onClose();
    traffic.onClose();
    await tester.runAsync(() async {
      await quality.flush().catchError((Object _) {});
      await timeline.flush().catchError((Object _) {});
      await traffic.flush().catchError((Object _) {});
    });
  }

  testWidgets(
    'workbench exposes node quality, DNS observatory, and governance',
    (tester) async {
      core.delays['Tokyo'] = 42;
      core.dnsQueries.assignAll([
        {'domain': 'example.com'},
      ]);
      core.connections.assignAll([connection(id: 'one')]);
      await tester.pumpWidget(app(const ToolsView()));
      await tap(tester, find.byKey(const ValueKey('toolsNodeQualityCard_1')));
      expect(find.byType(NodeQualityView), findsOneWidget);
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.byKey(const ValueKey('toolsDnsObservatoryCard')));
      expect(find.byType(DnsObservatoryView), findsOneWidget);
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.byKey(const ValueKey('toolsGovernanceCard')));
      expect(find.byType(ConnectionGovernanceView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('node quality displays history and only tests on user action', (
    tester,
  ) async {
    core.delays['Tokyo'] = 42;
    core.delays['Seoul'] = -1;
    await tester.pumpWidget(app(NodeQualityView(quality: quality)));
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.textContaining('Latest 42 ms'), findsOneWidget);
    expect(find.textContaining('Failed 100%'), findsOneWidget);
    expect(core.calls, isEmpty);
    await tap(tester, find.byKey(const ValueKey('nodeQualityTestAll')));
    expect(core.calls, ['all']);
    await tap(tester, find.byTooltip('Test Tokyo'));
    expect(core.calls, ['all', 'test:Tokyo']);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('DNS observatory aggregates failures, latency and domains', (
    tester,
  ) async {
    core.dnsQueries.assignAll([
      {'domain': 'example.com', 'delay': 20},
      {'domain': 'example.com', 'delay': 40},
      {'domain': 'blocked.example', 'error': 'NXDOMAIN'},
    ]);
    await tester.pumpWidget(app(DnsObservatoryView(core: core)));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('30 ms'), findsNWidgets(2));
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('blocked.example'), findsOneWidget);
    expect(find.text('1 failures'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'connection governance groups, searches, and confirms targeted close',
    (tester) async {
      core.connections.assignAll([
        connection(
          id: 'a',
          process: '/Apps/Browser',
          host: 'example.com',
          upload: 100,
          download: 200,
        ),
        connection(
          id: 'b',
          process: '/Apps/Browser',
          host: 'news.example',
          upload: 50,
          download: 60,
        ),
        connection(
          id: 'c',
          process: '/Apps/Chat',
          host: 'chat.example',
          chains: ['Seoul', 'Proxy'],
        ),
      ]);
      await tester.pumpWidget(app(ConnectionGovernanceView(core: core)));
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('2 connections · ↑ 150 B · ↓ 260 B'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('governanceGroup_domain')));
      expect(find.text('news.example'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('governanceGroup_node')));
      expect(find.text('Tokyo'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Seoul');
      await tester.pumpAndSettle();
      expect(find.text('Tokyo'), findsNothing);
      expect(find.text('Seoul'), findsNWidgets(2));
      await tap(tester, find.byTooltip('Close group'));
      expect(
        find.text(
          'Close 1 active connections in this group? They may reconnect if the app keeps using the network.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(core.calls, ['close:c']);
      expect(core.connections.map((connection) => connection.id), ['a', 'b']);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  for (final size in [const Size(320, 768), const Size(1200, 900)]) {
    testWidgets('observability tools fit $size in both themes and languages', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (var index = 0; index < 20; index++) {
        core.delays['Very long node ${'x' * 20} $index'] = index.isEven
            ? 20 + index
            : -1;
      }
      core.dnsQueries.assignAll([
        for (var index = 0; index < 20; index++)
          {
            'domain': '${'long' * 12}$index.example.com',
            if (index.isEven) 'delay': index * 10,
            if (!index.isEven) 'error': 'timeout',
          },
      ]);
      core.connections.assignAll([
        for (var index = 0; index < 20; index++)
          connection(
            id: '$index',
            process: 'Very long application name ${'x' * 15}',
            host: '${'long' * 12}$index.example.com',
            chains: ['Very long node ${'x' * 20}'],
          ),
      ]);
      for (final chinese in [false, true]) {
        for (final dark in [false, true]) {
          for (final page in [
            NodeQualityView(quality: quality),
            DnsObservatoryView(core: core),
            ConnectionGovernanceView(core: core),
          ]) {
            await tester.pumpWidget(
              app(page, dark: dark, chinese: chinese, scale: 1.5),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
      await finish(tester);
    });
  }
}
