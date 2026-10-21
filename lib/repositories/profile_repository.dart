import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domains/clash_profile.dart';
import '../storage/atomic_file.dart';

class ProfileRepository {
  ProfileRepository(Directory directory)
    : directory = Directory(p.join(directory.path, 'profiles'));
  final Directory directory;
  Directory get dataDirectory => Directory(p.join(directory.path, 'data'));
  File get _index => File(p.join(directory.path, 'index.json'));
  static bool validId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id);

  Future<({List<ClashProfile> profiles, String? activeId})> read() async {
    await dataDirectory.create(recursive: true);
    if (!await _index.exists()) {
      return (profiles: <ClashProfile>[], activeId: null);
    }
    if (await _index.length() > 4 * 1024 * 1024) {
      throw const FormatException('Profile index is too large.');
    }
    final decoded = jsonDecode(await _index.readAsString());
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['profiles'] is! List) {
      throw const FormatException('The profile index is invalid.');
    }
    final profiles = <ClashProfile>[];
    final ids = <String>{};
    for (final entry in decoded['profiles'] as List) {
      if (entry is! Map) throw const FormatException('Invalid profile record.');
      final record = Map<String, dynamic>.from(entry);
      final id = record['id'];
      if (id is! String || !validId(id) || !ids.add(id)) {
        throw const FormatException('Invalid or duplicate profile ID.');
      }
      final filename = record['path'];
      if (filename is! String ||
          p.basename(filename) != filename ||
          !RegExp(
            '^${RegExp.escape(id)}-[a-f0-9]{32}\\.yaml\$',
          ).hasMatch(filename)) {
        throw const FormatException('Unsafe profile content path.');
      }
      final file = File(p.join(dataDirectory.path, filename));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException(
          'Profile content is missing or unsafe',
          file.path,
        );
      }
      record['path'] = file.path;
      profiles.add(ClashProfile.fromJson(record));
    }
    final active = decoded['activeId'];
    if (active != null && (active is! String || !ids.contains(active))) {
      throw const FormatException('The active profile does not exist.');
    }
    return (profiles: profiles, activeId: active as String?);
  }

  Future<String> stage(String id, String content) async {
    if (!validId(id)) throw const FormatException('Invalid profile ID.');
    final file = File(
      p.join(dataDirectory.path, '$id-${randomIdentifier()}.yaml'),
    );
    await writePrivateText(file, content);
    return file.path;
  }

  Future<void> commit(List<ClashProfile> profiles, String? activeId) async {
    final records = profiles.map((profile) {
      if (!validId(profile.id) ||
          !p.isWithin(dataDirectory.path, profile.path)) {
        throw const FormatException('Unsafe profile path.');
      }
      return {...profile.toJson(), 'path': p.basename(profile.path)};
    }).toList();
    await writePrivateText(
      _index,
      jsonEncode({'version': 1, 'profiles': records, 'activeId': activeId}),
    );
  }

  Future<void> discard(String path) async {
    if (p.isWithin(dataDirectory.path, path)) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
