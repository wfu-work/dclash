import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../../../domains/resource_item.dart';
import '../../../../utils/yaml_config.dart';

enum BuilderSection { proxies, groups, proxyProviders, ruleProviders, rules }

extension BuilderSectionConfig on BuilderSection {
  String get configKey => switch (this) {
    BuilderSection.proxies => 'proxies',
    BuilderSection.groups => 'proxy-groups',
    BuilderSection.proxyProviders => 'proxy-providers',
    BuilderSection.ruleProviders => 'rule-providers',
    BuilderSection.rules => 'rules',
  };
  bool get provider =>
      this == BuilderSection.proxyProviders ||
      this == BuilderSection.ruleProviders;
  String get labelKey => 'builderSection_$name';
}

class BuilderEntry {
  const BuilderEntry(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

/// Applies only edited leaf fields. Empty optional fields are represented by
/// null, while unrelated mappings and unsupported protocol options survive.
Map<String, dynamic> applyBuilderEdits(
  Map<String, dynamic> original,
  Map<String, dynamic> edits,
) {
  final result = _copy(original);
  for (final entry in edits.entries) {
    final path = entry.key.split('.');
    var current = result;
    for (final segment in path.take(path.length - 1)) {
      final value = current[segment];
      current[segment] = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      current = current[segment] as Map<String, dynamic>;
    }
    if (entry.value == null) {
      current.remove(path.last);
    } else {
      current[path.last] = entry.value;
    }
  }
  return result;
}

dynamic builderValue(Map<String, dynamic> data, String path) {
  dynamic value = data;
  for (final segment in path.split('.')) {
    if (value is! Map) return null;
    value = value[segment];
  }
  return value;
}

/// An entry can contain keys such as `proxies` that have a different shape
/// from the document's top-level sections. Wrap it before parsing so document
/// validation does not mistake a group's member names for node records.
Map<String, dynamic> parseBuilderEntryYaml(String content) {
  final value = parseConfig(
    'builder-entry:\n${content.split('\n').map((line) => '  $line').join('\n')}',
    label: 'Entry YAML',
  )['builder-entry'];
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Entry YAML must contain a mapping.');
  }
  return value;
}

class ProfileBuilderDraft {
  ProfileBuilderDraft._(this._config);
  factory ProfileBuilderDraft.parse(String content) =>
      ProfileBuilderDraft._(parseConfig(content));
  Map<String, dynamic> _config;
  static const proxyTypes = [
    'ss',
    'vmess',
    'vless',
    'trojan',
    'hysteria2',
    'socks5',
    'http',
  ];
  static const groupTypes = [
    'select',
    'url-test',
    'fallback',
    'load-balance',
    'relay',
  ];
  static const providerTypes = ['http', 'file', 'inline'];
  static const builtinPolicies = [
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
  ];

  List<BuilderEntry> entries(BuilderSection section) {
    final value = _config[section.configKey];
    if (section == BuilderSection.rules) return [];
    if (section.provider) {
      return (value as Map? ?? const {}).entries
          .map(
            (entry) => BuilderEntry(
              entry.key as String,
              _copy(Map<String, dynamic>.from(entry.value as Map)),
            ),
          )
          .toList();
    }
    return (value as List? ?? const []).map((item) {
      final record = Map<String, dynamic>.from(item as Map);
      return BuilderEntry(record['name'] as String, _copy(record));
    }).toList();
  }

  List<String> get rules =>
      List<String>.from(_config['rules'] as List? ?? const []);
  List<String> get policies => {
    ...builtinPolicies,
    ...names(BuilderSection.proxies),
    ...names(BuilderSection.groups),
  }.toList();
  List<String> names(BuilderSection section) {
    final value = _config[section.configKey];
    if (section.provider) {
      return (value as Map? ?? const {}).keys.cast<String>().toList();
    }
    return (value as List? ?? const [])
        .map((item) => (item as Map)['name'] as String)
        .toList();
  }

