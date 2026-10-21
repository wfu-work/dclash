import 'dart:convert';

import 'package:yaml/yaml.dart';

enum ResourceKind { proxy, ruleProvider, regexFilter, iconSet }

extension ResourceKindWire on ResourceKind {
  String get wireName => switch (this) {
    ResourceKind.proxy => 'proxy',
    ResourceKind.ruleProvider => 'ruleProvider',
    ResourceKind.regexFilter => 'regexFilter',
    ResourceKind.iconSet => 'iconSet',
  };

  String get label => switch (this) {
    ResourceKind.proxy => 'Proxy resources',
    ResourceKind.ruleProvider => 'Rule sets',
    ResourceKind.regexFilter => 'Regex filters',
    ResourceKind.iconSet => 'Icon sets',
  };

  static ResourceKind parse(Object? value) => switch (value) {
    'proxy' => ResourceKind.proxy,
    'ruleProvider' => ResourceKind.ruleProvider,
    'regexFilter' => ResourceKind.regexFilter,
    'iconSet' => ResourceKind.iconSet,
    _ => throw FormatException('Unsupported resource type: $value'),
  };
}

enum ResourceSourceType { url, file, inline }

extension ResourceSourceTypeWire on ResourceSourceType {
  String get wireName => name;

  static ResourceSourceType parse(Object? value) => switch (value) {
    'url' => ResourceSourceType.url,
    'file' => ResourceSourceType.file,
    'inline' => ResourceSourceType.inline,
    _ => throw FormatException('Unsupported resource source: $value'),
  };
}

const _resourceLimit = 16 * 1024 * 1024;

/// Validates newline-delimited regular expressions without retaining a
/// compiled RegExp in the persisted model.
void validateRegexContent(String content, String label) {
  final patterns = content
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'));
  if (patterns.isEmpty) {
    throw FormatException('$label must contain at least one pattern.');
  }
  for (final pattern in patterns) {
    try {
      RegExp(pattern);
    } on FormatException {
      throw FormatException('$label contains an invalid pattern.');
    }
  }
}

/// A serializable, user-owned resource. `source` is the URL/path, or the
/// inline payload when [sourceType] is inline. `content` is a validated cache
/// for URL/file resources and is intentionally optional.
class ResourceItem {
  ResourceItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.sourceType,
    required this.source,
    required this.content,
    required this.enabled,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    Map<String, dynamic> extra = const {},
  }) : extra = _copyMap(extra);

  factory ResourceItem.fromJson(Map<String, dynamic> input) {
    final data = Map<String, dynamic>.from(input);
    final id = data.remove('id');
    final name = data.remove('name');
    final kind = data.remove('kind');
    final sourceType = data.remove('sourceType');
    final source = data.remove('source');
    final content = data.remove('content');
    final enabled = data.remove('enabled');
    final order = data.remove('order');
    final createdAt = data.remove('createdAt');
    final updatedAt = data.remove('updatedAt');
    if (id is! String ||
        name is! String ||
        source is! String ||
        enabled is! bool ||
        order is! int ||
        createdAt is! String ||
        updatedAt is! String ||
        (content != null && content is! String)) {
      throw const FormatException('Invalid resource fields.');
    }
    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (created == null || updated == null) {
      throw const FormatException('Resource timestamps are invalid.');
    }
    return ResourceItem(
      id: id,
      name: name,
      kind: ResourceKindWire.parse(kind),
      sourceType: ResourceSourceTypeWire.parse(sourceType),
      source: source,
      content: content as String?,
      enabled: enabled,
      order: order,
      createdAt: created.toUtc(),
      updatedAt: updated.toUtc(),
      extra: data,
    );
  }

  final String id;
  final String name;
  final ResourceKind kind;
  final ResourceSourceType sourceType;
  final String source;
  final String? content;
  final bool enabled;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> extra;

  ResourceItem copyWith({
    String? id,
    String? name,
    ResourceKind? kind,
    ResourceSourceType? sourceType,
    String? source,
    String? content,
    bool? enabled,
    int? order,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? extra,
  }) => ResourceItem(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    sourceType: sourceType ?? this.sourceType,
    source: source ?? this.source,
    content: content ?? this.content,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    extra: extra ?? this.extra,
  );

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    'id': id,
    'name': name,
    'kind': kind.wireName,
    'sourceType': sourceType.wireName,
    'source': source,
    if (content != null) 'content': content,
    'enabled': enabled,
    'order': order,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  void validate() {
    if (id.trim().isEmpty || id.length > 128 || !_safeIdentifier.hasMatch(id)) {
      throw const FormatException('Resource id is invalid.');
    }
    if (name.trim().isEmpty || name.length > 128 || _hasControl(name)) {
      throw const FormatException('Resource name is invalid.');
    }
    if (order < 0) throw const FormatException('Resource order is invalid.');
    if (source.trim().isEmpty || source.length > _resourceLimit) {
      throw const FormatException('Resource source is empty or too large.');
    }
    if (sourceType == ResourceSourceType.url) {
      final uri = Uri.tryParse(source.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Resource URL must use HTTP or HTTPS.');
      }
    } else if (sourceType == ResourceSourceType.file &&
        (source.contains('\u0000') || source.trim().isEmpty)) {
      throw const FormatException('Resource file path is invalid.');
    }
    if (content != null && utf8.encode(content!).length > _resourceLimit) {
      throw const FormatException('Resource content is too large.');
    }
    final payload = sourceType == ResourceSourceType.inline ? source : content;
    if (sourceType == ResourceSourceType.inline && payload!.trim().isEmpty) {
      throw const FormatException('Inline resource content is empty.');
    }
    if (payload != null && payload.trim().isNotEmpty) {
      _validatePayload(kind, payload, name);
    }
  }
}

