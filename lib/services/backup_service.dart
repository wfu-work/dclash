import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../storage/atomic_file.dart';
import '../utils/bounded_http.dart';
import 'profile_service.dart';
import 'settings_service.dart';

/// Portable dclash backups. Only data from the validated payload is restored;
/// archive entry names are never used as filesystem destinations.
class BackupService {
  BackupService(this.profiles, this.settings);
  final ProfileService profiles;
  final SettingsService settings;
  static const maxArchiveBytes = 32 * 1024 * 1024;
  static const maxExpandedBytes = 64 * 1024 * 1024;
  Future<void> _pending = Future.value();

  Future<T> _serialize<T>(Future<T> Function() work) {
    final result = _pending.then((_) => work());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Uint8List> exportArchive() => _serialize(() async {
    final fields = settings.export();
    final webdav = Uri.tryParse(fields['webdavUrl'] as String? ?? '');
    if (webdav != null && webdav.userInfo.isNotEmpty) {
      fields['webdavUrl'] = webdav.replace(userInfo: '').toString();
    }
    return compute(_encodeArchive, {
      'format': 'cloudrift',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': fields,
      'profiles': await profiles.exportSnapshot(),
    });
  });

  static Uint8List _encodeArchive(Map<String, dynamic> payload) {
    final data = utf8.encode(jsonEncode(payload));
    if (data.length > maxExpandedBytes) {
      throw const FormatException('Backup exceeds the 64 MiB limit.');
    }
    final archive = Archive()
      ..add(ArchiveFile.bytes('backup.json', data)..mode = 0x180);
    final encoded = ZipEncoder().encode(archive);
    if (encoded.length > maxArchiveBytes) {
      throw const FormatException(
        'Compressed backup exceeds the 32 MiB limit.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  Future<void> importArchive(List<int> bytes) => _serialize(() async {
    final payload = await compute(_decodeArchive, bytes);
    if (payload['format'] != 'cloudrift' ||
        payload['version'] != 1 ||
        payload['profiles'] is! Map ||
        payload['settings'] is! Map) {
      throw const FormatException('This is not a supported dclash backup.');
    }
    final snapshot = Map<String, dynamic>.from(payload['profiles'] as Map);
    await compute(ProfileService.validateSnapshot, snapshot);
    final fields = Map<String, dynamic>.from(payload['settings'] as Map);
    // Use exactly the same settings validator as normal persistence, without
    // writing platform preferences or keychain entries during validation.
    final validator = SettingsService(memoryOnly: true);
    await validator.initialize();
    await validator.restore(fields);
    final validatedSettings = validator.export();
    final oldSettings = settings.export();
    final oldProfiles = await profiles.exportSnapshot();
    var settingsApplied = false;
    var profilesApplied = false;
    try {
      await settings.restore(validatedSettings);
      settingsApplied = true;
      await profiles.restoreSnapshot(snapshot);
      profilesApplied = true;
    } catch (error) {
      Object? rollbackError;
      if (profilesApplied) {
        try {
          await profiles.restoreSnapshot(oldProfiles);
        } catch (e) {
          rollbackError = e;
        }
      }
      if (settingsApplied) {
        try {
          await settings.restore(oldSettings);
        } catch (e) {
          rollbackError = e;
        }
      }
      if (rollbackError != null) {
        throw StateError(
          'Restore failed: $error. Restoring previous data also failed: $rollbackError',
        );
      }
      rethrow;
    }
  });

  static Map<String, dynamic> _decodeArchive(List<int> input) {
    if (input.length > maxArchiveBytes || input.length < 22) {
      throw const FormatException(
        'Backup archive is empty, invalid, or too large.',
      );
    }
    final bytes = input is Uint8List ? input : Uint8List.fromList(input);
    final data = ByteData.sublistView(bytes);
    // Preflight central/local records before the ZIP decoder sees symlinks or
    // allocates decompression buffers. ZIP64, multipart and encrypted ZIPs are
    // intentionally unsupported for this one-file backup format.
    var end = -1;
    for (
      var offset = bytes.length - 22;
      offset >= 0 && offset >= bytes.length - 65557;
      offset--
    ) {
      if (data.getUint32(offset, Endian.little) == 0x06054b50 &&
          offset + 22 + data.getUint16(offset + 20, Endian.little) ==
              bytes.length) {
        end = offset;
        break;
      }
    }
    if (end < 0 ||
        data.getUint16(end + 4, Endian.little) != 0 ||
        data.getUint16(end + 6, Endian.little) != 0 ||
        data.getUint16(end + 8, Endian.little) != 1 ||
        data.getUint16(end + 10, Endian.little) != 1) {
      throw const FormatException(
        'Backup must contain exactly one regular payload file.',
      );
    }
    final central = data.getUint32(end + 16, Endian.little);
    if (central < 0 ||
        central + 46 > end ||
        data.getUint32(central, Endian.little) != 0x02014b50) {
      throw const FormatException('Invalid ZIP directory.');
    }
    final flags = data.getUint16(central + 8, Endian.little);
    final method = data.getUint16(central + 10, Endian.little);
    final expanded = data.getUint32(central + 24, Endian.little);
    final compressed = data.getUint32(central + 20, Endian.little);
    final nameLength = data.getUint16(central + 28, Endian.little);
    final extraLength = data.getUint16(central + 30, Endian.little);
    final commentLength = data.getUint16(central + 32, Endian.little);
    final fileType =
        (data.getUint32(central + 38, Endian.little) >> 16) & 0xf000;
    final local = data.getUint32(central + 42, Endian.little);
    if (central + 46 + nameLength + extraLength + commentLength != end ||
        flags & 1 != 0 ||
        ![0, 8].contains(method) ||
        expanded > maxExpandedBytes ||
        compressed > maxArchiveBytes ||
        ![0, 0x8000].contains(fileType) ||
        local + 30 > central ||
        data.getUint32(local, Endian.little) != 0x04034b50) {
      throw const FormatException('Unsafe or oversized ZIP entry.');
    }
    final name = utf8.decode(
      bytes.sublist(central + 46, central + 46 + nameLength),
    );
    final localNameLength = data.getUint16(local + 26, Endian.little);
    final localExtraLength = data.getUint16(local + 28, Endian.little);
    final contentStart = local + 30 + localNameLength + localExtraLength;
    if (name != 'backup.json' ||
        contentStart > central ||
        contentStart + compressed > central ||
        utf8.decode(bytes.sublist(local + 30, local + 30 + localNameLength)) !=
            name ||
        data.getUint16(local + 6, Endian.little) & 1 != 0 ||
        data.getUint16(local + 8, Endian.little) != method) {
      throw const FormatException('Unsafe backup entry name or data.');
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.single;
      final output = _LimitedOutput(maxExpandedBytes);
      entry.decompress(output);
      final content = output.getBytes();
      if (content.length != expanded || getCrc32(content) != entry.crc32) {
        throw const FormatException('Backup checksum or size does not match.');
      }
      final decoded = jsonDecode(utf8.decode(content));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Backup payload must be an object.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Backup archive could not be read: $error');
    }
  }

  Future<String?> exportFile() async {
    final bytes = await exportArchive();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export dclash backup',
      fileName: 'dclash-backup.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes,
    );
    if (path == null) return null;
    if (!path.startsWith('content:')) {
      await writePrivateAtomic(File(path), bytes);
    }
    return path;
  }

  Future<bool> importFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    if (selection == null) return false;
    final chosen = selection.files.single;
    if (chosen.size > maxArchiveBytes) {
      throw const FormatException('Backup exceeds the 32 MiB limit.');
    }
    final path = chosen.path;
    if (path == null) {
      throw const FileSystemException('The selected backup cannot be read.');
    }
    final file = File(path);
    if (await file.length() > maxArchiveBytes) {
      throw const FormatException('Backup exceeds the 32 MiB limit.');
    }
    await importArchive(await file.readAsBytes());
    return true;
  }

