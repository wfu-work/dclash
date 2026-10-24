import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domains/network_health.dart';

abstract interface class NetworkHealthHost {
  Future<void> checkListener(int port);
  Future<List<String>> lookup(String host);

  /// Null means this desktop environment cannot be inspected reliably.
  Future<SystemProxySnapshot?> systemProxy();
}

typedef HealthCommandRunner =
    Future<String> Function(String executable, List<String> arguments);

class IoNetworkHealthHost implements NetworkHealthHost {
  IoNetworkHealthHost({
    String? operatingSystem,
    String? desktop,
    HealthCommandRunner? commandRunner,
  }) : _os = operatingSystem ?? Platform.operatingSystem,
       _desktop = desktop ?? Platform.environment['XDG_CURRENT_DESKTOP'] ?? '',
       _run = commandRunner ?? _runCommand;

  static const deadline = Duration(seconds: 3);
  final String _os, _desktop;
  final HealthCommandRunner _run;

  @override
  Future<void> checkListener(int port) async {
    final socket = await Socket.connect('127.0.0.1', port, timeout: deadline);
    socket.destroy();
  }

  @override
  Future<List<String>> lookup(String host) async =>
      (await InternetAddress.lookup(
        host,
      ).timeout(deadline)).map((address) => address.address).toSet().toList();

  static Future<String> _runCommand(
    String executable,
    List<String> args,
  ) async {
    final process = await Process.start(executable, args);
    try {
      final output = await Future.wait<Object>([
        process.exitCode,
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.transform(utf8.decoder).join(),
      ]).timeout(deadline);
      if (output[0] != 0) throw StateError('System proxy inspection failed');
      return output[1] as String;
    } finally {
      process.kill();
    }
  }

  Future<String> _command(String executable, List<String> args) =>
      _run(executable, args).timeout(deadline);

  @override
  Future<SystemProxySnapshot?> systemProxy() async {
    if (_os == 'macos') {
      final output = await _command('/usr/sbin/scutil', ['--proxy']);
      final fields = <String, String>{};
      var depth = 0;
      for (final line in const LineSplitter().convert(output)) {
        final trimmed = line.trim();
        // Scoped / supplemental interface dictionaries are not the effective
        // top-level proxy. Do not let them overwrite the observed values.
        if (depth == 1) {
          final match = RegExp(r'^(\w+)\s*:\s*(.*)$').firstMatch(trimmed);
          if (match != null) fields[match[1]!] = match[2]!.trim();
        }
        if (trimmed.endsWith('{')) depth++;
        if (trimmed == '}') depth--;
      }
      if (!output.contains('<dictionary>')) {
        throw const FormatException('Invalid scutil proxy response');
      }
      SystemProxyEndpoint endpoint(String prefix) => SystemProxyEndpoint(
        enabled: fields['${prefix}Enable'] == '1',
        host: fields['${prefix}Proxy'] ?? '',
        port: int.tryParse(fields['${prefix}Port'] ?? '') ?? 0,
      );
      return SystemProxySnapshot(
        http: endpoint('HTTP'),
        https: endpoint('HTTPS'),
        automatic:
            fields['ProxyAutoConfigEnable'] == '1' ||
            fields['ProxyAutoDiscoveryEnable'] == '1',
        otherEnabled: fields['SOCKSEnable'] == '1',
      );
    }
    if (_os == 'windows') {
      // Inspect WinINet, the same per-user settings used by the proxy plugin.
      final output = await _command('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" | Select-Object ProxyEnable,ProxyServer,AutoConfigURL,AutoDetect | ConvertTo-Json -Compress',
      ]);
      final fields = jsonDecode(output) as Map;
      final servers = '${fields['ProxyServer'] ?? ''}';
      SystemProxyEndpoint endpoint(String protocol) {
        final entries = servers.split(';');
        final server = entries
            .firstWhere(
              (entry) => entry.startsWith('$protocol='),
              orElse: () =>
                  entries.length == 1 && !servers.contains('=') ? servers : '',
            )
            .replaceFirst('$protocol=', '');
        final uri = Uri.tryParse('http://$server');
        return SystemProxyEndpoint(
          enabled: fields['ProxyEnable'] == 1 && server.isNotEmpty,
          host: uri?.host ?? '',
          port: uri != null && uri.hasPort ? uri.port : 0,
        );
      }

      return SystemProxySnapshot(
        http: endpoint('http'),
        https: endpoint('https'),
        automatic:
            '${fields['AutoConfigURL'] ?? ''}'.isNotEmpty ||
            fields['AutoDetect'] == 1,
        otherEnabled: fields['ProxyEnable'] == 1 && servers.contains('socks='),
      );
    }
    if (_os == 'linux') {
      final desktop = _desktop.toLowerCase();
      final String schema;
      if (desktop.contains('kde')) return null;
      if (desktop.contains('mate')) {
        schema = 'org.mate.system.proxy';
      } else if (desktop.contains('gnome') ||
          desktop.contains('cinnamon') ||
          desktop.contains('budgie') ||
          desktop.contains('unity')) {
        schema = 'org.gnome.system.proxy';
      } else {
        return null;
      }
      Future<String> read(String path, String key) async => (await _command(
        'gsettings',
        ['get', path, key],
      )).trim().replaceAll(RegExp(r"^'|'$"), '');
      final mode = await read(schema, 'mode');
      if (!const ['none', 'manual', 'auto'].contains(mode)) {
        throw const FormatException('Invalid system proxy mode');
      }
      if (mode != 'manual') {
        return SystemProxySnapshot(
          http: const SystemProxyEndpoint(enabled: false),
          https: const SystemProxyEndpoint(enabled: false),
          automatic: mode == 'auto',
        );
      }
      Future<SystemProxyEndpoint> endpoint(String protocol) async =>
          SystemProxyEndpoint(
            enabled: mode == 'manual',
            host: await read('$schema.$protocol', 'host'),
            port: int.tryParse(await read('$schema.$protocol', 'port')) ?? 0,
          );
      final endpoints = await Future.wait([
        endpoint('http'),
        endpoint('https'),
      ]);
      return SystemProxySnapshot(
        http: endpoints[0],
        https: endpoints[1],
        automatic: mode == 'auto',
      );
    }
    return null;
  }
}
