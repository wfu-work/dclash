import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:rust_api/rust_api.dart';

import '../domains/script_library.dart';
import '../domains/standard_extension.dart';
import '../storage/atomic_file.dart';
import '../utils/yaml_config.dart';

typedef ConfigScriptEvaluator =
    Future<String> Function({required String script, required String config});

class ConfigBuilder {
  static final String _sessionSecret = randomIdentifier();
  static String get sessionSecret => _sessionSecret;

  static Future<String> build(
    String content,
    Map<String, dynamic> fields, {
    String script = '',
    Iterable<String>? sharedScriptIds,
    Iterable<String>? profileRules,
    String? matchTarget,
    ConfigScriptEvaluator? scriptEvaluator,
  }) async {
    final normalizedProfileRules = normalizeStandardRules(
      profileRules ?? const <String>[],
    );
    validateMatchTarget(matchTarget);
    var config = await compute(parseConfig, content);
    final library = ScriptLibrary.decode(fields['scripts'] as String? ?? '');
    final selectedIds = sharedScriptIds?.toSet();
    final selected = [
      for (final item in library.scripts)
        if (item.enabled &&
            (selectedIds == null || selectedIds.contains(item.id)))
          (name: 'Shared script "${item.name}"', code: item.content),
      if (script.trim().isNotEmpty) (name: 'Profile script', code: script),
    ];
    if (selected.isNotEmpty && scriptEvaluator == null) {
      await ensureRustLibInitialized();
    }
    final evaluate = scriptEvaluator ?? evaluateScript;
    for (final item in selected) {
      try {
        final result = jsonDecode(
          await evaluate(
            script: item.code,
            config: await compute(jsonEncode, config),
          ),
        );
        if (result is! Map<String, dynamic>) {
          throw const FormatException(
            'Script must return a configuration object.',
          );
        }
        config = await compute(parseConfig, jsonEncode(result));
      } catch (e) {
        throw FormatException('${item.name} failed: $e');
      }
    }
    return compute(_applyManagedSettings, {
      'config': config,
      'fields': {
        'controllerSecret': _sessionSecret,
        ...fields,
        'profileRules': normalizedProfileRules,
        'matchTarget': matchTarget,
      },
    });
  }