  int count(BuilderSection section) {
    final value = _config[section.configKey];
    return value is Map
        ? value.length
        : value is List
        ? value.length
        : 0;
  }

  String nextName(BuilderSection section, String prefix) {
    final existing = section.provider
        ? names(section).toSet()
        : policies.toSet();
    var candidate = prefix;
    for (var suffix = 2; existing.contains(candidate); suffix++) {
      candidate = '$prefix $suffix';
    }
    return candidate;
  }

  void saveEntry(
    BuilderSection section, {
    String? originalName,
    required String name,
    required Map<String, dynamic> data,
  }) {
    if (section == BuilderSection.rules) {
      throw const FormatException('Use the rule editor for rules.');
    }
    name = name.trim();
    _validateName(name);
    final records = entries(section);
    if (originalName != null &&
        !records.any((entry) => entry.name == originalName)) {
      throw const FormatException('The entry no longer exists.');
    }
    if (section.provider) {
      if (records.any(
        (entry) => entry.name == name && entry.name != originalName,
      )) {
        throw const FormatException('This provider name already exists.');
      }
    } else {
      if (builtinPolicies.contains(name) ||
          (name == 'GLOBAL' &&
              !(section == BuilderSection.groups && originalName == name))) {
        throw const FormatException('This name is reserved by the core.');
      }
      final otherSection = section == BuilderSection.proxies
          ? BuilderSection.groups
          : BuilderSection.proxies;
      if (records.any(
            (entry) => entry.name == name && entry.name != originalName,
          ) ||
          names(otherSection).contains(name)) {
        throw const FormatException('Proxy and group names must be unique.');
      }
    }
    final edited = _copy(data);
    if (!section.provider) edited['name'] = name;
    validateEntry(section, edited);
    final next = _copy(_config);
    if (section.provider) {
      final providers = Map<String, dynamic>.from(
        next[section.configKey] as Map? ?? {},
      );
      final result = <String, dynamic>{};
      var replaced = false;
      for (final entry in providers.entries) {
        if (entry.key == originalName) {
          result[name] = edited;
          replaced = true;
        } else {
          result[entry.key] = entry.value;
        }
      }
      if (!replaced) result[name] = edited;
      next[section.configKey] = result;
    } else {
      final list = List<dynamic>.from(next[section.configKey] as List? ?? []);
      final index = list.indexWhere(
        (item) => (item as Map)['name'] == originalName,
      );
      if (index < 0) {
        list.add(edited);
      } else {
        list[index] = edited;
      }
      next[section.configKey] = list;
    }
    if (originalName != null && originalName != name) {
      _renameReferences(next, section, originalName, name);
    }
    _validateGroupCycles(next);
    _config = next;
  }

  void removeEntry(BuilderSection section, String name) {
    final references = _references(section, name);
    if (references.isNotEmpty) {
      throw FormatException(
        '"$name" is still referenced by ${references.join(', ')}. Remove those references first.',
      );
    }
    if (section.provider) {
      final providers = Map<String, dynamic>.from(
        _config[section.configKey] as Map? ?? {},
      );
      providers.remove(name);
      _config[section.configKey] = providers;
    } else {
      _config[section.configKey] = (_config[section.configKey] as List? ?? [])
          .where((item) => (item as Map)['name'] != name)
          .toList();
    }
  }

  List<String> _references(BuilderSection section, String name) {
    final result = <String>[];
    for (final group in entries(BuilderSection.groups)) {
      if (section == BuilderSection.proxyProviders &&
          group.data['use'] is List &&
          (group.data['use'] as List).contains(name)) {
        result.add(group.name);
      }
      if (!section.provider &&
          group.data['proxies'] is List &&
          (group.data['proxies'] as List).contains(name)) {
        result.add(group.name);
      }
    }
    if (!section.provider) {
      for (final proxy in entries(BuilderSection.proxies)) {
        if (proxy.data['dialer-proxy'] == name) result.add(proxy.name);
      }
    }
    for (final (label, list) in _ruleLists(_config)) {
      for (var i = 0; i < list.length; i++) {
        var referenced = false;
        _mapRuleReferences(list[i] as String, section, (value) {
          if (value.trim() == name) referenced = true;
          return value;
        });
        if (referenced) result.add('$label ${i + 1}');
      }
    }
    return result.toSet().toList();
  }

