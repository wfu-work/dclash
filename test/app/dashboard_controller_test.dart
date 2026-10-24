import 'dart:async';

import 'package:dclash_flutter/app/pages/dashboard/dashboard_controller.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeCore extends CoreService {
  _ProbeCore(super.profiles, super.settings);
  Completer<dynamic> response = Completer<dynamic>();
  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) => response.future;
}

void main() {
  test(
    'outbound and service results from a previous route are discarded',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      final profiles = ProfileService();
      final core = _ProbeCore(profiles, settings)
        ..status.value = CoreStatus.running;
      final controller = DashboardController(core, profiles, settings)
        ..onInit();
      addTearDown(controller.onClose);

      final detection = controller.detectIp();
      core.groups.add(
        const ProxyGroup(
          name: 'Proxy',
          type: 'Selector',
          selected: 'New route',
          nodes: [],
        ),
      );
      core.response.complete({'body': '{"ip":"1.1.1.1"}'});
      await detection;
      expect(controller.outboundIp.value, isEmpty);
      expect(controller.outboundDetectedAt.value, isNull);
      expect(controller.outboundError.value, isNull);
      expect(controller.checking.value, false);

      core.response = Completer<dynamic>();
      final checks = controller.checkServices();
      core.status.value = CoreStatus.stopped;
      core.response.complete([
        {'name': 'google', 'status': 'ok', 'delay': 20},
      ]);
      await checks;
      expect(controller.serviceChecks, isEmpty);
    },
  );

  test(
    'invalid probe bodies remain visible as errors rather than an IP',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      final profiles = ProfileService();
      final core = _ProbeCore(profiles, settings)
        ..status.value = CoreStatus.running;
      final controller = DashboardController(core, profiles, settings)
        ..onInit();
      addTearDown(controller.onClose);
      core.response.complete({'body': '<html>rate limited</html>'});
      await expectLater(controller.detectIp(), throwsStateError);
      expect(controller.outboundIp.value, isEmpty);
      expect(controller.outboundError.value, isStateError);
      expect(controller.outboundDetectedAt.value, isNull);
      expect(controller.checking.value, false);

      core.response = Completer<dynamic>();
      final retry = controller.detectIp();
      expect(controller.outboundError.value, isNull);
      expect(controller.checking.value, true);
      core.response.complete({'body': '{"ip":"1.1.1.1"}'});
      await retry;
      expect(controller.outboundIp.value, '1.1.1.1');
      expect(controller.outboundDetectedAt.value, isNotNull);
      expect(controller.checking.value, false);

      core.status.value = CoreStatus.stopped;
      expect(controller.outboundIp.value, isEmpty);
      expect(controller.outboundDetectedAt.value, isNull);
      expect(controller.outboundError.value, isNull);
    },
  );

  test(
    'a stale failure cannot replace or finish a newer outbound check',
    () async {
      final settings = SettingsService(memoryOnly: true);
      await settings.initialize();
      final profiles = ProfileService();
      final core = _ProbeCore(profiles, settings)
        ..status.value = CoreStatus.running;
      final controller = DashboardController(core, profiles, settings)
        ..onInit();
      addTearDown(controller.onClose);
      final oldResponse = core.response;
      final oldCheck = controller.detectIp();
      await settings.set('mode', 'direct');
      core.response = Completer<dynamic>();
      final newCheck = controller.detectIp();
      oldResponse.completeError(StateError('old route timed out'));
      await oldCheck;
      expect(controller.checking.value, true);
      expect(controller.outboundError.value, isNull);
      core.response.complete({'body': '203.0.113.8'});
      await newCheck;
      expect(controller.outboundIp.value, '203.0.113.8');
      expect(controller.checking.value, false);
    },
  );
}
