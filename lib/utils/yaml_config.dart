import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Parses bounded, string-keyed YAML and reports errors suitable for the editor.
Map<String, dynamic> parseConfig(
  String content, {
  String label = 'Configuration',
}) {
  if (utf8.encode(content).length > 16 * 1024 * 1024) {
    throw FormatException('$label exceeds the 16 MiB limit.');
  }
  try {
    final value = _plain(loadYaml(content), 0, <Object>{});
    if (value is! Map<String, dynamic> || value.isEmpty) {
      throw FormatException('$label must contain a YAML mapping.');
    }
    validateConfig(value, label: label);
    return value;
  } on YamlException catch (e) {
    throw FormatException(
      '$label: ${e.message} ${e.span?.start.line == null ? '' : '(line ${e.span!.start.line + 1})'}',
    );
  }
}

dynamic _plain(dynamic value, int depth, Set<Object> ancestors) {
  if (depth > 64) {
    throw const FormatException('YAML nesting exceeds 64 levels.');
  }
  if (value is Map || value is List) {
    if (!ancestors.add(value as Object)) {
      throw const FormatException('Recursive YAML aliases are not supported.');
    }
    try {
      if (value is Map) {
        final map = <String, dynamic>{};
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw const FormatException('YAML keys must be strings.');
          }
          map[entry.key as String] = _plain(entry.value, depth + 1, ancestors);
        }
        return map;
      }
      return (value as List)
          .map((v) => _plain(v, depth + 1, ancestors))
          .toList();
    } finally {
      ancestors.remove(value);
    }
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Unsupported YAML value.');
}

void validateConfig(
  Map<String, dynamic> config, {
  String label = 'Configuration',
}) {
  for (final key in ['proxies', 'proxy-groups', 'rules', 'listeners']) {
    final value = config[key];
    if (value != null && value is! List) {
      throw FormatException('$label: "$key" must be a list.');
    }
  }
  for (final key in [
    'proxy-providers',
    'rule-providers',
    'dns',
    'tun',
    'sniffer',
    'ntp',
    'hosts',
    'profile',
  ]) {
    final value = config[key];
    if (value != null && value is! Map) {
      throw FormatException('$label: "$key" must be a mapping.');
    }
  }
  for (final key in ['proxies', 'proxy-groups']) {
    for (final value in config[key] as List? ?? const []) {
      if (value is! Map ||
          value['name'] is! String ||
          value['type'] is! String) {
        throw FormatException(
          '$label: every "$key" item requires a name and type.',
        );
      }
    }
  }
  for (final rule in config['rules'] as List? ?? const []) {
    if (rule is! String) {
      throw FormatException('$label: rules must be strings.');
    }
  }
  for (final key in ['proxy-providers', 'rule-providers']) {
    for (final entry in (config[key] as Map? ?? const {}).entries) {
      if (entry.value is! Map) {
        throw FormatException(
          '$label: provider "${entry.key}" must be a mapping.',
        );
      }
    }
  }
}

Map<String, dynamic> parseMapping(String text, String label) {
  if (text.trim().isEmpty) return {};
  return parseConfig(text, label: label);
}

/// JSON is a YAML 1.2 subset and avoids ambiguous scalars and unsafe tags.
String encodeYaml(Map<String, dynamic> value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';
