import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../domains/resource_item.dart';
import '../storage/atomic_file.dart';
import '../utils/bounded_http.dart';
import 'settings_service.dart';

typedef ResourceDownloader = Future<String> Function(Uri url);
typedef ResourceFileReader = Future<String> Function(String path);

const maxResourceItems = 200;
const maxResourceBytes = 16 * 1024 * 1024;

class ResourceLibraryService extends GetxService {
  ResourceLibraryService(
    this.settings, {
    ResourceDownloader? downloader,
    ResourceFileReader? fileReader,
  }) : _downloader = downloader ?? _download,
       _fileReader = fileReader ?? _readFile;

  final SettingsService settings;
  final ResourceDownloader _downloader;
  final ResourceFileReader _fileReader;
  final items = <ResourceItem>[].obs;
  final error = RxnString();
  final busy = false.obs;
  Worker? _worker;
  String? _lastRaw;

  String get raw => settings.fields['resources'] as String? ?? '';

  Future<void> initialize() async {
    _sync();
    _worker ??= ever(settings.fields, (_) => _sync());
  }

  void _sync() {
    if (_lastRaw == raw) return;
    _lastRaw = raw;
    try {
      final envelope = ResourceEnvelope.decode(raw);
      items.assignAll(_ordered(envelope.items));
      error.value = null;
    } on Object catch (failure) {
      items.clear();
      error.value = failure.toString();
    }
  }

  List<ResourceItem> byKind(ResourceKind kind) =>
      items.where((item) => item.kind == kind).toList(growable: false);

  Future<ResourceItem> save({
    String? id,
    required String name,
    required ResourceKind kind,
    required ResourceSourceType sourceType,
    required String source,
    String? content,
    bool enabled = true,
  }) => _change((current) {
    final old = id == null
        ? null
        : current.items.firstWhere(
            (item) => item.id == id,
            orElse: () => throw StateError('The resource no longer exists.'),
          );
    final now = DateTime.now().toUtc();
    final item = ResourceItem(
      id: old?.id ?? randomIdentifier(),
      name: name.trim(),
      kind: kind,
      sourceType: sourceType,
      source: source.trim(),
      content: sourceType == ResourceSourceType.inline
          ? null
          : (content ?? (old?.source == source.trim() ? old?.content : null)),
      enabled: old?.enabled ?? enabled,
      order: old?.order ?? current.items.length,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      extra: old?.extra ?? const {},
    );
    item.validate();
    final next = [
      for (final entry in current.items)
        if (entry.id == item.id) item else entry,
      if (old == null) item,
    ];
    if (next.length > maxResourceItems) {
      throw const FormatException('The resource library is full.');
    }
    ResourceEnvelope.validateItems(next);
    return (_replace(current, next), item);
  });

  Future<void> remove(String id) => _change((current) {
    _find(current, id);
    return (
      _replace(current, current.items.where((item) => item.id != id).toList()),
      null,
    );
  });

  Future<void> setEnabled(String id, bool enabled) => _change((current) {
    _find(current, id);
    return (
      _replace(current, [
        for (final item in current.items)
          item.id == id
              ? item.copyWith(
                  enabled: enabled,
                  updatedAt: DateTime.now().toUtc(),
                )
              : item,
      ]),
      null,
    );
  });

  Future<void> reorder(String id, int order) => _change((current) {
    if (order < 0 || order >= current.items.length) {
      throw const FormatException('Resource order is out of range.');
    }
    _find(current, id);
    final sorted = current.items.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final oldIndex = sorted.indexWhere((item) => item.id == id);
    final item = sorted.removeAt(oldIndex);
    sorted.insert(order, item);
    final now = DateTime.now().toUtc();
    return (
      _replace(current, [
        for (var index = 0; index < sorted.length; index++)
          sorted[index].copyWith(order: index, updatedAt: now),
      ]),
      null,
    );
  });

  Future<ResourceItem> refresh(String id) async {
    return _change((current) async {
      final old = _find(current, id);
      if (old.sourceType == ResourceSourceType.inline) {
        old.validate();
        return (current, old);
      }
      final content = old.sourceType == ResourceSourceType.url
          ? await _downloader(validateHttpUri(old.source))
          : await _fileReader(old.source);
      if (content.trim().isEmpty) {
        throw const FormatException('The resource content is empty.');
      }
      final next = old.copyWith(
        content: content,
        updatedAt: DateTime.now().toUtc(),
      );
      next.validate();
      return (
        _replace(current, [
          for (final item in current.items) item.id == id ? next : item,
        ]),
        next,
      );
    });
  }

  Future<String> resolveContent(ResourceItem item) async {
    final current = _findCurrent(item.id);
    if (current.sourceType == ResourceSourceType.inline) return current.source;
    if (current.content != null && current.content!.trim().isNotEmpty) {
      return current.content!;
    }
    return (await refresh(current.id)).content ??
        (await resolveContent(_findCurrent(current.id)));
  }

  Future<T> _change<T>(
    FutureOr<(ResourceEnvelope, T)> Function(ResourceEnvelope current) change,
  ) async {
    if (busy.value) {
      throw StateError('A resource operation is already in progress.');
    }
    busy.value = true;
    try {
      final previous = raw;
      final current = ResourceEnvelope.decode(previous);
      final changed = await change(current);
      final encoded = changed.$1.encode();
      if (!await settings.compareAndSetString(
        'resources',
        expected: previous,
        value: encoded,
      )) {
        throw StateError('The resource library changed. Please try again.');
      }
      _sync();
      return changed.$2;
    } finally {
      busy.value = false;
    }
  }

  ResourceItem _findCurrent(String id) =>
      _find(ResourceEnvelope(items: items.toList(growable: false)), id);

  static ResourceItem _find(ResourceEnvelope current, String id) =>
      current.items.firstWhere(
        (item) => item.id == id,
        orElse: () => throw StateError('The resource no longer exists.'),
      );

  static ResourceEnvelope _replace(
    ResourceEnvelope current,
    List<ResourceItem> next,
  ) => ResourceEnvelope(items: _ordered(next), extra: current.extra);

  static List<ResourceItem> _ordered(Iterable<ResourceItem> values) {
    final list = values.toList();
    list.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : order;
    });
    return list;
  }

  static Future<String> _download(Uri url) async {
    final response = await boundedHttp(url, maxBytes: maxResourceBytes);
    return utf8.decode(response.bytes);
  }

  static Future<String> _readFile(String path) => File(path).readAsString();

  @override
  void onClose() {
    _worker?.dispose();
    super.onClose();
  }
}