  static void _renameReferences(
    Map<String, dynamic> config,
    BuilderSection section,
    String oldName,
    String name,
  ) {
    for (final group in config['proxy-groups'] as List? ?? const []) {
      final key = section == BuilderSection.proxyProviders
          ? 'use'
          : !section.provider
          ? 'proxies'
          : null;
      if (key != null && group[key] is List) {
        group[key] = (group[key] as List)
            .map((item) => item == oldName ? name : item)
            .toList();
      }
    }
    if (!section.provider) {
      for (final proxy in config['proxies'] as List? ?? const []) {
        if (proxy['dialer-proxy'] == oldName) proxy['dialer-proxy'] = name;
      }
    }
    for (final (_, list) in _ruleLists(config)) {
      for (var i = 0; i < list.length; i++) {
        list[i] = _mapRuleReferences(
          list[i] as String,
          section,
          (value) => value.trim() == oldName ? name : value,
        );
      }
    }
  }

  static Iterable<(String, List)> _ruleLists(
    Map<String, dynamic> config,
  ) sync* {
    if (config['rules'] is List) yield ('rule', config['rules'] as List);
    final subRules = config['sub-rules'];
    if (subRules is Map) {
      for (final entry in subRules.entries) {
        if (entry.value is List) {
          yield ('sub-rule ${entry.key}', entry.value as List);
        }
      }
    }
  }

  static String _mapRuleReferences(
    String raw,
    BuilderSection section,
    String Function(String) transform,
  ) {
    final parts = _ruleParts(raw);
    if (parts.length < 2) return raw;
    final type = parts.first.trim().toUpperCase();
    // Match the core's ParseRulePayload: ordinary targets precede parameters;
    // logical/regex targets are last, and SUB-RULE targets name rule branches.
    if (!section.provider && type != 'SUB-RULE') {
      final index = type == 'MATCH'
          ? 1
          : const {
              'AND',
              'OR',
              'NOT',
              'DOMAIN-REGEX',
              'PROCESS-NAME-REGEX',
              'PROCESS-PATH-REGEX',
            }.contains(type)
          ? parts.length - 1
          : 2;
      if (index < parts.length) parts[index] = transform(parts[index]);
    }
    if (section == BuilderSection.ruleProviders) {
      if (type == 'RULE-SET') parts[1] = transform(parts[1]);
      if (const {'AND', 'OR', 'NOT', 'SUB-RULE'}.contains(type)) {
        parts[1] = _mapRuleSetPredicate(parts[1], transform);
      }
    }
    return parts.join(',');
  }

  static String _mapRuleSetPredicate(
    String expression,
    String Function(String) transform, [
    int depth = 0,
  ]) {
    if (depth > 64) {
      throw const FormatException('Rule expression nesting is too deep.');
    }
    final value = expression.trim();
    final parts = _ruleParts(value);
    if (parts.length == 1 && value.startsWith('(') && value.endsWith(')')) {
      return '(${_mapRuleSetPredicate(value.substring(1, value.length - 1), transform, depth + 1)})';
    }
    final type = parts.first.trim().toUpperCase();
    if (type == 'RULE-SET' && parts.length > 1) {
      parts[1] = transform(parts[1]);
    } else if (const {'AND', 'OR', 'NOT'}.contains(type) && parts.length > 1) {
      parts[1] = _mapRuleSetPredicate(parts[1], transform, depth + 1);
    } else if (parts.first.trim().startsWith('(')) {
      for (var i = 0; i < parts.length; i++) {
        parts[i] = _mapRuleSetPredicate(parts[i], transform, depth + 1);
      }
    }
    return parts.join(',');
  }

