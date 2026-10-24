import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domains/clash_profile.dart';
import '../repositories/profile_repository.dart';
import '../storage/atomic_file.dart';
import '../utils/bounded_http.dart';
import '../utils/yaml_config.dart';

class ProfileService extends GetxService {
  ProfileService({this._directory});
  Directory? _directory;
  Directory get directory => _directory!;
  late ProfileRepository _repository;
  final profiles = <ClashProfile>[].obs;
  final activeId = RxnString();
  final updating = <String>{}.obs;
  final error = RxnString();
  ClashProfile? get active =>
      profiles.firstWhereOrNull((profile) => profile.id == activeId.value);
  Future<void> _pending = Future.value();
  Timer? _refreshTimer;
  final updateFailure = Rxn<ProfileUpdateFailure>();

  Future<void> initialize() async {
    _directory ??= await getApplicationSupportDirectory();
    _repository = ProfileRepository(_directory!);
    final state = await _repository.read();
    profiles.assignAll(state.profiles);
    activeId.value = state.activeId;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refreshDue(),
    );
  }

  void _refreshDue() {
    final now = DateTime.now();
    for (final profile in profiles.toList()) {
      if (profile.source == ProfileSource.remote &&
          profile.autoUpdateHours > 0 &&
          !updating.contains(profile.id) &&
          (profile.updatedAt == null ||
              now.difference(profile.updatedAt!).inHours >=
                  profile.autoUpdateHours)) {
        // Errors remain visible through [error]; timer callbacks must not produce
        // unhandled futures after the UI has gone away.
        unawaited(refresh(profile.id).catchError((Object _) {}));
      }
    }
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      try {
        final value = await operation();
        error.value = null;
        return value;
      } catch (e) {
        error.value = _message(e);
        rethrow;
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ClashProfile> importUrl(
    String url, {
    String? name,
  }) => _mutate(() async {
    var uri = Uri.tryParse(url.trim());
    if (uri == null) throw const FormatException('Invalid subscription URL.');
    if (['clash', 'flclash', 'cloudrift'].contains(uri.scheme)) {
      if (uri.host != 'install-config' || uri.queryParameters['url'] == null) {
        throw const FormatException('Unsupported profile import link.');
      }
      name ??= uri.queryParameters['name'];
      uri = Uri.tryParse(uri.queryParameters['url']!);
      if (uri == null) {
        throw const FormatException('Import link contains an invalid URL.');
      }
    }
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      return _save(
        name: name ?? p.basenameWithoutExtension(file.path),
        content: await _readFile(file),
        source: ProfileSource.local,
      );
    }
    uri = validateHttpUri(uri.toString());
    final canonical = uri.toString();
    final existing = profiles.firstWhereOrNull(
      (profile) =>
          profile.source == ProfileSource.remote && profile.url == canonical,
    );
    return _download(uri, existing: existing, name: name);
  });

  Future<ClashProfile?> importFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml', 'json'],
    );
    if (selection == null) return null;
    final path = selection.files.single.path;
    if (path == null) {
      throw const FileSystemException('The selected file cannot be read.');
    }
    return _mutate(
      () async => _save(
        name: p.basenameWithoutExtension(path),
        content: await _readFile(File(path)),
        source: ProfileSource.local,
      ),
    );
  }

  Future<ClashProfile> saveContent({
    String? id,
    required String name,
    required String content,
  }) => _mutate(() => _save(id: id, name: name, content: content));

  Future<ClashProfile> _save({
    String? id,
    required String name,
    required String content,
    ProfileSource source = ProfileSource.custom,
    String url = '',
    String? script,
    List<String>? sharedScriptIds,
    List<String>? standardRules,
    String? matchTarget,
    Map<String, String> headers = const {},
  }) async {
    await compute(_validateContent, content);
    final existing = id == null ? null : _find(id);
    final profileId = id ?? randomIdentifier();
    final path = await _repository.stage(profileId, content);
    final stats = _subscriptionInfo(headers['subscription-userinfo']);
    final profile = ClashProfile(
      id: profileId,
      name: _safeName(name),
      source: existing?.source ?? source,
      path: path,
      url: existing?.url ?? url,
      updatedAt: DateTime.now(),
      upload: stats['upload'] ?? existing?.upload ?? 0,
      download: stats['download'] ?? existing?.download ?? 0,
      total: stats['total'] ?? existing?.total ?? 0,
      expiresAt: stats['expire'] == null
          ? existing?.expiresAt
          : DateTime.fromMillisecondsSinceEpoch(stats['expire']! * 1000),
      autoUpdateHours: existing?.autoUpdateHours ?? 24,
      script: script ?? existing?.script ?? '',
      sharedScriptIds: sharedScriptIds ?? existing?.sharedScriptIds,
      standardRules: standardRules ?? existing?.standardRules ?? const [],
      matchTarget: matchTarget ?? existing?.matchTarget,
    );
    final next = [...profiles];
    if (existing == null) {
      next.add(profile);
    } else {
      next[next.indexWhere((item) => item.id == profileId)] = profile;
    }
    try {
      await _commit(next, activeId.value ?? profileId);
    } catch (_) {
      await _repository.discard(path);
      rethrow;
    }
    return profile;
  }

  Future<ClashProfile> _download(
    Uri uri, {
    ClashProfile? existing,
    String? name,
  }) async {
    final key = existing?.id ?? uri.toString();
    updating.add(key);
    try {
      final response = await boundedHttp(uri);
      final content = utf8.decode(response.bytes);
      return await _save(
        id: existing?.id,
        name: name ?? existing?.name ?? _responseName(response.headers, uri),
        content: content,
        source: ProfileSource.remote,
        url: uri.toString(),
        headers: response.headers,
      );
    } on Object {
      if (existing != null) {
        updateFailure.value = ProfileUpdateFailure(existing.id, existing.name);
      }
      rethrow;
    } finally {
      updating.remove(key);
    }
  }

  Future<String> readContent(ClashProfile profile) async {
    if (!ProfileRepository.validId(profile.id) ||
        !p.isWithin(_repository.dataDirectory.path, profile.path)) {
      throw const FileSystemException('Unsafe profile path.');
    }
    final type = await FileSystemEntity.type(profile.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('Profile content is missing or unsafe.');
    }
    return _readFile(File(profile.path));
  }

  Future<void> activate(String id) => _mutate(() async {
    _find(id);
    await _commit([...profiles], id);
  });

  Future<void> refresh(String id) => _mutate(() async {
    final profile = _find(id);
    if (profile.source != ProfileSource.remote || profile.url.isEmpty) {
      throw const FormatException('Only URL subscriptions can be refreshed.');
    }
    await _download(validateHttpUri(profile.url), existing: profile);
  });

  Future<void> remove(String id) => _mutate(() async {
    _find(id);
    final remaining = profiles.where((profile) => profile.id != id).toList();
    await _commit(
      remaining,
      activeId.value == id ? remaining.firstOrNull?.id : activeId.value,
    );
  });

  Future<void> update(ClashProfile profile) => _mutate(() async {
    final old = _find(profile.id);
    if (profile.path != old.path || profile.source != old.source) {
      throw const FormatException('Profile source cannot be changed.');
    }
    if (profile.autoUpdateHours < 0 ||
        profile.autoUpdateHours > 8760 ||
        profile.script.length > 1024 * 1024) {
      throw const FormatException(
        'Invalid profile update interval or oversized script.',
      );
    }
    if (profile.source == ProfileSource.remote) validateHttpUri(profile.url);
    final next = [...profiles];
    next[next.indexWhere((item) => item.id == profile.id)] = profile.copyWith(
      name: _safeName(profile.name),
    );
    await _commit(next, activeId.value);
  });

  Future<ClashProfile> duplicate(String id) => _mutate(() async {
    final original = _find(id);
    return _save(
      name: '${original.name} copy',
      content: await readContent(original),
      script: original.script,
      sharedScriptIds: original.sharedScriptIds,
      standardRules: original.standardRules,
      matchTarget: original.matchTarget,
    );
  });

  Future<Map<String, dynamic>> exportSnapshot() => _mutate(
    () async => {
      'version': 1,
      'activeId': activeId.value,
      'profiles': [
        for (final profile in profiles)
          {
            ...profile.toJson()..remove('path'),
            'content': await readContent(profile),
          },
      ],
    },
  );

  Future<void> restoreSnapshot(Map<String, dynamic> snapshot) =>
      _mutate(() async {
        final prepared = await compute(validateSnapshot, snapshot);
        final staged = <String>[];
        try {
          final restored = <ClashProfile>[];
          for (final entry in prepared) {
            final path = await _repository.stage(
              entry['id'] as String,
              entry['content'] as String,
            );
            staged.add(path);
            restored.add(ClashProfile.fromJson({...entry, 'path': path}));
          }
          await _commit(restored, snapshot['activeId'] as String?);
        } catch (_) {
          for (final path in staged) {
            await _repository.discard(path);
          }
          rethrow;
        }
      });

  static List<Map<String, dynamic>> validateSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    if (snapshot['version'] != 1 ||
        snapshot['profiles'] is! List ||
        (snapshot['profiles'] as List).length > 1000) {
      throw const FormatException('Unsupported or oversized profile backup.');
    }
    final ids = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final raw in snapshot['profiles'] as List) {
      if (raw is! Map) {
        throw const FormatException('Invalid profile in backup.');
      }
      final entry = Map<String, dynamic>.from(raw);
      final id = entry['id'];
      if (id is! String ||
          !ProfileRepository.validId(id) ||
          !ids.add(id) ||
          entry['content'] is! String ||
          entry['name'] is! String) {
        throw const FormatException('Invalid or duplicate profile in backup.');
      }
      parseConfig(entry['content'] as String);
      entry['name'] = _safeName(entry['name'] as String);
      final profile = ClashProfile.fromJson({...entry, 'path': ''});
      if (profile.source == ProfileSource.remote) validateHttpUri(profile.url);
      if (profile.script.length > 1024 * 1024 ||
          profile.autoUpdateHours < 0 ||
          profile.autoUpdateHours > 8760) {
        throw const FormatException('Invalid profile metadata in backup.');
      }
      result.add(entry);
    }
    if (snapshot['activeId'] != null && !ids.contains(snapshot['activeId'])) {
      throw const FormatException('Backup active profile does not exist.');
    }
    return result;
  }

  static void _validateContent(String content) {
    parseConfig(content);
  }

  Future<void> _commit(List<ClashProfile> next, String? selected) async {
    await _repository.commit(next, selected);
    profiles.assignAll(next);
    activeId.value = selected;
  }

  ClashProfile _find(String id) =>
      profiles.firstWhereOrNull((profile) => profile.id == id) ??
      (throw const FormatException('Profile does not exist.'));
  static Future<String> _readFile(File file) async {
    if (await file.length() > 16 * 1024 * 1024) {
      throw const FormatException('Profile exceeds the 16 MiB limit.');
    }
    return file.readAsString();
  }

  static String _safeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .trim();
    return cleaned.isEmpty
        ? 'Profile'
        : cleaned.substring(0, cleaned.length.clamp(0, 100));
  }

  static String _responseName(Map<String, String> headers, Uri uri) {
    final disposition = headers['content-disposition'] ?? '';
    final extended = RegExp(
      "filename\\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    if (extended != null) {
      try {
        return Uri.decodeComponent(extended);
      } on FormatException {
        /* use fallback */
      }
    }
    final simple = RegExp(
      'filename="?([^";]+)',
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    return simple ??
        (uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last);
  }

  static Map<String, int> _subscriptionInfo(String? header) {
    final result = <String, int>{};
    for (final part in (header ?? '').split(';')) {
      final pair = part.trim().split('=');
      if (pair.length != 2 ||
          ![
            'upload',
            'download',
            'total',
            'expire',
          ].contains(pair.first.trim())) {
        continue;
      }
      final value = int.tryParse(pair.last.trim());
      if (value != null && value >= 0 && value <= 8640000000000) {
        result[pair.first.trim()] = value;
      }
    }
    return result;
  }

  static String _message(Object error) =>
      error is FormatException ? error.message.toString() : error.toString();
  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }
}

/// Deliberately excludes subscription URLs, credentials and response bodies.
class ProfileUpdateFailure {
  const ProfileUpdateFailure(this.id, this.name);
  final String id, name;
}
