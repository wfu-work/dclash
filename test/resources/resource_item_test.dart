import 'package:dclash_flutter/domains/resource_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips fields and preserves unknown fields', () {
    final item = ResourceItem.fromJson({
      'id': 'r1',
      'name': 'Rules',
      'kind': 'ruleProvider',
      'sourceType': 'inline',
      'source': 'rules: []',
      'enabled': true,
      'order': 2,
      'createdAt': '2026-10-21T00:00:00Z',
      'updatedAt': '2026-10-21T00:00:00Z',
      'future': {'x': 1},
    });
    expect(item.extra['future'], {'x': 1});
    expect(ResourceItem.fromJson(item.toJson()).id, 'r1');
    expect(ResourceEnvelope(items: [item]).encode(), contains('future'));
  });

  test('rejects invalid URLs and regular expressions', () {
    final item = ResourceItem(
      id: 'bad-url',
      name: 'Bad URL',
      kind: ResourceKind.ruleProvider,
      sourceType: ResourceSourceType.url,
      source: 'ftp://example.invalid/rules.yaml',
      content: null,
      enabled: true,
      order: 0,
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
    );
    expect(item.validate, throwsFormatException);
    expect(() => validateRegexContent('[', 'filter'), throwsFormatException);
  });

  test('validates duplicate names by kind and allows different kinds', () {
    ResourceItem item(String id, ResourceKind kind, String name) =>
        ResourceItem(
          id: id,
          name: name,
          kind: kind,
          sourceType: ResourceSourceType.inline,
          source: kind == ResourceKind.regexFilter ? 'example' : '{}',
          content: null,
          enabled: true,
          order: 0,
          createdAt: DateTime.utc(2026, 10, 21),
          updatedAt: DateTime.utc(2026, 10, 21),
        );
    final first = item('a', ResourceKind.iconSet, 'Shared');
    final second = item('b', ResourceKind.iconSet, 'shared');
    final third = item('c', ResourceKind.proxy, 'Shared');
    expect(
      () => ResourceEnvelope.validateItems([first, second]),
      throwsFormatException,
    );
    expect(
      () => ResourceEnvelope.validateItems([first, third]),
      returnsNormally,
    );
  });

  test('decodes empty and rejects unsupported envelopes', () {
    expect(ResourceEnvelope.decode('').items, isEmpty);
    expect(
      () => ResourceEnvelope.decode('{"version":2,"items":[]}'),
      throwsFormatException,
    );
  });
}