  void saveRule(String rule, {int? index}) {
    rule = rule.trim();
    if (rule.isEmpty || rule.contains('\n') || rule.contains('\r')) {
      throw const FormatException('Enter one complete rule.');
    }
    final next = rules;
    if (index == null) {
      next.add(rule);
    } else {
      next[index] = rule;
    }
    _config['rules'] = next;
  }

  void removeRule(int index) {
    final next = rules..removeAt(index);
    _config['rules'] = next;
  }

  /// Imports proxy records from a resource while keeping the original record
  /// fields intact. Names are regenerated only when they collide with the
  /// current draft.
  void importProxyResource(String content) {
    final payload = _decodeResourcePayload(content);
    final records = _recordsFor(payload, 'proxies');
    if (records.isEmpty) {
      throw const FormatException('The proxy resource contains no proxies.');
    }
    for (final record in records) {
      final sourceName = record['name'];
      final prefix = sourceName is String && sourceName.trim().isNotEmpty
          ? sourceName.trim()
          : 'Imported proxy';
      final name = nextName(BuilderSection.proxies, prefix);
      saveEntry(
        BuilderSection.proxies,
        name: name,
        data: {...record, 'name': name},
      );
    }
  }

  /// Adds a provider entry backed by a reusable resource. URL resources remain
  /// remote providers; inline/file resources become validated inline payloads.
  void addProviderResource(
    BuilderSection section,
    ResourceItem item, {
    String? content,
  }) {
    if (!section.provider) {
      throw const FormatException('Choose a provider section first.');
    }
    final name = nextName(section, item.name);
    final path = 'providers/${_safeResourceName(name)}.yaml';
    final data = <String, dynamic>{
      'type': item.sourceType == ResourceSourceType.url ? 'http' : 'inline',
      'path': path,
    };
    if (item.sourceType == ResourceSourceType.url) {
      data['url'] = item.source;
      data['interval'] = section == BuilderSection.ruleProviders ? 86400 : 3600;
      if (section == BuilderSection.ruleProviders) {
        data.addAll({'behavior': 'domain', 'format': 'yaml'});
      }
    } else {
      final payload = _providerPayload(
        _decodeResourcePayload(content ?? item.source),
        section == BuilderSection.ruleProviders ? 'rules' : 'proxies',
      );
      if (payload.isEmpty) {
        throw const FormatException(
          'The provider resource contains no entries.',
        );
      }
      if (section == BuilderSection.proxyProviders &&
          payload.any((entry) => entry is! Map)) {
        throw const FormatException(
          'Proxy provider payload must contain objects.',
        );
      }
      if (section == BuilderSection.ruleProviders &&
          payload.any((entry) => entry is! String)) {
        throw const FormatException(
          'Rule provider payload must contain rules.',
        );
      }
      data['payload'] = payload;
      if (section == BuilderSection.ruleProviders) {
        data.addAll({'behavior': 'domain', 'format': 'yaml'});
      }
    }
    saveEntry(section, name: name, data: data);
  }

