import 'dart:convert';

import 'package:dclash_flutter/app/pages/tools/network_health_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_health_history_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_diagnostics_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/app/pages/settings/settings_controller.dart';
import 'package:dclash_flutter/app/pages/settings/settings_view.dart';
import 'package:dclash_flutter/app/pages/workspace/workspace_controller.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/domains/network_health_report.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/health_history_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';
import '../support/health_host.dart';

class _ReportFilePicker extends FilePicker {
  String? path;
  String? name;
  FileType? type;
  List<String>? extensions;
  Uint8List? reportBytes;
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
    name = fileName;
    this.type = type;
    extensions = allowedExtensions;
    reportBytes = bytes;
    if (fail) throw StateError('report export unavailable');
    return path;
  }
}

HealthReportEntry historyReport(
  int minute, {
  String id = 'history',
}) => HealthReportEntry.capture(
  id: '$id-$minute',
  checkedAt: DateTime.utc(2026, 10, 23, 12, minute),
  target: 'https://user:secret@example.com/path?q=private#fragment',
  results: {
    for (final check in HealthCheck.values)
      check: HealthResult(
        HealthStatus.passed,
        'healthCoreRunning',
        details:
            'Request https://user:secret@example.com/path?q=private#fragment',
      ),
  },
);

void main() {
  late DiagnosticCore core;
  late FakeHealthHost host;
  late HealthHistoryService history;

  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    host = FakeHealthHost();
    history = HealthHistoryService(memoryOnly: true);
    await history.initialize();
    Get.put<CoreService>(core);
    Get.put<HealthHistoryService>(history);
    Get.put(WorkspaceController());
  });
  tearDown(Get.reset);

  Widget app(
    Widget page, {
    bool dark = false,
    String language = 'en',
    double scale = 1,
  }) => GetMaterialApp(
    translations: AppTranslations(),
    locale: language == 'zh'
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US'),
    theme: AppTheme.resolve(dark ? Brightness.dark : Brightness.light, 'blue'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: page),
  );

  testWidgets('tools opens health check and returns without running probes', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ToolsView()));
    await tester.tap(find.text('Network health check'));
    await tester.pumpAndSettle();
    expect(find.byType(NetworkHealthView), findsOneWidget);
    expect(core.calls.where((call) => call.$1 == 'probe'), isEmpty);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tools opens history, details copy sanitized report, and returns',
    (tester) async {
      await tester.runAsync(
        () => history.add(historyReport(1, id: 'navigation')),
      );
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

      await tester.pumpWidget(app(const ToolsView()));
      await tester.tap(find.text('Diagnostic history'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkHealthHistoryView), findsOneWidget);
      expect(find.text('https://example.com/path'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(find.textContaining('secret'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('healthHistory_navigation-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NetworkHealthReportView), findsOneWidget);
      await tester.tap(find.byTooltip('Copy diagnostic results'));
      await tester.pump();
      expect(clipboard, contains('https://example.com/path'));
      expect(clipboard, isNot(contains('private')));
      expect(clipboard, isNot(contains('secret')));
      expect(clipboard, isNot(contains('fragment')));
      expect(clipboard, isNot(contains('user:')));
      expect(clipboard, contains('Core service'));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkHealthHistoryView), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolsView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing history requires confirmation', (tester) async {
    await tester.runAsync(() => history.add(historyReport(2, id: 'clear')));
    await tester.pumpWidget(app(NetworkHealthHistoryView(history: history)));
    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Clear all locally stored network diagnostic reports? This cannot be undone.',
      ),
      findsOneWidget,
    );
    expect(history.entries, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(history.entries, hasLength(1));
    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(history.entries, isEmpty);
    expect(find.text('No completed reports yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'export supplies sanitized TXT, handles cancellation and failure',
    (tester) async {
      final picker = _ReportFilePicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = FilePickerIO());
      final entry = historyReport(3, id: 'export');
      await tester.pumpWidget(app(NetworkHealthReportView(entry: entry)));

      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      expect(picker.type, FileType.custom);
      expect(picker.extensions, ['txt']);
      expect(picker.name, 'dclash-network-health-20261023T120300000Z.txt');
      expect(utf8.decode(picker.reportBytes!), formatHealthReport(entry));
      expect(utf8.decode(picker.reportBytes!), isNot(contains('private')));
      expect(utf8.decode(picker.reportBytes!), isNot(contains('secret')));
      expect(find.text('File exported'), findsNothing);

      // Mobile document providers save the supplied bytes and return a URI.
      picker.path = 'content://documents/network-report';
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      expect(find.text('File exported'), findsOneWidget);

      picker.fail = true;
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();
      expect(find.text('report export unavailable'), findsOneWidget);
      expect(find.byType(NetworkHealthReportView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('history list fits $size in both themes', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (var minute = 1; minute <= 20; minute++) {
          await history.add(historyReport(minute, id: 'layout'));
        }
      });
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          app(
            NetworkHealthHistoryView(history: history),
            dark: dark,
            language: 'zh',
            scale: 1.2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('诊断历史'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('healthHistory_layout-20')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('healthHistory_layout-1')),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('healthHistory_layout-20')),
        );
        await tester.tap(find.byKey(const ValueKey('healthHistory_layout-20')));
        await tester.pumpAndSettle();
        expect(find.byType(NetworkHealthReportView), findsOneWidget);
        expect(find.text('通过'), findsNWidgets(6));
        await tester.ensureVisible(find.text('当前分流规则'));
        expect(find.text('Request https://example.com/path'), findsNWidgets(6));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('six results and recommendations fit $size in both themes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          app(
            NetworkHealthView(host: host),
            dark: dark,
            language: 'zh',
            scale: 1.2,
          ),
        );
        final run = find.byKey(const ValueKey('healthRun'));
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(find.text('所有检查均已通过'), findsOneWidget);
        expect(find.text('已完成 6 / 6 项'), findsOneWidget);
        expect(find.text('通过'), findsNWidgets(6));
        await tester.ensureVisible(
          find.byKey(const ValueKey('healthCheck_routing')),
        );
        expect(find.textContaining('DomainSuffix,example.com'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('URL drill-down preserves target and copying includes results', (
    tester,
  ) async {
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
    await tester.pumpWidget(app(NetworkHealthView(host: host)));
    const target = 'https://example.com/target?q=health';
    await tester.enterText(
      find.byKey(const ValueKey('healthUrlInput')),
      target,
    );
    final run = find.byKey(const ValueKey('healthRun'));
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy diagnostic results'));
    await tester.pump();
    expect(clipboard, contains(target));
    expect(clipboard, contains('HTTP 204'));
    final details = find.text('Inspect URL and routes').last;
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(UrlDiagnosticsView), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('diagnosticUrlInput')),
          )
          .controller!
          .text,
      target,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopped core still allows local checks and links to profiles', (
    tester,
  ) async {
    core.status.value = CoreStatus.stopped;
    await tester.pumpWidget(app(NetworkHealthView(host: host)));
    final run = find.byKey(const ValueKey('healthRun'));
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.text('Skipped'), findsNWidgets(3));
    final profiles = find.text('Select a profile');
    await tester.ensureVisible(profiles);
    await tester.tap(profiles);
    await tester.pumpAndSettle();
    expect(Get.find<WorkspaceController>().index.value, 2);
    expect(core.calls.where((call) => call.$1 == 'probe'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'proxy remediation opens Network settings without changing settings',
    (tester) async {
      Get.put(SettingsController(core.settings, core));
      host.proxy = () async => null;
      final before = Map.of(core.settings.fields);
      await tester.pumpWidget(app(NetworkHealthView(host: host)));
      final run = find.byKey(const ValueKey('healthRun'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      final network = find.text('Open Network settings');
      await tester.ensureVisible(network);
      await tester.tap(network);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsView>(find.byType(SettingsView)).section,
        'network',
      );
      expect(core.settings.fields, before);
      expect(
        core.calls.every((c) => ['probe', 'watchRoute'].contains(c.$1)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
