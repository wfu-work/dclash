import 'package:dclash_flutter/domains/clash_profile.dart';
import 'package:flutter_test/flutter_test.dart';

ClashProfile profile({
  List<String>? sharedScriptIds,
  List<String> standardRules = const [],
  String? matchTarget,
}) => ClashProfile(
  id: 'profile',
  name: 'Profile',
  source: ProfileSource.custom,
  path: '/tmp/profile.yaml',
  sharedScriptIds: sharedScriptIds,
  standardRules: standardRules,
  matchTarget: matchTarget,
);

void main() {
  test(
    'selected shared script IDs round trip and legacy profiles stay implicit',
    () {
      final selected = profile(sharedScriptIds: ['second', 'first']);
      final restored = ClashProfile.fromJson(selected.toJson());
      expect(restored.sharedScriptIds, ['second', 'first']);

      final legacy = ClashProfile.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'source': 'custom',
        'path': '/tmp/legacy.yaml',
      });
      expect(legacy.sharedScriptIds, isNull);
    },
  );

  test('profile rejects malformed shared script selections', () {
    final base = profile().toJson();
    expect(
      () => ClashProfile.fromJson({
        ...base,
        'sharedScriptIds': ['bad id'],
      }),
      throwsFormatException,
    );
    expect(
      () => ClashProfile.fromJson({
        ...base,
        'sharedScriptIds': ['same', 'same'],
      }),
      throwsFormatException,
    );
  });

  test(
    'standard extension fields round trip and legacy profiles stay empty',
    () {
      final selected = profile(
        standardRules: const ['DOMAIN-SUFFIX,ads.example,REJECT'],
        matchTarget: 'Proxy',
      );
      final restored = ClashProfile.fromJson(selected.toJson());
      expect(restored.standardRules, ['DOMAIN-SUFFIX,ads.example,REJECT']);
      expect(restored.matchTarget, 'Proxy');

      final legacy = ClashProfile.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'source': 'custom',
        'path': '/tmp/legacy.yaml',
      });
      expect(legacy.standardRules, isEmpty);
      expect(legacy.matchTarget, isNull);
    },
  );

  test('profile rejects malformed standard extension rules', () {
    final base = profile().toJson();
    expect(
      () => ClashProfile.fromJson({
        ...base,
        'standardRules': ['not a rule'],
      }),
      throwsFormatException,
    );
    expect(
      () => ClashProfile.fromJson({...base, 'matchTarget': 'Proxy\nOther'}),
      throwsFormatException,
    );
  });

  test('profile accepts nested and regex standard rules', () {
    final selected = profile(
      standardRules: const [
        'AND,((DOMAIN-SUFFIX,ads.example),(NETWORK,udp)),REJECT',
        r'PROCESS-NAME-REGEX,(?i)^curl,.*$,DIRECT',
      ],
    );
    expect(ClashProfile.fromJson(selected.toJson()).standardRules, [
      'AND,((DOMAIN-SUFFIX,ads.example),(NETWORK,udp)),REJECT',
      r'PROCESS-NAME-REGEX,(?i)^curl,.*$,DIRECT',
    ]);
  });
}