  /// Keeps only proxies matching at least one pattern in the resource.
  void applyRegexFilter(String content) {
    final patterns = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) => RegExp(line))
        .toList(growable: false);
    if (patterns.isEmpty) {
      throw const FormatException('The filter contains no patterns.');
    }
    final proxies = List<Map<String, dynamic>>.from(
      (_config['proxies'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final names = <String>{};
    final kept = <Map<String, dynamic>>[];
    for (final proxy in proxies) {
      final name = proxy['name'] as String? ?? '';
      if (patterns.any((pattern) => pattern.hasMatch(name))) {
        kept.add(proxy);
        names.add(name);
      }
    }
    if (kept.isEmpty) {
      throw const FormatException('The filter matches no proxy.');
    }
    final next = _copy(_config);
    next['proxies'] = kept;
    next['proxy-groups'] = [
      for (final item in next['proxy-groups'] as List? ?? const [])
        _filterGroup(Map<String, dynamic>.from(item as Map), names),
    ];
    _config = next;
  }

  /// Applies a YAML/JSON mapping of proxy or group names to icon URLs.
  void applyIconSet(String content) {
    final value = _decodeResourcePayload(content);
    if (value is! Map) {
      throw const FormatException('The icon set must contain a mapping.');
    }
    final icons = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.value as String).trim().isEmpty) {
        throw const FormatException('Icon mappings must contain text values.');
      }
      icons[entry.key as String] = (entry.value as String).trim();
    }
    if (icons.isEmpty) throw const FormatException('The icon set is empty.');
    final next = _copy(_config);
    for (final section in ['proxies', 'proxy-groups']) {
      for (final raw in next[section] as List? ?? const []) {
        final item = raw as Map<String, dynamic>;
        final icon = icons[item['name']];
        if (icon != null) item['icon'] = icon;
      }
    }
    _config = next;
  }

  static Map<String, dynamic> _filterGroup(
    Map<String, dynamic> group,
    Set<String> names,
  ) {
    if (group['proxies'] is List) {
      group['proxies'] = (group['proxies'] as List)
          .where(
            (item) =>
                item is String &&
                (names.contains(item) || builtinPolicies.contains(item)),
          )
          .toList();
    }
    return group;
  }

  static String _safeResourceName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '')
      .toLowerCase()
      .padLeft(1, 'r');

  static dynamic _decodeResourcePayload(String content) {
    try {
      return _plainYaml(loadYaml(content), 0, <Object>{});
    } on YamlException catch (error) {
      throw FormatException('Resource YAML is invalid: ${error.message}');
    }
  }

  static List<Map<String, dynamic>> _recordsFor(dynamic payload, String key) {
    final value = payload is Map && payload[key] is List
        ? payload[key]
        : payload;
    if (value is! List) {
      if (value is Map<String, dynamic>) return [value];
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) Map<String, dynamic>.from(item),
    ];
  }

  static List<dynamic> _providerPayload(dynamic payload, String key) {
    final value = payload is Map && payload[key] is List
        ? payload[key]
        : payload;
    return value is List ? List<dynamic>.from(value) : const [];
  }

  void move(BuilderSection section, int oldIndex, int newIndex) {
    final nextIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (section.provider) {
      final providers = Map<String, dynamic>.from(
        _config[section.configKey] as Map? ?? {},
      );
      final entries = providers.entries.toList();
      final item = entries.removeAt(oldIndex);
      entries.insert(nextIndex, item);
      _config[section.configKey] = Map<String, dynamic>.fromEntries(entries);
    } else {
      final list = List<dynamic>.from(
        _config[section.configKey] as List? ?? [],
      );
      final item = list.removeAt(oldIndex);
      list.insert(nextIndex, item);
      _config[section.configKey] = list;
    }
  }

  String toYaml() {
    validateConfig(_config);
    _validateGroupCycles(_config);
    return encodeYaml(_config);
  }

  static void _validateName(String name) {
    if (name.isEmpty ||
        name.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException(
        'Enter a name without control characters (up to 256 characters).',
      );
    }
  }

  static void validateEntry(BuilderSection section, Map<String, dynamic> data) {
    final type = data['type'];
    if (type is! String || type.trim().isEmpty) {
      throw const FormatException('An entry requires a type.');
    }
    if (section == BuilderSection.proxies && proxyTypes.contains(type)) {
      if (data['server'] is! String ||
          (data['server'] as String).trim().isEmpty) {
        throw const FormatException('Enter a proxy server.');
      }
      final port = data['port'];
      if (port is! int || port < 1 || port > 65535) {
        throw const FormatException('Port must be between 1 and 65535.');
      }
      final credential = ['vmess', 'vless'].contains(type)
          ? 'uuid'
          : ['ss', 'trojan', 'hysteria2'].contains(type)
          ? 'password'
          : null;
      if (credential != null &&
          (data[credential] is! String ||
              (data[credential] as String).isEmpty) &&
          !(type == 'ss' && data['cipher'] == 'none')) {
        throw FormatException('Enter the proxy $credential.');
      }
      if (type == 'ss' &&
          (data['cipher'] is! String || (data['cipher'] as String).isEmpty)) {
        throw const FormatException('Choose a Shadowsocks cipher.');
      }
    }
    if (section == BuilderSection.groups && groupTypes.contains(type)) {
      for (final key in ['proxies', 'use']) {
        if (data[key] != null &&
            (data[key] is! List ||
                !(data[key] as List).every((item) => item is String))) {
          throw FormatException('Group $key must contain names.');
        }
      }
      if ((data['proxies'] as List? ?? []).isEmpty &&
          (data['use'] as List? ?? []).isEmpty &&
          ![
            'include-all',
            'include-all-proxies',
            'include-all-providers',
          ].any((key) => data[key] == true)) {
        throw const FormatException(
          'Choose at least one member or proxy provider.',
        );
      }
      if (['url-test', 'fallback', 'load-balance'].contains(type)) {
        _httpUrl(data['url'], 'Test URL');
        final interval = data['interval'];
        if (interval != null && (interval is! int || interval < 1)) {
          throw const FormatException(
            'Test interval must be a positive whole number.',
          );
        }
      }
    }
    if (section.provider && providerTypes.contains(type)) {
      if (type == 'http') _httpUrl(data['url'], 'Provider URL');
      if (data['interval'] != null &&
          (data['interval'] is! int || (data['interval'] as int) < 1)) {
        throw const FormatException(
          'Provider interval must be a positive whole number.',
        );
      }
      if (type != 'inline') {
        final path = data['path'];
        if (path is! String ||
            path.isEmpty ||
            path.startsWith('/') ||
            path.contains('\\') ||
            path.split('/').contains('..') ||
            Uri.tryParse(path)?.hasScheme == true ||
            RegExp(r'^[A-Za-z]:').hasMatch(path)) {
          throw const FormatException(
            'Provider path must stay inside the profile provider directory.',
          );
        }
      } else if (data['payload'] is! List) {
        throw const FormatException(
          'Inline providers require a payload list; edit it in advanced YAML.',
        );
      }
      if (section == BuilderSection.ruleProviders) {
        if (!['domain', 'ipcidr', 'classical'].contains(data['behavior'])) {
          throw const FormatException('Choose a rule provider behavior.');
        }
        if (data['format'] != null &&
            !['yaml', 'text', 'mrs'].contains(data['format'])) {
          throw const FormatException('Unsupported rule provider format.');
        }
        if (data['format'] == 'mrs' && data['behavior'] == 'classical') {
          throw const FormatException(
            'MRS format supports domain or ipcidr behavior.',
          );
        }
      }
      if (section == BuilderSection.proxyProviders &&
          data['health-check'] is Map) {
        final health = data['health-check'] as Map;
        if (health['enable'] == true) {
          _httpUrl(health['url'], 'Health-check URL');
        }
        if (health['interval'] != null &&
            (health['interval'] is! int || (health['interval'] as int) < 1)) {
          throw const FormatException(
            'Health-check interval must be a positive whole number.',
          );
        }
      }
    }
  }

  static void _httpUrl(dynamic value, String label) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw FormatException('$label must be a valid HTTP or HTTPS URL.');
    }
  }

  static void _validateGroupCycles(Map<String, dynamic> config) {
    final groups = <String, List<String>>{};
    for (final group in config['proxy-groups'] as List? ?? const []) {
      if (group['proxies'] != null &&
          (group['proxies'] is! List ||
              !(group['proxies'] as List).every((value) => value is String))) {
        throw const FormatException('Group proxies must contain names.');
      }
      groups[group['name'] as String] = group['proxies'] is List
          ? List<String>.from(group['proxies'] as List)
          : [];
    }
    final visiting = <String>{}, visited = <String>{};
    void visit(String name) {
      if (visited.contains(name) || !groups.containsKey(name)) return;
      if (!visiting.add(name)) {
        throw FormatException(
          'Proxy groups contain a circular reference at "$name".',
        );
      }
      for (final child in groups[name]!) {
        visit(child);
      }
      visiting.remove(name);
      visited.add(name);
    }

    for (final name in groups.keys) {
      visit(name);
    }
  }
}