  Future<void> uploadWebDav({String filename = 'dclash-backup.zip'}) async {
    final uri = _webdavUri(filename);
    final bytes = await exportArchive();
    await boundedHttp(
      uri,
      method: 'PUT',
      body: bytes,
      headers: await _webdavHeaders(),
      maxBytes: 1024 * 1024,
    );
  }

  Future<void> downloadWebDav({String filename = 'dclash-backup.zip'}) async {
    final response = await boundedHttp(
      _webdavUri(filename),
      headers: await _webdavHeaders(),
      maxBytes: maxArchiveBytes,
    );
    await importArchive(response.bytes);
  }

  Uri _webdavUri(String filename) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+\.zip$').hasMatch(filename) ||
        filename.contains('..')) {
      throw const FormatException('Invalid backup filename.');
    }
    final base = validateHttpUri(settings.fields['webdavUrl'] as String? ?? '');
    if (base.userInfo.isNotEmpty) {
      throw const FormatException(
        'Store the WebDAV username and password in the credential fields.',
      );
    }
    final root = base.replace(
      path: base.path.endsWith('/') ? base.path : '${base.path}/',
    );
    return root.resolve(filename);
  }

  Future<Map<String, String>> _webdavHeaders() async {
    final user = settings.fields['webdavUser'] as String? ?? '';
    final password = await settings.readSecret('webdavPassword');
    return {
      'Content-Type': 'application/zip',
      if (user.isNotEmpty || password.isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$user:$password'))}',
    };
  }
}

class _LimitedOutput extends OutputMemoryStream {
  _LimitedOutput(this.limit);
  final int limit;
  void _check(int count) {
    if (length + count > limit) {
      throw const FormatException('Expanded backup exceeds the 64 MiB limit.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}
