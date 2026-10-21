import 'standard_extension.dart';

enum ProfileSource { remote, local, custom }

class ClashProfile {
  static const Object _unset = Object();

  const ClashProfile({
    required this.id,
    required this.name,
    required this.source,
    required this.path,
    this.url = '',
    this.updatedAt,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expiresAt,
    this.autoUpdateHours = 24,
    this.script = '',
    this.sharedScriptIds,
    this.standardRules = const [],
    this.matchTarget,
  });
  final String id, name, path, url, script;
  final ProfileSource source;
  final DateTime? updatedAt, expiresAt;
  final int upload, download, total, autoUpdateHours;
  final List<String>? sharedScriptIds;
  final List<String> standardRules;
  final String? matchTarget;
  int get used => upload + download;
  ClashProfile copyWith({
    String? name,
    String? url,
    DateTime? updatedAt,
    int? upload,
    int? download,
    int? total,
    DateTime? expiresAt,
    int? autoUpdateHours,
    String? script,
    Object? sharedScriptIds = _unset,
    Object? standardRules = _unset,
    Object? matchTarget = _unset,
  }) => ClashProfile(
    id: id,
    name: name ?? this.name,
    source: source,
    path: path,
    url: url ?? this.url,
    updatedAt: updatedAt ?? this.updatedAt,
    upload: upload ?? this.upload,
    download: download ?? this.download,
    total: total ?? this.total,
    expiresAt: expiresAt ?? this.expiresAt,
    autoUpdateHours: autoUpdateHours ?? this.autoUpdateHours,
    script: script ?? this.script,
    sharedScriptIds: identical(sharedScriptIds, _unset)
        ? this.sharedScriptIds
        : _normalizeSharedScriptIds(sharedScriptIds as List<String>?),
    standardRules: identical(standardRules, _unset)
        ? this.standardRules
        : normalizeStandardRules(standardRules as Iterable<String>),
    matchTarget: identical(matchTarget, _unset)
        ? this.matchTarget
        : _normalizeMatchTarget(matchTarget as String?),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source.name,
    'path': path,
    'url': url,
    'updatedAt': updatedAt?.toIso8601String(),
    'upload': upload,
    'download': download,
    'total': total,
    'expiresAt': expiresAt?.toIso8601String(),
    'autoUpdateHours': autoUpdateHours,
    'script': script,
    if (sharedScriptIds != null) 'sharedScriptIds': sharedScriptIds,
    if (standardRules.isNotEmpty) 'standardRules': standardRules,
    if (matchTarget != null && matchTarget!.isNotEmpty)
      'matchTarget': matchTarget,
  };
  factory ClashProfile.fromJson(Map<String, dynamic> json) {
    final rawSelection = json['sharedScriptIds'];
    if (rawSelection != null && rawSelection is! List) {
      throw const FormatException('Invalid shared script selection.');
    }
    final rawRules = json['standardRules'];
    if (rawRules != null &&
        (rawRules is! List || rawRules.any((item) => item is! String))) {
      throw const FormatException('Invalid standard extension rules.');
    }
    final matchTarget = json['matchTarget'] as String?;
    validateMatchTarget(matchTarget);
    return ClashProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      source: ProfileSource.values.byName(json['source'] as String),
      path: json['path'] as String,
      url: json['url'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      autoUpdateHours: (json['autoUpdateHours'] as num?)?.toInt() ?? 24,
      script: json['script'] as String? ?? '',
      sharedScriptIds: rawSelection == null
          ? null
          : _decodeSharedScriptIds(rawSelection),
      standardRules: rawRules == null
          ? const []
          : normalizeStandardRules(List<String>.from(rawRules)),
      matchTarget: _normalizeMatchTarget(matchTarget),
    );
  }

  static List<String> _validateSharedScriptIds(List<String> ids) {
    if (ids.toSet().length != ids.length ||
        ids.any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id))) {
      throw const FormatException('Invalid shared script selection.');
    }
    return List<String>.from(ids);
  }

  static List<String>? _normalizeSharedScriptIds(List<String>? ids) =>
      ids == null ? null : List.unmodifiable(_validateSharedScriptIds(ids));

  static String? _normalizeMatchTarget(String? value) {
    final normalized = value?.trim();
    validateMatchTarget(normalized);
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static List<String> _decodeSharedScriptIds(dynamic value) {
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('Invalid shared script selection.');
    }
    return _normalizeSharedScriptIds(List<String>.from(value))!;
  }
}