const builderRuleTypes = [
  'DOMAIN',
  'DOMAIN-SUFFIX',
  'DOMAIN-KEYWORD',
  'DOMAIN-REGEX',
  'GEOSITE',
  'IP-CIDR',
  'IP-CIDR6',
  'GEOIP',
  'SRC-IP-CIDR',
  'DST-PORT',
  'SRC-PORT',
  'NETWORK',
  'PROCESS-NAME',
  'PROCESS-PATH',
  'RULE-SET',
  'MATCH',
];

class BuilderRule {
  const BuilderRule({
    required this.type,
    required this.payload,
    required this.policy,
    this.noResolve = false,
    this.raw,
  });
  factory BuilderRule.parse(String raw) {
    final parts = _ruleParts(raw).map((value) => value.trim()).toList();
    final noResolve = parts.isNotEmpty && parts.last == 'no-resolve';
    final body = noResolve ? parts.take(parts.length - 1).toList() : parts;
    if (body.isNotEmpty &&
        builderRuleTypes.contains(body.first) &&
        body.length == (body.first == 'MATCH' ? 2 : 3)) {
      return BuilderRule(
        type: body.first,
        payload: body.first == 'MATCH' ? '' : body[1],
        policy: body.last,
        noResolve: noResolve,
      );
    }
    return BuilderRule(
      type: parts.isEmpty ? '' : parts.first,
      payload: '',
      policy: '',
      raw: raw,
    );
  }
  final String type, payload, policy;
  final bool noResolve;
  final String? raw;
  bool get structured => raw == null;
  String toRule() {
    if (raw != null) return raw!;
    if (!builderRuleTypes.contains(type) ||
        policy.trim().isEmpty ||
        policy.contains(',') ||
        (type != 'MATCH' &&
            (payload.trim().isEmpty || payload.contains(','))) ||
        RegExp(r'[\r\n]').hasMatch('$payload$policy')) {
      throw const FormatException(
        'Complete the rule fields; complex expressions can be edited as raw rules.',
      );
    }
    return [
      type,
      if (type != 'MATCH') payload.trim(),
      policy.trim(),
      if (noResolve) 'no-resolve',
    ].join(',');
  }
}

List<String> _ruleParts(String value) {
  final result = <String>[];
  var depth = 0, start = 0;
  String? quote;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      result.add(value.substring(start, i));
      start = i + 1;
    }
  }
  result.add(value.substring(start));
  return result;
}

dynamic _plainYaml(dynamic value, int depth, Set<Object> ancestors) {
  if (depth > 64) throw const FormatException('Resource YAML is too deep.');
  if (value is Map || value is List) {
    if (!ancestors.add(value as Object)) {
      throw const FormatException('Resource YAML contains a recursive alias.');
    }
    try {
      if (value is Map) {
        final map = <String, dynamic>{};
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw const FormatException('Resource YAML keys must be strings.');
          }
          map[entry.key as String] = _plainYaml(
            entry.value,
            depth + 1,
            ancestors,
          );
        }
        return map;
      }
      return [
        for (final item in value as List)
          _plainYaml(item, depth + 1, ancestors),
      ];
    } finally {
      ancestors.remove(value);
    }
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Unsupported value in resource YAML.');
}
