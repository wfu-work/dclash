import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dclash_flutter/app/pages/connections/connections_controller.dart';
import 'package:dclash_flutter/app/pages/logs/logs_controller.dart';
import 'package:dclash_flutter/app/pages/tools/network_timeline_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_timeline.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/diagnostic_report_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/network_timeline_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/traffic_statistics_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';

class _FilePicker extends FilePicker {
  String? result;
  String? fileName;
  List<String>? extensions;
  Uint8List? bytes;
  bool fail = false;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.fileName = fileName;
    extensions = allowedExtensions;
    this.bytes = bytes;
    if (fail) throw StateError('archive unavailable');
    return result;
  }
}

void main() {
  late DiagnosticCore core;
  late SettingsService settings;
  late HealthHistoryService health;
  late TrafficStatisticsService traffic;
  late NetworkTimelineService timeline;
  late DiagnosticReportService report;

  setUp(() async {
    Get.testMode = true;
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
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
    report = DiagnosticReportService(core, settings, health, traffic, timeline);
    Get.put<CoreService>(core);
    Get.put(settings);
    Get.put(health);
    Get.put(traffic);
    Get.put(timeline);
    Get.put(report);
    Get.put(ConnectionsController(core));
    Get.put(LogsController(core));
  });

  tearDown(() async {
    timeline.onClose();
    traffic.onClose();
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
    timeline.onClose();
    traffic.onClose();
    await tester.runAsync(() async {
      await timeline.flush().catchError((Object _) {});
      await traffic.flush().catchError((Object _) {});
    });
  }

  void events() {
    timeline.add(
      kind: TimelineKind.core,
      severity: TimelineSeverity.info,
      titleKey: 'timelineCoreStatus',
      params: const {'status': 'running'},
    );
    timeline.add(
      kind: TimelineKind.error,
      severity: TimelineSeverity.error,
      titleKey: 'timelineCoreError',
      detail: 'token=secret https://user:password@example.com/path?q=private',
    );
  }

  testWidgets('workbench opens the timeline and report cards', (tester) async {
    events();
    await tester.pumpWidget(app(const ToolsView()));
    expect(find.text('2 local events'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('toolsTimelineCard')));
    expect(find.byType(NetworkTimelineView), findsOneWidget);
    expect(find.text('Core reported an error'), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));
    await tap(tester, find.byKey(const ValueKey('toolsReportCard')));
    expect(find.byType(DiagnosticReportView), findsOneWidget);
    expect(find.text('Diagnostic report package'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('timeline clear is confirmed before local data is removed', (
    tester,
  ) async {
    events();
    await tester.pumpWidget(
      app(NetworkTimelineView(timeline: timeline, report: report)),
    );
    await tap(tester, find.byTooltip('Clear timeline'));
    expect(
      find.text(
        'Clear all locally stored network timeline events? This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(timeline.entries, hasLength(2));
    await tap(tester, find.byTooltip('Clear timeline'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(timeline.entries, isEmpty);
    expect(find.text('No network events yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await finish(tester);
  });

  testWidgets('report copies and exports a sanitized ZIP package', (
    tester,
  ) async {
    events();
    final picker = _FilePicker()..result = 'content://documents/report';
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = FilePickerIO());
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app(DiagnosticReportView(report: report)));
    await tap(tester, find.byTooltip('Copy diagnostic results'));
    expect(clipboard, contains('Diagnostic report package'));
    expect(clipboard, isNot(contains('secret')));
    expect(clipboard, isNot(contains('password')));
    expect(clipboard, isNot(contains('q=private')));

    await tap(tester, find.byTooltip('Export report package'));
    expect(picker.extensions, ['zip']);
    expect(picker.fileName, startsWith('dclash-diagnostic-report-'));
    final archive = ZipDecoder().decodeBytes(picker.bytes!);
    final output = archive.files
        .map((file) => utf8.decode(file.content))
        .join();
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('password')));
    expect(find.text('File exported'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final size in [const Size(320, 768), const Size(1200, 900)]) {
    testWidgets('timeline and report fit $size in both themes and languages', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (var index = 0; index < 40; index++) {
        timeline.add(
          kind: TimelineKind.error,
          severity: index.isEven
              ? TimelineSeverity.error
              : TimelineSeverity.warning,
          titleKey: 'timelineCoreError',
          detail: 'Long diagnostic failure detail ${'x' * 500}',
        );
      }
      for (final chinese in [false, true]) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            app(
              NetworkTimelineView(timeline: timeline, report: report),
              dark: dark,
              chinese: chinese,
              scale: 1.5,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.text(chinese ? '网络状态时间线' : 'Network timeline').first,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            app(
              DiagnosticReportView(report: report),
              dark: dark,
              chinese: chinese,
              scale: 1.5,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byTooltip(chinese ? '导出报告包' : 'Export report package'),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      await finish(tester);
    });
  }
}
