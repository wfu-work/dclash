import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'core_rpc.dart';

class DesktopStartup {
  static const _channel = MethodChannel('launch_at_startup');
  static const _windowsValue = 'dclash';
  static const _legacyWindowsValue = 'Cloudrift';
  static const _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static File get _linuxFile => File(
    p.join(
      Platform.environment['XDG_CONFIG_HOME'] ??
          p.join(Platform.environment['HOME']!, '.config'),
      'autostart',
      'com.cloudrift.dclash.desktop',
    ),
  );

  static Future<bool> isEnabled() async {
    if (Platform.isMacOS) {
      return await _channel.invokeMethod<bool>('launchAtStartupIsEnabled') ??
          false;
    }
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _windowsValue,
      ]);
      if (result.exitCode == 0) return true;
      final legacy = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _legacyWindowsValue,
      ]);
      return legacy.exitCode == 0;
    }
    if (Platform.isLinux) return _linuxFile.exists();
    throw const CoreException(
      'unsupported',
      'Launch at login is available on desktop',
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('launchAtStartupSetEnabled', {
        'setEnabledValue': enabled,
      });
    } else if (Platform.isWindows) {
      final result = await Process.run(
        'reg',
        enabled
            ? [
                'add',
                _registryKey,
                '/v',
                _windowsValue,
                '/t',
                'REG_SZ',
                '/d',
                '"${Platform.resolvedExecutable}"',
                '/f',
              ]
            : ['delete', _registryKey, '/v', _windowsValue, '/f'],
      );
      if (result.exitCode != 0 && enabled) {
        throw CoreException(
          'startup',
          'Unable to update launch at login: ${result.stderr}',
        );
      }
      if (!enabled) {
        await Process.run('reg', [
          'delete',
          _registryKey,
          '/v',
          _legacyWindowsValue,
          '/f',
        ]);
      }
    } else if (Platform.isLinux) {
      final file = _linuxFile;
      if (enabled) {
        final executable = Platform.resolvedExecutable
            .replaceAll('\\', r'\\')
            .replaceAll('"', r'\"')
            .replaceAll('`', r'\`')
            .replaceAll(r'$', r'\$')
            .replaceAll('%', '%%');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '[Desktop Entry]\nType=Application\nName=dclash\nExec="$executable"\nTerminal=false\nX-GNOME-Autostart-enabled=true\n',
        );
      } else if (await file.exists()) {
        await file.delete();
      }
    } else {
      throw const CoreException(
        'unsupported',
        'Launch at login is available on desktop',
      );
    }
  }
}
