const standardRuleTypes = {
  'DOMAIN',
  'DOMAIN-SUFFIX',
  'DOMAIN-KEYWORD',
  'DOMAIN-WILDCARD',
  'DOMAIN-REGEX',
  'GEOSITE',
  'IP-CIDR',
  'IP-CIDR6',
  'IP-SUFFIX',
  'IP-ASN',
  'GEOIP',
  'SRC-GEOIP',
  'SRC-IP-ASN',
  'SRC-IP-CIDR',
  'SRC-IP-SUFFIX',
  'DST-PORT',
  'SRC-PORT',
  'IN-PORT',
  'IN-TYPE',
  'IN-USER',
  'IN-NAME',
  'REMATCH-NAME',
  'NETWORK',
  'PROCESS-NAME',
  'PROCESS-NAME-REGEX',
  'PROCESS-NAME-WILDCARD',
  'PROCESS-PATH',
  'PROCESS-PATH-REGEX',
  'PROCESS-PATH-WILDCARD',
  'UID',
  'DSCP',
  'RULE-SET',
  'SUB-RULE',
  'AND',
  'OR',
  'NOT',
  'MATCH',
};

const _nestedRuleTypes = {'AND', 'OR', 'NOT', 'SUB-RULE'};
const _commaPayloadRuleTypes = {
  'AND',
  'OR',
  'NOT',
  'SUB-RULE',
  'DOMAIN-REGEX',
  'PROCESS-NAME-REGEX',
  'PROCESS-PATH-REGEX',
};

class StandardRulePreset {
  const StandardRulePreset({
    required this.id,
    required this.labelKey,
    required this.rules,
  });

  final String id, labelKey;
  final List<String> rules;
}

const standardRulePresets = [
  StandardRulePreset(
    id: 'lanDirect',
    labelKey: 'profileRulePresetLan',
    rules: [
      'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
      'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
    ],
  ),
  StandardRulePreset(
    id: 'localhostDirect',
    labelKey: 'profileRulePresetLocalhost',
    rules: ['IP-CIDR,127.0.0.0/8,DIRECT,no-resolve'],
  ),
  StandardRulePreset(
    id: 'matchPlaceholder',
    labelKey: 'profileRulePresetMatch',
    rules: ['MATCH,MATCH'],
  ),
];

List<String> normalizeStandardRules(Iterable<String> values) {
  final result = <String>[];
  for (final raw in values) {
    final rule = raw.trim();
    if (rule.isEmpty) continue;
    _validateRule(rule);
    result.add(rule);
  }
  if (result.length > 500) {
    throw const FormatException('A profile can contain at most 500 rules.');
  }
  return List.unmodifiable(result);
}

void validateMatchTarget(String? value) {
  if (value == null || value.trim().isEmpty) return;
  if (value.contains(RegExp(r'[\r\n,]')) || value.trim().length > 256) {
    throw const FormatException('MATCH-TARGET must be a single policy name.');
  }
}

void _validateRule(String rule) {
  if (rule.contains(RegExp(r'[\r\n]'))) {
    throw const FormatException(
      'Profile rules must contain one rule per line.',
    );
  }
  final parts = rule.split(',').map((part) => part.trim()).toList();
  if (parts.isEmpty || !standardRuleTypes.contains(parts.first)) {
    throw const FormatException('Unsupported profile rule type.');
  }
  if (parts.first == 'MATCH') {
    if (parts.length != 2 || parts[1].isEmpty) {
      throw const FormatException('Invalid profile rule format.');
    }
    return;
  }
  if (parts.length < 3 || parts.any((part) => part.isEmpty)) {
    throw const FormatException('Invalid profile rule format.');
  }
  if (_nestedRuleTypes.contains(parts.first)) return;
  final noResolve = parts.last == 'no-resolve';
  final body = noResolve ? parts.sublist(0, parts.length - 1) : parts;
  if (body.length < 3 ||
      (body.length != 3 && !_commaPayloadRuleTypes.contains(parts.first))) {
    throw const FormatException('Invalid profile rule option.');
  }
  if (noResolve &&
      !{
        'IP-CIDR',
        'IP-CIDR6',
        'IP-SUFFIX',
        'IP-ASN',
        'GEOIP',
        'SRC-IP-CIDR',
        'RULE-SET',
      }.contains(parts.first)) {
    throw const FormatException('This rule type does not support no-resolve.');
  }
}