  static String _applyManagedSettings(Map<String, dynamic> request) {
    final config = request['config'] as Map<String, dynamic>;
    final fields = request['fields'] as Map<String, dynamic>;
    for (final entry in {
      'dns': 'dnsOverride',
      'tun': 'tunOverride',
      'sniffer': 'snifferOverride',
      'ntp': 'ntpOverride',
    }.entries) {
      final text = fields[entry.value] as String? ?? '';
      if (text.trim().isNotEmpty) {
        config[entry.key] = _mergeMappings(
          config[entry.key] as Map<String, dynamic>? ?? {},
          parseMapping(text, '${entry.key} override'),
        );
      }
    }
    final hosts = fields['hosts'] as String? ?? '';
    if (hosts.trim().isNotEmpty) {
      config['hosts'] = {
        ...?config['hosts'] as Map<String, dynamic>?,
        ...parseMapping(hosts, 'Hosts'),
      };
    }
    final rulesText = fields['addedRules'] as String? ?? '';
    final profileRules = (fields['profileRules'] as List?)
        ?.whereType<String>()
        .toList(growable: false);
    final normalizedRules = <String>[
      ...?profileRules?.map(
        (rule) => _replaceMatchTarget(rule, fields['matchTarget'] as String?),
      ),
    ];
    if (rulesText.trim().isNotEmpty) {
      final parsed = parseConfig(
        'rules:\n${rulesText.split('\n').map((line) => '  $line').join('\n')}',
        label: 'Added rules',
      );
      final addedRules = (parsed['rules'] as List)
          .map(
            (rule) =>
                _replaceMatchTarget('$rule', fields['matchTarget'] as String?),
          )
          .toList(growable: false);
      config['rules'] = [
        ...normalizedRules,
        ...addedRules,
        ...?config['rules'] as List?,
      ];
    } else if (normalizedRules.isNotEmpty) {
      config['rules'] = [...normalizedRules, ...?config['rules'] as List?];
    }
    final mode = fields['mode'] ?? 'rule';
    if (!['rule', 'global', 'direct'].contains(mode)) {
      throw const FormatException('Invalid proxy mode.');
    }
    final port = _port(fields['mixedPort'] ?? 7890, 'Mixed port');
    final controllerPort = _port(
      fields['controllerPort'] ?? 19090,
      'Controller port',
    );
    for (final key in [
      'external-controller',
      'external-controller-tls',
      'external-controller-unix',
      'external-controller-pipe',
      'external-ui',
      'external-ui-url',
      'external-ui-name',
      'secret',
    ]) {
      config.remove(key);
    }
    config.addAll({
      'mode': mode,
      'mixed-port': port,
      'port': 0,
      'socks-port': 0,
      'redir-port': 0,
      'tproxy-port': 0,
      'allow-lan': fields['allowLan'] == true,
      'ipv6': fields['ipv6'] == true,
      'log-level': fields['logLevel'] ?? 'info',
      'unified-delay': fields['unifiedDelay'] ?? true,
      'tcp-concurrent': fields['tcpConcurrent'] ?? true,
    });
    if (fields['controllerEnabled'] == true) {
      config['external-controller'] = '127.0.0.1:$controllerPort';
      config['secret'] =
          (fields['controllerSecret'] is String &&
              (fields['controllerSecret'] as String).isNotEmpty)
          ? fields['controllerSecret']
          : _sessionSecret;
    }
    config['tun'] = {
      ...?config['tun'] as Map<String, dynamic>?,
      'enable': fields['tunEnabled'] == true,
      'stack': fields['stack'] ?? 'mixed',
    };
    if ((config['tun'] as Map)['enable'] == true) {
      (config['tun'] as Map).putIfAbsent('auto-route', () => true);
      (config['tun'] as Map).putIfAbsent('auto-detect-interface', () => true);
      (config['tun'] as Map).putIfAbsent('dns-hijack', () => ['any:53']);
      final dns = <String, dynamic>{
        'enhanced-mode': 'fake-ip',
        'fake-ip-range': '198.18.0.1/16',
        ...?config['dns'] as Map<String, dynamic>?,
        'enable': true,
      };
      if (dns['nameserver'] == null ||
          (dns['nameserver'] is List && (dns['nameserver'] as List).isEmpty)) {
        dns['nameserver'] = [
          'https://1.1.1.1/dns-query',
          'https://dns.alidns.com/dns-query',
        ];
      }
      config['dns'] = dns;
    }
    final root = fields['providerDirectory'] as String? ?? 'providers';
    for (final group in ['proxy-providers', 'rule-providers']) {
      final providers = config[group] as Map<String, dynamic>?;
      if (providers == null) continue;
      for (final entry in providers.entries) {
        final provider = entry.value as Map<String, dynamic>;
        final path = provider['path'];
        if (path != null && (path is! String || _unsafePath(path))) {
          throw FormatException(
            'Provider "${entry.key}" has an unsafe file path.',
          );
        }
        final filename = path is String
            ? path
            : '${sha256.convert(utf8.encode('$group:${entry.key}')).toString().substring(0, 24)}.yaml';
        provider['path'] = p.join(root, filename.replaceAll('\\', '/'));
      }
    }
    validateConfig(config);
    return encodeYaml(config);
  }

  static Map<String, dynamic> _mergeMappings(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final entry in override.entries) {
      final previous = result[entry.key];
      result[entry.key] =
          previous is Map<String, dynamic> &&
              entry.value is Map<String, dynamic>
          ? _mergeMappings(previous, entry.value as Map<String, dynamic>)
          : entry.value;
    }
    return result;
  }

  static bool _unsafePath(String path) =>
      path.isEmpty ||
      path.contains('\\') ||
      p.posix.isAbsolute(path) ||
      RegExp(r'^[A-Za-z]:').hasMatch(path) ||
      path.split('/').contains('..') ||
      Uri.tryParse(path)?.hasScheme == true;

  static String _replaceMatchTarget(String rule, String? matchTarget) {
    if (matchTarget == null || matchTarget.trim().isEmpty) return rule;
    final parts = rule.split(',');
    if (parts.length == 2 &&
        parts.first.trim() == 'MATCH' &&
        parts.last.trim() == 'MATCH') {
      return 'MATCH,${matchTarget.trim()}';
    }
    return rule;
  }

  static int _port(dynamic value, String label) {
    if (value is! int || value < 1 || value > 65535) {
      throw FormatException('$label must be between 1 and 65535.');
    }
    return value;
  }
}
