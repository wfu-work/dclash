import 'dart:async';

import 'package:dclash_flutter/services/settings_service.dart';
import 'package:dclash_flutter/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> release(String version) => {
  'tag_name': 'v$version',
  'html_url': 'https://github.com/wfu-work/dclash/releases/tag/v$version',
  'body': 'Release notes',
};

void main() {
  late SettingsService settings;
  setUp(() async {
    settings = SettingsService(memoryOnly: true);
    await settings.initialize();
  });

  test('SemVer compares prerelease identifiers and ignores build metadata', () {
    const ordered = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
      '1.0.1',
      '1.1.0',
      '2.0.0',
    ];
    for (var i = 1; i < ordered.length; i++) {
      expect(
        AppVersion.tryParse(
          ordered[i],
        )!.compareTo(AppVersion.tryParse(ordered[i - 1])!),
        greaterThan(0),
      );
    }
    expect(
      AppVersion.tryParse(
        '1.0.0+build.7',
      )!.compareTo(AppVersion.tryParse('1.0.0')!),
      0,
    );
    for (final invalid in [
      '1.2',
      '01.2.3',
      '1.2.3-',
      '1.2.3-01',
      '1.2.3+a..b',
    ]) {
      expect(AppVersion.tryParse(invalid), isNull, reason: invalid);
    }
  });

  test('release links are limited to the matching project release', () {
    expect(AppRelease.parse(release('1.2.3')).version, '1.2.3');
    for (final url in [
      'http://github.com/wfu-work/dclash/releases/tag/v1.2.3',
      'https://github.com.evil.test/wfu-work/dclash/releases/tag/v1.2.3',
      'https://user:password@github.com/wfu-work/dclash/releases/tag/v1.2.3',
      'https://github.com:444/wfu-work/dclash/releases/tag/v1.2.3',
      'https://github.com/other/project/releases/tag/v1.2.3',
      'https://github.com/wfu-work/dclash/releases/../issues',
      'https://github.com/wfu-work/dclash/releases/tag/v9.9.9',
    ]) {
      expect(
        () => AppRelease.parse({...release('1.2.3'), 'html_url': url}),
        throwsFormatException,
        reason: url,
      );
    }
    expect(
      () => AppRelease.parse({...release('1.2.3'), 'draft': true}),
      throwsFormatException,
    );
  });

  test(
    'checks share requests, compare installed version and clear stale results',
    () async {
      var calls = 0;
      var payload = Completer<dynamic>();
      final service = UpdateService(
        settings,
        version: () async => '1.0.0',
        fetch: () {
          calls++;
          return payload.future;
        },
      );
      final first = service.check();
      final second = service.check();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(service.checking.value, isTrue);
      payload.complete(release('1.1.0'));
      await Future.wait([first, second]);
      expect(service.available, isTrue);
      expect(service.checkedAt.value, isNotNull);
      payload = Completer<dynamic>()..complete(release('1.0.0'));
      await service.check();
      expect(service.available, isFalse);
      payload = Completer<dynamic>()..complete(null);
      await service.check();
      expect(service.noRelease.value, isTrue);
      expect(service.release.value, isNull);
      payload = Completer<dynamic>();
      final failed = service.check();
      payload.completeError(StateError('offline'));
      await failed;
      expect(service.error.value, contains('offline'));
      expect(service.release.value, isNull);
      expect(service.checking.value, isFalse);
      service.onClose();
    },
  );

  testWidgets('automatic checks require opt-in and stop when disabled', (
    tester,
  ) async {
    final settings = SettingsService(memoryOnly: true);
    await settings.initialize();
    var calls = 0;
    final service = UpdateService(
      settings,
      version: () async => '1.0.0',
      fetch: () async {
        calls++;
        return release('1.1.0');
      },
    );
    service.initialize();
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 0);
    await settings.set('autoCheckUpdates', true);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(calls, 1);
    await settings.set('autoCheckUpdates', false);
    await tester.pump(const Duration(days: 2));
    expect(calls, 1);
    service.onClose();
  });

  test(
    'closing ignores an in-flight response and prevents further requests',
    () async {
      final pending = Completer<dynamic>();
      var calls = 0;
      final service = UpdateService(
        settings,
        version: () async => '1.0.0',
        fetch: () {
          calls++;
          return pending.future;
        },
      );
      final check = service.check();
      await Future<void>.delayed(Duration.zero);
      service.onClose();
      pending.complete(release('2.0.0'));
      await check;
      await service.check();
      expect(service.release.value, isNull);
      expect(calls, 1);
    },
  );
}
