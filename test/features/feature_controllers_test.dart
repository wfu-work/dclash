import 'package:dclash_flutter/app/pages/connections/connections_controller.dart';
import 'package:dclash_flutter/app/pages/connections/feed_controller.dart';
import 'package:dclash_flutter/app/pages/logs/logs_controller.dart';
import 'package:dclash_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:dclash_flutter/app/pages/proxies/proxies_controller.dart';
import 'package:dclash_flutter/domains/clash_connection.dart';
import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:dclash_flutter/domains/core_status.dart';
import 'package:dclash_flutter/domains/proxy_group.dart';
import 'package:dclash_flutter/services/core_service.dart';
import 'package:dclash_flutter/services/profile_service.dart';
import 'package:dclash_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingCore extends CoreService {
  RecordingCore(super.profiles, super.settings);
  final calls = <String>[];
  bool failDelay = false;
  @override
  Future<void> selectProxy(String group, String name) async =>
      calls.add('select:$group:$name');
  @override
  Future<int?> testDelay(String name) async {
    if (failDelay) throw StateError('Delay failed');
    calls.add('test:$name');
    delays[name] = 42;
    return 42;
  }

  @override
  Future<void> closeConnection(String id) async => calls.add('close:$id');
  @override
  Future<void> closeAll() async => calls.add('closeAll');
  @override
  Future<void> reload() async => calls.add('reload');
  @override
  Future<void> stop() async {
    calls.add('stop');
    status.value = CoreStatus.stopped;
  }
}

class RecordingProfiles extends ProfileService {
  final calls = <String>[];
  @override
  Future<void> activate(String id) async {
    calls.add('activate:$id');
    activeId.value = id;
  }

  @override
  Future<void> remove(String id) async => calls.add('remove:$id');
  @override
  Future<void> refresh(String id) async => calls.add('refresh:$id');
}

void main() {
  late SettingsService settings;
  late RecordingProfiles profiles;
  late RecordingCore core;
  setUp(() async {
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    profiles = RecordingProfiles();
    core = RecordingCore(profiles, settings);
  });

  test(
    'proxy filtering keeps unknown delays last and forwards selections',
    () async {
      const nodes = [
        ProxyNode(name: 'Unknown', type: 'VLESS'),
        ProxyNode(name: 'Fast', type: 'SS', delay: 25),
        ProxyNode(name: 'Offline', type: 'SS', delay: -1, alive: false),
      ];
      core.groups.add(
        const ProxyGroup(
          name: 'Proxy',
          type: 'Selector',
          selected: 'Fast',
          nodes: nodes,
        ),
      );
      final controller = ProxiesController(core, settings);
      await controller.setSort('delay');
      expect(controller.visibleNodes.map((node) => node.name), [
        'Fast',
        'Unknown',
        'Offline',
      ]);
      await controller.setHideUnavailable(true);
      expect(controller.visibleNodes.map((node) => node.name), [
        'Fast',
        'Unknown',
      ]);
      controller.query.value = 'vless';
      expect(controller.visibleNodes.single.name, 'Unknown');
      await controller.select(nodes.first);
      expect(core.calls, contains('select:Proxy:Unknown'));
      core.failDelay = true;
      await expectLater(controller.test(nodes.first), throwsStateError);
      expect(controller.testing, isEmpty);
    },
  );

  test(
    'proxy group tools test one group and remember its collapsed state',
    () async {
      core.status.value = CoreStatus.running;
      const group = ProxyGroup(
        name: 'Proxy',
        type: 'Selector',
        selected: 'Tokyo',
        nodes: [
          ProxyNode(name: 'Tokyo', type: 'VLESS'),
          ProxyNode(name: 'Seoul', type: 'SS'),
        ],
      );
      core.groups.add(group);
      final controller = ProxiesController(core, settings);

      expect(controller.isExpanded(group), isTrue);
      controller.toggleGroup(group);
      expect(controller.isExpanded(group), isFalse);
      controller.toggleGroup(group);
      await controller.testGroup(group);

      expect(core.calls, containsAll(['test:Tokyo', 'test:Seoul']));
      expect(controller.testingGroups, isEmpty);
    },
  );

  test(
    'active profile edits reload and removing it stops the service',
    () async {
      const profile = ClashProfile(
        id: 'profile',
        name: 'My profile',
        source: ProfileSource.remote,
        path: '/profile.yaml',
        url: 'https://example.com/config',
      );
      profiles.profiles.add(profile);
      profiles.activeId.value = profile.id;
      core.status.value = CoreStatus.running;
      final controller = ProfilesController(profiles, core);
      await controller.refreshProfile(profile);
      expect(profiles.calls, ['refresh:profile']);
      expect(core.calls, ['reload']);
      await controller.remove(profile);
      expect(core.calls.last, 'stop');
      expect(profiles.calls.last, 'remove:profile');
      expect(controller.busy, isEmpty);
    },
  );

  test(
    'connection filtering includes process and sends close commands',
    () async {
      core.connections.add(
        ClashConnection(
          id: 'one',
          host: 'example.com',
          network: 'tcp',
          source: '127.0.0.1',
          destination: '1.1.1.1',
          rule: 'MATCH',
          chains: ['Proxy'],
          upload: 100,
          download: 200,
          startedAt: DateTime(2026),
          process: 'Browser',
        ),
      );
      final controller = ConnectionsController(core);
      controller.query.value = 'browser';
      expect(controller.visibleConnections.single.id, 'one');
      await controller.closeConnection('one');
      await controller.closeAll();
      expect(core.calls, ['close:one', 'closeAll']);
      expect(controller.closing, isEmpty);
    },
  );

  test('logs pause freezes records while filters and export keep working', () {
    core.logs.add(
      CoreLog(level: 'info', message: 'first', time: DateTime(2026)),
    );
    final controller = LogsController(core);
    controller.togglePause();
    core.logs.add(
      CoreLog(level: 'error', message: 'second', time: DateTime(2026)),
    );
    expect(controller.visibleLogs.map((log) => log.message), ['first']);
    controller.togglePause();
    controller.level.value = 'error';
    expect(controller.visibleLogs.single.message, 'second');
    expect(controller.exportText, contains('[ERROR] second'));
    controller.clear();
    expect(core.logs, isEmpty);
  });

  test('DNS feed freezes while paused and searches all record fields', () {
    core.dnsQueries.add({
      'name': 'example.com',
      'answers': ['1.1.1.1'],
    });
    final controller = FeedController(core, dns: true);
    controller.togglePause();
    core.dnsQueries.add({'name': 'other.example'});
    expect(controller.visibleRecords, hasLength(1));
    controller.query.value = '1.1.1.1';
    expect(controller.visibleRecords.single['name'], 'example.com');
    controller.clear();
    expect(core.dnsQueries, isEmpty);
    expect(controller.visibleRecords, isEmpty);
  });

  test(
    'request summaries read core tracker metadata and DNS skips empty answers',
    () {
      final request = <String, dynamic>{
        'id': 'request-1',
        'rule': 'DomainSuffix',
        'metadata': {
          'host': 'example.com',
          'network': 'tcp',
          'destinationIP': '1.1.1.1',
        },
      };
      expect(
        FeedController.value(request, ['host', 'destinationIP']),
        'example.com',
      );
      expect(FeedController.value(request, ['network']), 'tcp');
      expect(
        FeedController.value(
          {'answers': [], 'upstream': 'https://dns.example'},
          ['answers', 'upstream'],
        ),
        'https://dns.example',
      );
    },
  );
}
