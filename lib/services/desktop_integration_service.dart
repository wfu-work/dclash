import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tray/tray.dart';
import 'package:window/window.dart';

import '../app/widgets/app_message.dart';
import '../domains/clash_connection.dart';
import '../domains/core_status.dart';
import 'core_service.dart';
import 'settings_service.dart';

/// Labels used by the native tray menu.
///
/// The tray is owned by the operating system and can outlive the Flutter
/// widget tree. Keep its labels independent from the app locale so a stale
/// GetX translation (for example, the key itself) never leaks into the menu.
abstract final class DesktopTrayText {
  static const _values = <String, String>{
    'hideWindow': '隐藏窗口',
    'showWindow': '显示窗口',
    'status': '运行状态',
    'stopped': '未连接',
    'starting': '正在连接',
    'running': '运行中',
    'stopping': '正在断开',
    'failed': '连接失败',
    'start': '连接',
    'stop': '断开',
    'outboundMode': '出站模式',
    'rule': '规则',
    'global': '全局',
    'direct': '直连',
    'systemProxy': '系统代理',
    'tun': 'TUN 模式',
    'allowLan': '允许局域网连接',
    'minimizeToTray': '关闭窗口时最小化到托盘',
    'launchAtLogin': '开机启动',
    'quit': '退出 dclash',
  };

  static String label(String key) => _values[key] ?? key;
}

class DesktopIntegrationService extends GetxService with WindowListener {
  DesktopIntegrationService(
    this.core,
    this.settings, {
    this.preview = false,
    this.beforeExit,
  });
  final CoreService core;
  final SettingsService settings;
  final bool preview;
  final Future<void> Function()? beforeExit;
  final _window = DesktopWindow.instance;
  StreamSubscription<TrayEvent>? _traySubscription;
  StreamSubscription<ProcessSignal>? _signalSubscription;
  Worker? _worker;
  bool _trayUpdateRunning = false;
  bool _trayUpdatePending = false;
  bool _quitting = false;
  bool _ready = false;
  bool _windowVisible = false;
  bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> initialize() async {
    if (!supported) return;
    await _window.ensureInitialized();
    await _window.setMinimumSize(const Size(390, 640));
    await _window.setSize(const Size(1240, 850));
    await _window.center();
    await _window.setPreventClose(true);
    _window.addListener(this);
    _ready = true;
    await _window.show();
    _windowVisible = true;
    if (!Platform.isWindows) {
      _signalSubscription = ProcessSignal.sigterm.watch().listen(
        (_) => unawaited(quit()),
      );
    }
    if (preview) return;
    try {
      await _updateTray();
      _traySubscription = Tray.instance.events.listen((event) {
        if (event is TrayIconActivated) {
          unawaited(_show().catchError(_report));
        }
        if (event is TrayMenuRequested) {
          unawaited(Tray.instance.openMenu().catchError(_report));
        }
      });
      _worker = everAll([
        core.status,
        core.groups,
        core.delays,
        settings.fields,
      ], (_) => _requestTrayUpdate());
    } on Object catch (error) {
      _report(error);
    }
  }

  Future<void> _show() async {
    if (_quitting) return;
    await _window.show();
    await _window.focus();
    _windowVisible = true;
    _requestTrayUpdate();
  }

  Future<void> _hideToTray() async {
    if (_quitting) return;
    await _window.hide();
    _windowVisible = false;
    _requestTrayUpdate();
  }

  /// Coalesces updates caused by core events and settings writes.
  /// Native tray menus are serialized too, but sending every intermediate
  /// state would leave a stale menu visible while a burst is in flight.
  void _requestTrayUpdate() {
    if (_quitting || preview || !_ready) return;
    _trayUpdatePending = true;
    if (_trayUpdateRunning) return;
    _trayUpdateRunning = true;
    unawaited(_drainTrayUpdates().catchError(_report));
  }