class ResourceEnvelope {
  ResourceEnvelope({required this.items, Map<String, dynamic> extra = const {}})
    : extra = _copyMap(extra);

  factory ResourceEnvelope.decode(String encoded) {
    if (encoded.trim().isEmpty) return ResourceEnvelope(items: const []);
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Resource library must be an object.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final version = map.remove('version');
    final items = map.remove('items');
    if (version != 1 || items is! List) {
      throw const FormatException('Unsupported resource library version.');
    }
    final parsed = <ResourceItem>[];
    for (final item in items) {
      if (item is! Map) {
        throw const FormatException('Resource entries must be objects.');
      }
      final resource = ResourceItem.fromJson(Map<String, dynamic>.from(item));
      resource.validate();
      parsed.add(resource);
    }
    _validateUniqueNames(parsed);
    return ResourceEnvelope(items: parsed, extra: map);
  }

  final List<ResourceItem> items;
  final Map<String, dynamic> extra;

  String encode() => jsonEncode({
    ..._copyMap(extra),
    'version': 1,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  });

  static void validateItems(Iterable<ResourceItem> items) {
    final list = items.toList(growable: false);
    for (final item in list) {
      item.validate();
    }
    _validateUniqueNames(list);
  }

  static void _validateUniqueNames(List<ResourceItem> items) {
    final seen = <String>{};
    for (final item in items) {
      final key =
          '${item.kind.wireName}\u0000${item.name.trim().toLowerCase()}';
      if (!seen.add(key)) {
        throw FormatException('Duplicate resource name: ${item.name}');
      }
    }
  }
}

final _safeIdentifier = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool _hasControl(String value) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

Map<String, dynamic> _copyMap(Map<String, dynamic> input) =>
    (jsonDecode(jsonEncode(input)) as Map).cast<String, dynamic>();

void _validatePayload(ResourceKind kind, String content, String label) {
  if (kind == ResourceKind.regexFilter) {
    validateRegexContent(content, label);
    return;
  }
  dynamic value;
  try {
    value = loadYaml(content);
  } on YamlException catch (error) {
    throw FormatException('$label contains invalid YAML: ${error.message}');
  }
  if (value == null || (value is! Map && value is! List)) {
    throw FormatException('$label must contain a YAML object or list.');
  }
  if (kind == ResourceKind.iconSet && value is! Map) {
    throw FormatException('$label must contain an icon mapping.');
  }
}
