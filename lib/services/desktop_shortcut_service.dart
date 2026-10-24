import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'core_service.dart';
import 'settings_service.dart';

class DesktopShortcutService extends GetxService {
  DesktopShortcutService(
    this.core,
    this.settings, {
    required this.toggleWindow,
    Future<void> Function(HotKey, void Function())? register,
    Future<void> Function(HotKey)? unregister,
  }) : _register =
           register ??
           ((key, action) =>
               hotKeyManager.register(key, keyDownHandler: (_) => action())),
       _unregister = unregister ?? hotKeyManager.unregister;
  final CoreService core;
  final SettingsService settings;
  final Future<void> Function() toggleWindow;
  final Future<void> Function(HotKey, void Function()) _register;
  final Future<void> Function(HotKey) _unregister;
  final error = RxnString();
  final _registered = <HotKey>[];
  Map<String, dynamic> _applied = {};
  Future<void> _queue = Future.value();
  Worker? _worker;
  static const keys = [
    'shortcutsEnabled',
    'shortcutWindow',
    'shortcutConnection',
    'shortcutMode',
  ];
  static HotKey parse(String value, String id) {
    final parts = value.split('+');
    final letter = parts.removeLast();
    return HotKey(
      identifier: id,
      key: LogicalKeyboardKey.findKeyByKeyId(letter.codeUnitAt(0))!,
      modifiers: parts
          .map(
            (part) => switch (part) {
              'ctrl' => HotKeyModifier.control,
              'alt' => HotKeyModifier.alt,
              'shift' => HotKeyModifier.shift,
              'meta' => HotKeyModifier.meta,
              _ => throw const FormatException('Invalid shortcut'),
            },
          )
          .toList(),
    );
  }

  void initialize() {
    _worker = debounce(
      settings.fields,
      (_) => unawaited(apply(settings.fields).catchError((Object _) {})),
      time: const Duration(milliseconds: 150),
    );
    unawaited(apply(settings.fields).catchError((Object _) {}));
  }

  Future<void> apply(Map<String, dynamic> values) {
    final next = {for (final key in keys) key: values[key]};
    SettingsService.validate(values);
    final task = _queue.then((_) async {
      if (keys.every((key) => _applied[key] == next[key])) return;
      final previous = Map<String, dynamic>.of(_applied);
      try {
        await _remove();
        await _install(next);
        _applied = next;
        error.value = null;
      } on Object catch (failure) {
        error.value = failure.toString();
        try {
          await _remove();
          await _install(previous);
          _applied = previous;
        } on Object catch (rollback) {
          _applied = {};
          error.value = '$failure; $rollback';
        }
        rethrow;
      }
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _install(Map<String, dynamic> values) async {
    if (values['shortcutsEnabled'] != true) return;
    final actions = <String, Future<void> Function()>{
      'shortcutWindow': toggleWindow,
      'shortcutConnection': core.toggle,
      'shortcutMode': () async {
        const modes = ['rule', 'global', 'direct'];
        final current = modes.indexOf(settings.fields['mode'] as String);
        await core.setMode(modes[(current + 1) % modes.length]);
      },
    };
    for (final entry in actions.entries) {
      final key = parse(values[entry.key] as String, entry.key);
      await _register(
        key,
        () => unawaited(
          entry.value().catchError((Object failure) {
            error.value = failure.toString();
          }),
        ),
      );
      _registered.add(key);
    }
  }

  Future<void> _remove() async {
    for (final key in _registered.toList()) {
      await _unregister(key);
      _registered.remove(key);
    }
  }

  Future<void> disposeShortcuts() async {
    _worker?.dispose();
    await _queue;
    await _remove();
  }

  @override
  void onClose() {
    unawaited(disposeShortcuts().catchError((Object _) {}));
    super.onClose();
  }
}
