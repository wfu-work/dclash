import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class CoreException implements Exception {
  const CoreException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

Object? _decodeBytes(List<int> bytes) => jsonDecode(utf8.decode(bytes));

/// The native bridge already frames messages. This layer correlates replies and
/// only accepts spill files in the current core's private response directory.
class CoreRpc {
  CoreRpc({
    required this.send,
    required this.homeDirectory,
    this.timeout = const Duration(seconds: 30),
    this.setupConfigTimeout = const Duration(minutes: 3),
  });
  final void Function(List<int>) send;
  final String homeDirectory;
  final Duration timeout;

  /// GeoIP/GeoSite resources may need to be fetched on the first launch.
  /// Keep ordinary control calls responsive while allowing setupConfig enough
  /// time to finish that one-time download on mobile networks.
  final Duration setupConfigTimeout;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<dynamic>> _pending = {};
  int _sequence = 0;
  bool _closed = false;
  Stream<Map<String, dynamic>> get events => _events.stream;
  int get pendingCount => _pending.length;

  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    if (_closed) {
      throw const CoreException('closed', 'Core transport is closed');
    }
    if (_pending.length >= 128) {
      throw const CoreException('busy', 'Too many pending core requests');
    }
    final id = '${++_sequence}';
    final reply = Completer<dynamic>();
    _pending[id] = reply;
    try {
      send(
        utf8.encode(
          jsonEncode({'id': id, 'method': method, 'arguments': arguments}),
        ),
      );
      final requestTimeout = method == 'setupConfig'
          ? setupConfigTimeout
          : timeout;
      return await reply.future.timeout(
        requestTimeout,
        onTimeout: () =>
            throw CoreException('timeout', 'Core request timed out: $method'),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> receive(List<int> bytes) async {
    if (_closed) return;
    try {
      final decoded = bytes.length > 51200
          ? await compute(_decodeBytes, bytes)
          : _decodeBytes(bytes);
      if (decoded is! Map) throw const FormatException('Invalid core response');
      var response = Map<String, dynamic>.from(decoded);
      if (response['method'] == 'message') {
        final arguments = response['arguments'];
        final list = arguments is List ? arguments : [arguments];
        for (final event in list.take(256)) {
          if (event is Map && !_events.isClosed) {
            _events.add(Map<String, dynamic>.from(event));
          }
        }
        return;
      }
      final id = response['id']?.toString();
      final completer = _pending[id];
      final spilled = response['file'];
      if (spilled is String) {
        response = await _resolveSpill(spilled, id);
      }
      if (completer == null || completer.isCompleted || _closed) return;
      final failure = response['error'];
      if (failure is Map) {
        completer.completeError(
          CoreException('${failure['code']}', '${failure['message']}'),
        );
      } else {
        completer.complete(response['result']);
      }
    } catch (error, stack) {
      fail(error, stack);
    }
  }

  Future<Map<String, dynamic>> _resolveSpill(String path, String? id) async {
    final directory = p.join(homeDirectory, 'responses');
    final file = File(p.normalize(p.absolute(path)));
    if (!p.equals(p.dirname(file.path), p.normalize(p.absolute(directory))) ||
        await FileSystemEntity.isLink(file.path)) {
      throw const CoreException(
        'invalid_spill',
        'Core returned an invalid response file',
      );
    }
    final realDirectory = await Directory(directory).resolveSymbolicLinks();
    if (!p.equals(
      p.dirname(await file.resolveSymbolicLinks()),
      realDirectory,
    )) {
      throw const CoreException(
        'invalid_spill',
        'Core response escaped its directory',
      );
    }
    try {
      if (await file.length() > 64 * 1024 * 1024) {
        throw const CoreException(
          'large_response',
          'Core response exceeds 64 MB',
        );
      }
      final decoded = await compute(_decodeBytes, await file.readAsBytes());
      if (decoded is! Map ||
          decoded['id']?.toString() != id ||
          decoded['file'] != null) {
        throw const CoreException(
          'invalid_spill',
          'Core response identity mismatch',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  void fail(Object error, [StackTrace? stack]) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final reply in pending) {
      if (!reply.isCompleted) reply.completeError(error, stack);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    fail(const CoreException('disconnected', 'Core disconnected'));
    await _events.close();
  }
}
