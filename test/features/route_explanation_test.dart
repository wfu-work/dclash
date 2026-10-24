import 'package:dclash_flutter/app/pages/tools/route_explanation_controller.dart';
import 'package:dclash_flutter/app/pages/tools/route_explanation_view.dart';
import 'package:dclash_flutter/app/pages/tools/network_diagnostics_view.dart';
import 'package:dclash_flutter/app/pages/tools/tools_view.dart';
import 'package:dclash_flutter/configs/localization/app_translations.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/diagnostic_core.dart';

class _ExplainCore extends DiagnosticCore {
  _ExplainCore(super.profiles, super.settings);
  bool stale = false;
  bool ipDependent = false;

  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    calls.add((method, arguments));
    if (method == 'watchRoute') return Map<String, dynamic>.from(nativeRoute);
    if (method == 'explainRoute') {
      final data = arguments as Map;
      return {
        ...nativeRoute,
        'url': data['url'],
        'host': 'www.example.com',
        'port': 443,
        'rule': ipDependent ? '' : 'DomainSuffix',
        'rule-payload': ipDependent ? '' : 'example.com',
        'route': ipDependent ? 'DIRECT' : 'Proxy',
        'selected': ipDependent ? '' : 'Tokyo',
        'final': ipDependent ? 'DIRECT' : 'Tokyo',
        'needs-dns': ipDependent,
        'exact': !ipDependent,
        if (stale) 'picks-version': 2,
      };
    }
    return super.invoke(method, arguments);
  }
}

void main() {
  late _ExplainCore core;
  late RouteExplanationController controller;

  setUp(() async {
    Get.testMode = true;
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    core = _ExplainCore(ProfileService(), settings)
      ..status.value = CoreStatus.running
      ..routeState.assignAll({
        'core-epoch': 1,
        'picks-version': 1,
        'picks': {'Proxy': 'Tokyo'},
      });
    controller = RouteExplanationController(core)..onInit();
  });
  tearDown(() {
    controller.onClose();
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

  test(
    'explains static route without invoking a probe or changing selection',
    () async {
      await controller.explain('https://www.example.com/path?private=value');
      final result = controller.result.value!;
      expect(result.matchedRule, 'DomainSuffix,example.com');
      expect(result.route, 'Proxy');
      expect(result.selected, 'Tokyo');
      expect(result.finalOutbound, 'Tokyo');
      expect(result.exact, isTrue);
      expect(core.calls.map((call) => call.$1), ['watchRoute', 'explainRoute']);
      expect(core.nativeRoute['picks'], isEmpty);
    },
  );

  test(
    'marks IP-dependent explanations as estimates and rejects invalid URLs',
    () async {
      core.ipDependent = true;
      await controller.explain('https://example.com');
      expect(controller.result.value?.needsDns, isTrue);
      expect(controller.result.value?.exact, isFalse);
      await controller.explain('https://user:secret@example.com');
      expect(controller.error.value, 'diagnosticInvalidUrl');
      expect(
        core.calls.where((call) => call.$1 == 'explainRoute'),
        hasLength(1),
      );
    },
  );

  test(
    'stale route result is discarded and disconnected core avoids RPC',
    () async {
      core.stale = true;
      await controller.explain('https://example.com');
      expect(controller.result.value, isNull);
      expect(controller.notice.value, 'routeExplainChanged');
      core.stale = false;
      core.status.value = CoreStatus.stopped;
      await controller.explain('https://example.com');
      expect(controller.error.value, 'diagnosticConnectFirst');
      expect(
        core.calls.where((call) => call.$1 == 'explainRoute'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'tool entry explains first and opens real URL diagnostics only on action',
    (tester) async {
      Get.put<CoreService>(core);
      await tester.pumpWidget(app(const ToolsView()));
      final routeExplanation = find.byKey(
        const ValueKey('toolsRouteExplainCard'),
      );
      await tester.ensureVisible(routeExplanation);
      await tester.tap(routeExplanation);
      await tester.pumpAndSettle();
      expect(find.byType(RouteExplanationView), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'probe'), isEmpty);
      final explain = find.byKey(const ValueKey('routeExplainRun'));
      await tester.ensureVisible(explain);
      await tester.tap(explain);
      await tester.pumpAndSettle();
      expect(find.text('DomainSuffix,example.com'), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'probe'), isEmpty);
      final diagnose = find.byKey(const ValueKey('routeExplainDiagnose'));
      await tester.ensureVisible(diagnose);
      await tester.tap(diagnose);
      await tester.pumpAndSettle();
      expect(find.byType(UrlDiagnosticsView), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'probe'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 768), const Size(1200, 900)]) {
    testWidgets('route explanation fits $size in both themes and languages', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final chinese in [false, true]) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            app(
              RouteExplanationView(core: core),
              dark: dark,
              chinese: chinese,
              scale: 1.5,
            ),
          );
          final explain = find.byKey(const ValueKey('routeExplainRun'));
          await tester.ensureVisible(explain);
          await tester.tap(explain);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('routeExplainDiagnose')),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  }
}
