import 'dart:convert';

const maxScriptBytes = 1024 * 1024;
const maxScriptLibraryBytes = 16 * maxScriptBytes;

Uri validateScriptUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Use an HTTPS script URL without credentials.');
  }
  return uri.replace(fragment: '');
}

void validateScriptContent(String content) {
  if (content.trim().isEmpty) {
    throw const FormatException('Script content cannot be empty.');
  }
  if (content.length > maxScriptBytes ||
      utf8.encode(content).length > maxScriptBytes) {
    throw const FormatException('Scripts must be at most 1 MiB.');
  }
}

class LibraryScript {
  LibraryScript({
    required this.id,
    required this.name,
    required this.content,
    this.enabled = false,
    this.url,
    this.updatedAt,
    Map<String, dynamic> extra = const {},
  }) : extra = Map.unmodifiable(extra) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid script identifier.');
    }
    if (name.trim().isEmpty || name.length > 256) {
      throw const FormatException(
        'Script names must contain 1 to 256 characters.',
      );
    }
    validateScriptContent(content);
    if (url != null) validateScriptUrl(url!);
    if (updatedAt != null &&
        (updatedAt! < 0 || updatedAt! > 8640000000000000)) {
      throw const FormatException('Invalid script update time.');
    }
  }

  final String id, name, content;
  final bool enabled;
  final String? url;
  final int? updatedAt;
  final Map<String, dynamic> extra;
  bool get remote => url != null;

  factory LibraryScript.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['content'] is! String ||
        value['enabled'] is! bool ||
        (value['url'] != null && value['url'] is! String) ||
        (value['updatedAt'] != null && value['updatedAt'] is! int)) {
      throw const FormatException('Invalid script entry.');
    }
    return LibraryScript(
      id: value['id'] as String,
      name: value['name'] as String,
      content: value['content'] as String,
      enabled: value['enabled'] as bool,
      url: value['url'] as String?,
      updatedAt: value['updatedAt'] as int?,
      extra: Map<String, dynamic>.from(value)
        ..removeWhere((key, _) => _knownKeys.contains(key)),
    );
  }

  static const _knownKeys = {
    'id',
    'name',
    'content',
    'enabled',
    'url',
    'updatedAt',
  };

  LibraryScript copyWith({
    String? name,
    String? content,
    bool? enabled,
    int? updatedAt,
  }) => LibraryScript(
    id: id,
    name: name ?? this.name,
    content: content ?? this.content,
    enabled: enabled ?? this.enabled,
    url: url,
    updatedAt: updatedAt ?? this.updatedAt,
    extra: extra,
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'content': content,
    'enabled': enabled,
    if (url != null) 'url': url,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };
}

class ScriptLibrary {
  ScriptLibrary({
    List<LibraryScript> scripts = const [],
    Map<String, dynamic> extra = const {},
  }) : scripts = List.unmodifiable(scripts),
       extra = Map.unmodifiable(extra) {
    if (scripts.length > 100 ||
        scripts.map((item) => item.id).toSet().length != scripts.length) {
      throw const FormatException(
        'Script library has too many or duplicate entries.',
      );
    }
  }

  final List<LibraryScript> scripts;
  final Map<String, dynamic> extra;

  factory ScriptLibrary.decode(String raw) {
    if (raw.trim().isEmpty) return ScriptLibrary();
    if (raw.length > maxScriptLibraryBytes ||
        utf8.encode(raw).length > maxScriptLibraryBytes) {
      throw const FormatException('Script library exceeds 16 MiB.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] is! int ||
        decoded['version'] != 1 ||
        decoded['scripts'] is! List) {
      throw const FormatException(
        'Invalid or unsupported script library format.',
      );
    }
    return ScriptLibrary(
      scripts: (decoded['scripts'] as List)
          .map(LibraryScript.fromJson)
          .toList(),
      extra: Map<String, dynamic>.from(decoded)
        ..remove('version')
        ..remove('scripts'),
    );
  }

  ScriptLibrary withScripts(List<LibraryScript> next) =>
      ScriptLibrary(scripts: next, extra: extra);

  String encode() {
    final encoded = jsonEncode({
      ...extra,
      'version': 1,
      'scripts': scripts.map((item) => item.toJson()).toList(),
    });
    if (utf8.encode(encoded).length > maxScriptLibraryBytes) {
      throw const FormatException('Script library exceeds 16 MiB.');
    }
    return encoded;
  }
}
