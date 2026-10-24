import 'package:dclash_flutter/app/pages/tools/network_diagnostics_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/app/widgets/app_switch.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';

void main() {
  late DiagnosticCore core;
  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = DiagnosticCore(ProfileService(), settings)
      ..status.value = CoreStatus.running;
    core.groups.add(
      const ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Tokyo',
        nodes: [ProxyNode(name: 'Tokyo', type: 'VLESS')],
      ),
    );
    Get.put<CoreService>(core);
  });
  tearDown(Get.reset);

  Widget app(Widget page, {bool dark = false, String language = 'en'}) =>
      GetMaterialApp(
        translations: AppTranslations(),
        locale: language == 'zh'
            ? const Locale('zh', 'CN')
            : const Locale('en', 'US'),
        theme: AppTheme.resolve(
          dark ? Brightness.dark : Brightness.light,
          'blue',
        ),
        home: Scaffold(body: page),
      );

  testWidgets(
    'tools exposes both diagnostic pages with working back navigation',
    (tester) async {
      await tester.pumpWidget(app(const ToolsView()));
      await tester.tap(find.text('URL diagnostics'));
      await tester.pumpAndSettle();
      expect(find.byType(UrlDiagnosticsView), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service availability'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDiagnosticsView), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('URL form and comparison results fit $size in both themes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final dark in [false, true]) {
        await tester.pumpWidget(app(const UrlDiagnosticsView(), dark: dark));
        await tester.enterText(
          find.byKey(const ValueKey('diagnosticUrlInput')),
          'https://example.com',
        );
        await tester.ensureVisible(find.byType(AppSwitch));
        await tester.tap(find.byType(AppSwitch));
        final run = find.widgetWithText(FilledButton, 'Run diagnostics');
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(find.text('Received HTTP response'), findsNothing);
        expect(find.textContaining('HTTP 204'), findsNWidgets(2));
        expect(find.text('DomainSuffix,example.com'), findsOneWidget);
        expect(find.text('Proxy → Tokyo'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('service results and long route names fit $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      core.groups.add(
        const ProxyGroup(
          name: 'A very long proxy group name that should fit on a phone',
          type: 'Selector',
          selected: 'Tokyo',
          nodes: [],
        ),
      );
      await tester.pumpWidget(
        app(const ServiceDiagnosticsView(), dark: true, language: 'zh'),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('A very long proxy group name').last,
      );
      await tester.pumpAndSettle();
      final run = find.widgetWithText(FilledButton, '检测全部服务');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call.$1 == 'serviceCheck'),
        hasLength(13),
      );
      expect(
        core.calls
            .where((call) => call.$1 == 'serviceCheck')
            .every(
              (call) =>
                  (call.$2 as Map)['proxy-name'] ==
                  'A very long proxy group name that should fit on a phone',
            ),
        isTrue,
      );
      expect(find.text('可用'), findsNWidgets(13));
      await tester.ensureVisible(find.text('Netflix'));
      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      expect(find.text('Proxy → Tokyo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'comparison picker can target a node without changing current routing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const UrlDiagnosticsView()));
      await tester.enterText(
        find.byKey(const ValueKey('diagnosticUrlInput')),
        'https://example.com',
      );
      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      final comparison = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(comparison);
      await tester.tap(comparison);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selected route: Tokyo').last);
      await tester.pumpAndSettle();
      final run = find.widgetWithText(FilledButton, 'Run diagnostics');
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(
        core.calls
            .where((call) => call.$1 == 'probe')
            .map((call) => (call.$2 as Map)['proxy-name']),
        ['', 'Tokyo'],
      );
      expect(core.calls.any((call) => call.$1 == 'changeProxy'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid URL and disconnected state never issue a test request', (
    tester,
  ) async {
    await tester.pumpWidget(app(const UrlDiagnosticsView()));
    await tester.enterText(
      find.byKey(const ValueKey('diagnosticUrlInput')),
      'example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Run diagnostics'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a complete HTTP or HTTPS URL without credentials.'),
      findsOneWidget,
    );
    expect(core.calls, isEmpty);
    core.status.value = CoreStatus.stopped;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Run diagnostics'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Connect the service from Overview before testing.'),
      findsOneWidget,
    );
  });
}