  Future<void> _drainTrayUpdates() async {
    try {
      do {
        _trayUpdatePending = false;
        await _updateTray();
      } while (_trayUpdatePending && !_quitting);
    } finally {
      _trayUpdateRunning = false;
      if (_trayUpdatePending && !_quitting) _requestTrayUpdate();
    }
  }

  Future<void> _updateTray() async {
    if (_quitting || preview) return;
    await Tray.instance.show(
      TraySpec(
        icon: TrayIcon.asset(
          Platform.isWindows
              ? 'assets/brand/tray.ico'
              : 'assets/brand/tray.png',
          isTemplate: Platform.isMacOS,
          size: 20,
        ),
        toolTip: 'dclash · ${DesktopTrayText.label(core.status.value.name)}',
        menu: [
          TrayMenuAction(
            label: DesktopTrayText.label(
              _windowVisible ? 'hideWindow' : 'showWindow',
            ),
            onSelected: () => unawaited(
              (_windowVisible ? _hideToTray() : _show()).catchError(_report),
            ),
          ),
          const TrayMenuSeparator(),
          TrayMenuAction(
            label: DesktopTrayText.label('status'),
            detail: DesktopTrayText.label(core.status.value.name),
            enabled: false,
          ),
          TrayMenuAction(
            label: DesktopTrayText.label(core.running ? 'stop' : 'start'),
            enabled: !const [
              CoreStatus.starting,
              CoreStatus.stopping,
            ].contains(core.status.value),
            onSelected: () => unawaited(core.toggle().catchError(_report)),
          ),
          TrayMenuSubmenu(
            label: DesktopTrayText.label('outboundMode'),
            items: [
              for (final mode in ['rule', 'global', 'direct'])
                TrayMenuCheckbox(
                  label: DesktopTrayText.label(mode),
                  checked: settings.fields['mode'] == mode,
                  enabled: !_busy,
                  onSelected: () =>
                      unawaited(core.setMode(mode).catchError(_report)),
                ),
            ],
          ),
          if (core.groups.isNotEmpty) ...[
            for (final group in core.groups)
              if (group.selectable && group.nodes.isNotEmpty)
                TrayMenuSubmenu(
                  label: group.name,
                  detail: group.selected,
                  items: [
                    for (final node in group.nodes)
                      TrayMenuCheckbox(
                        label: node.name,
                        checked: node.name == group.selected,
                        enabled: !_busy,
                        onSelected: () => unawaited(
                          core
                              .selectProxy(group.name, node.name)
                              .catchError(_report),
                        ),
                      ),
                  ],
                ),
            const TrayMenuSeparator(),
          ],
          TrayMenuCheckbox(
            label: DesktopTrayText.label('systemProxy'),
            checked: settings.fields['systemProxy'] == true,
            enabled: !_busy,
            onSelected: () => unawaited(
              _setRuntimeSetting(
                'systemProxy',
                settings.fields['systemProxy'] != true,
              ),
            ),
          ),
          TrayMenuCheckbox(
            label: DesktopTrayText.label('tun'),
            checked: settings.fields['tunEnabled'] == true,
            enabled: !_busy,
            onSelected: () => unawaited(
              _setRuntimeSetting(
                'tunEnabled',
                settings.fields['tunEnabled'] != true,
              ),
            ),
          ),
          TrayMenuCheckbox(
            label: DesktopTrayText.label('allowLan'),
            checked: settings.fields['allowLan'] == true,
            enabled: !_busy,
            onSelected: () => unawaited(
              _setRuntimeSetting(
                'allowLan',
                settings.fields['allowLan'] != true,
              ),
            ),
          ),
          TrayMenuCheckbox(
            label: DesktopTrayText.label('minimizeToTray'),
            checked: settings.fields['minimizeToTray'] == true,
            onSelected: () => unawaited(_setMinimizeToTray()),
          ),
          TrayMenuCheckbox(
            label: DesktopTrayText.label('launchAtLogin'),
            checked: settings.fields['launchAtLogin'] == true,
            onSelected: () => unawaited(_setLaunchAtLogin()),
          ),
          const TrayMenuSeparator(),
          TrayMenuAction(
            label: DesktopTrayText.label('quit'),
            onSelected: () => unawaited(quit()),
          ),
        ],
      ),
    );
  }

