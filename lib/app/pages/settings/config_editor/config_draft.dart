import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../../../utils/yaml_config.dart';

/// A complete override document. Field edits change only the addressed leaf.
class ConfigDraft {
  ConfigDraft(this.values);
  final Map<String, dynamic> values;

  factory ConfigDraft.parse(String source) {
    if (source.trim().isEmpty) return ConfigDraft({});
    if (utf8.encode(source).length > 16 * 1024 * 1024) {
      throw const FormatException('Override exceeds the 16 MiB limit.');
    }
    final parsed = loadYaml(source);
    if (parsed is YamlMap && parsed.isEmpty) return ConfigDraft({});
    return ConfigDraft(parseMapping(source, 'Override'));
  }

  dynamic read(List<String> path) {
    dynamic current = values;
    for (final key in path) {
      if (current is! Map || !current.containsKey(key)) return null;
      current = current[key];
    }
    return current;
  }

  bool contains(List<String> path) {
    dynamic current = values;
    for (var index = 0; index < path.length; index++) {
      if (current is! Map || !current.containsKey(path[index])) return false;
      if (index == path.length - 1) return true;
      current = current[path[index]];
    }
    return false;
  }

  void write(List<String> path, dynamic value) {
    var current = values;
    for (final key in path.take(path.length - 1)) {
      final existing = current[key];
      if (existing != null && existing is! Map) {
        throw FormatException(
          '"$key" must be a mapping. Edit the YAML to change its structure.',
        );
      }
      final child = existing == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(existing as Map);
      current[key] = child;
      current = child;
    }
    current[path.last] = value;
  }

  void remove(List<String> path) {
    void prune(Map<String, dynamic> current, int index) {
      final key = path[index];
      if (index == path.length - 1) {
        current.remove(key);
        return;
      }
      final value = current[key];
      if (value is! Map<String, dynamic>) return;
      prune(value, index + 1);
      if (value.isEmpty) current.remove(key);
    }

    prune(values, 0);
  }

  String encode() => values.isEmpty ? '' : encodeYaml(values);
}
