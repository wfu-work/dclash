import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../domains/script_library.dart';
import '../storage/atomic_file.dart';
import '../utils/bounded_http.dart';
import 'settings_service.dart';

typedef ScriptDownloader = Future<String> Function(Uri url);

class ScriptLibraryService extends GetxService {
  ScriptLibraryService(this.settings, {ScriptDownloader? downloader})
    : _downloader = downloader ?? _download;

  final SettingsService settings;
  final ScriptDownloader _downloader;
  final scripts = <LibraryScript>[].obs;
  final error = RxnString();
  final busy = false.obs;
  Worker? _worker;
  String? _lastRaw;

  String get raw => settings.fields['scripts'] as String? ?? '';

  void initialize() {
    _sync();
    _worker ??= ever(settings.fields, (_) => _sync());
  }

  void _sync() {
    if (_lastRaw == raw) return;
    _lastRaw = raw;
    try {
      scripts.assignAll(ScriptLibrary.decode(raw).scripts);
      error.value = null;
    } on Object catch (failure) {
      scripts.clear();
      error.value = failure.toString();
    }
  }

  static Future<String> _download(Uri url) async {
    final response = await boundedHttp(url, maxBytes: maxScriptBytes);
    return utf8.decode(response.bytes);
  }

  Future<void> _change(
    FutureOr<ScriptLibrary> Function(ScriptLibrary current) change,
  ) async {
    if (busy.value) {
      throw StateError('A script operation is already in progress.');
    }
    busy.value = true;
    try {
      final previous = raw;
      final next = await change(ScriptLibrary.decode(previous));
      final encoded = next.encode();
      if (!await settings.compareAndSetString(
        'scripts',
        expected: previous,
        value: encoded,
      )) {
        throw StateError('The script library changed. Please try again.');
      }
      _sync();
    } finally {
      busy.value = false;
    }
  }

  Future<void> createLocal(String name, String content) => _change(
    (current) => current.withScripts([
      ...current.scripts,
      LibraryScript(
        id: randomIdentifier(),
        name: name.trim(),
        content: content,
      ),
    ]),
  );

  Future<void> importRemote(String name, String url) =>
      _change((current) async {
        final uri = validateScriptUrl(url);
        final content = await _downloader(uri);
        return current.withScripts([
          ...current.scripts,
          LibraryScript(
            id: randomIdentifier(),
            name: name.trim(),
            content: content,
            url: uri.toString(),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ]);
      });

  Future<void> save(String id, String name, String content) =>
      _change((current) {
        final old = _find(current, id);
        if (old.remote && content != old.content) {
          throw StateError('Refresh a remote script to change its content.');
        }
        final next = old.copyWith(
          name: name.trim(),
          content: content,
          enabled: content == old.content ? old.enabled : false,
        );
        return _replace(current, next);
      });

  Future<void> setEnabled(String id, bool enabled) => _change(
    (current) =>
        _replace(current, _find(current, id).copyWith(enabled: enabled)),
  );

  Future<void> refreshRemote(String id) => _change((current) async {
    final old = _find(current, id);
    if (old.url == null) throw StateError('This is a local script.');
    final content = await _downloader(validateScriptUrl(old.url!));
    return _replace(
      current,
      old.copyWith(
        content: content,
        enabled: old.content == content ? old.enabled : false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });

  Future<void> remove(String id) => _change((current) {
    _find(current, id);
    return current.withScripts([
      for (final item in current.scripts)
        if (item.id != id) item,
    ]);
  });

  Future<void> move(String id, int offset) => _change((current) {
    if (offset != -1 && offset != 1) {
      throw ArgumentError.value(offset, 'offset');
    }
    final item = _find(current, id);
    final index = current.scripts.indexOf(item);
    final target = index + offset;
    if (target < 0 || target >= current.scripts.length) return current;
    final next = current.scripts.toList()..removeAt(index);
    next.insert(target, item);
    return current.withScripts(next);
  });

  Future<void> reset() async {
    if (busy.value) {
      throw StateError('A script operation is already in progress.');
    }
    busy.value = true;
    try {
      await settings.set('scripts', '');
      _sync();
    } finally {
      busy.value = false;
    }
  }

  static LibraryScript _find(ScriptLibrary current, String id) =>
      current.scripts.firstWhere(
        (item) => item.id == id,
        orElse: () => throw StateError('The script no longer exists.'),
      );

  static ScriptLibrary _replace(ScriptLibrary current, LibraryScript next) =>
      current.withScripts([
        for (final item in current.scripts) item.id == next.id ? next : item,
      ]);

  @override
  void onClose() {
    _worker?.dispose();
    super.onClose();
  }
}