  bool get _busy => const [
    CoreStatus.starting,
    CoreStatus.stopping,
  ].contains(core.status.value);

  void _report(Object error) {
    core.logs.add(
      CoreLog(
        level: 'error',
        message: 'Desktop integration: $error',
        time: DateTime.now(),
      ),
    );
    if (core.logs.length > 1000) {
      core.logs.removeRange(0, core.logs.length - 1000);
    }
    final context = Get.context;
    if (context != null && context.mounted) {
      AppMessage.error(context, error);
    }
  }

  Future<void> _setMinimizeToTray() async {
    try {
      await settings.set(
        'minimizeToTray',
        settings.fields['minimizeToTray'] != true,
      );
    } on Object catch (error) {
      _report(error);
    }
  }

  Future<void> _setLaunchAtLogin() async {
    final value = settings.fields['launchAtLogin'] != true;
    final previous = settings.fields['launchAtLogin'] == true;
    var startupChanged = false;
    try {
      await core.setLaunchAtLogin(value);
      startupChanged = true;
      await settings.set('launchAtLogin', value);
    } on Object catch (error) {
      if (startupChanged) {
        try {
          await core.setLaunchAtLogin(previous);
        } on Object catch (rollback) {
          _report('Could not restore launch-at-login state: $rollback');
        }
      }
      if (settings.fields['launchAtLogin'] != previous) {
        try {
          await settings.set('launchAtLogin', previous);
        } on Object catch (rollback) {
          _report('Could not restore launch-at-login preference: $rollback');
        }
      }
      _report(error);
    }
  }

  Future<void> _setRuntimeSetting(String key, bool value) async {
    final previous = settings.fields[key];
    try {
      await settings.set(key, value);
      if (core.running) await core.reload();
    } on Object catch (error) {
      if (settings.fields[key] != previous) {
        try {
          await settings.set(key, previous);
        } on Object catch (rollback) {
          _report('Could not restore $key after reload failure: $rollback');
        }
      }
      _report(error);
    }
  }

  @override
  void onWindowClose() {
    if (!preview &&
        settings.fields['minimizeToTray'] == true &&
        Tray.instance.isVisible) {
      unawaited(_hideToTray().catchError(_report));
    } else {
      unawaited(quit());
    }
  }

  @override
  void onWindowActivate() => unawaited(_show().catchError(_report));

  @override
  void onWindowShow() {
    _windowVisible = true;
    _requestTrayUpdate();
  }

  @override
  void onWindowHide() {
    _windowVisible = false;
    _requestTrayUpdate();
  }

  @override
  void onWindowShouldTerminate() => unawaited(quit());

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await core.stop();
      if (!preview) await Tray.instance.hide();
      await beforeExit?.call();
      await core.disposeRuntime();
      await _traySubscription?.cancel();
      await _signalSubscription?.cancel();
      _worker?.dispose();
      _window.removeListener(this);
      await _window.setPreventClose(false);
      exit(0);
    } on Object catch (error) {
      _quitting = false;
      _report(error);
      await _show();
    }
  }

  @override
  void onClose() {
    unawaited(disposeIntegration().catchError(_report));
    super.onClose();
  }

  Future<void> disposeIntegration() async {
    if (_ready) _window.removeListener(this);
    _worker?.dispose();
    _worker = null;
    _trayUpdatePending = false;
    await _traySubscription?.cancel();
    _traySubscription = null;
    await _signalSubscription?.cancel();
    _signalSubscription = null;
    if (_ready) await _window.setPreventClose(false);
    _windowVisible = false;
    if (!preview && Tray.instance.isVisible) {
      await Tray.instance.hide();
    }
    _ready = false;
  }
}
