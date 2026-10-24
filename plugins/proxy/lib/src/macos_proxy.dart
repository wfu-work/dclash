import 'dart:io';

import 'proxy_command.dart';

typedef ProxyEndpointChecker = Future<bool> Function(String host, int port);

class MacosProxy {
  final ProxyCommandRunner _commandRunner;
  final ProxyEndpointChecker _endpointInUse;
  Map<String, _ServiceSnapshot>? _saved;

  MacosProxy({
    required ProxyCommandRunner commandRunner,
    ProxyEndpointChecker? endpointInUse,
  }) : _commandRunner = commandRunner,
       _endpointInUse = endpointInUse ?? _isEndpointInUse;

  Future<bool> start(int port, List<String> bypassDomain) async {
    final services = await _networkServices();
    if (services == null || services.isEmpty) return false;
    final saved = {...?_saved};
    for (final service in services) {
      if (saved.containsKey(service)) continue;
      final snapshot = await _snapshot(service);
      if (snapshot == null) return false;
      saved[service] = snapshot;
    }
    _saved = saved;
    final succeeded = await _commandRunner.run(
      services.expand(
        (service) => MacosProxyCommands.buildStart(service, port, bypassDomain),
      ),
    );
    if (!succeeded) await stop();
    return succeeded;
  }

  Future<bool> stop() async {
    final saved = _saved;
    if (saved == null) return true;
    var restored = true;
    for (final entry in saved.entries) {
      if (!await entry.value.restore(_commandRunner, entry.key)) {
        restored = false;
      }
    }
    if (restored) _saved = null;
    return restored;
  }

  /// Repairs an abandoned local proxy even when its in-memory snapshot was
  /// lost on a previous run. A live listener may belong to another client.
  /// Only the app's port is eligible; PAC, bypasses and other proxies stay intact.
  Future<bool> recoverStale(int port) async {
    if (port < 1 || port > 65535) return false;
    final services = await _networkServices();
    if (services == null) return false;
    var succeeded = true;
    for (final service in services) {
      for (final kind in const ['web', 'secureweb', 'socksfirewall']) {
        final current = await _readProxy(service, kind);
        if (current == null) {
          succeeded = false;
          continue;
        }
        if (!current.isLocalEndpoint(port) ||
            await _endpointInUse(current.server, port)) {
          continue;
        }
        if (!await _commandRunner.run([
          ProxyCommand('/usr/sbin/networksetup', [
            '-set${kind}proxystate',
            service,
            'off',
          ]),
        ])) {
          succeeded = false;
          continue;
        }
        // networksetup can print an error while exiting successfully.
        final restored = await _readProxy(service, kind);
        if (restored == null || restored.isLocalEndpoint(port)) {
          succeeded = false;
        }
      }
    }
    return succeeded;
  }

  Future<_ProxySnapshot?> _readProxy(String service, String kind) async {
    try {
      final result = await _commandRunner.process('/usr/sbin/networksetup', [
        '-get${kind}proxy',
        service,
      ]);
      if (result.exitCode != 0) return null;
      return _ProxySnapshot.parse(
        result.stdout.toString(),
        requireUnauthenticated: false,
      );
    } on ProcessException {
      return null;
    }
  }

  static Future<bool> _isEndpointInUse(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host == '[::1]' ? '::1' : host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } on SocketException catch (error) {
      // Only connection refused proves there is no local listener. Timeouts
      // and other probe errors must not disable a potentially working proxy.
      return error.osError?.errorCode != 61;
    }
  }

  Future<_ServiceSnapshot?> _snapshot(String service) async {
    final proxies = <String, _ProxySnapshot>{};
    try {
      for (final kind in const ['web', 'secureweb', 'socksfirewall']) {
        final result = await _commandRunner.process('/usr/sbin/networksetup', [
          '-get${kind}proxy',
          service,
        ]);
        if (result.exitCode != 0) return null;
        final snapshot = _ProxySnapshot.parse(result.stdout.toString());
        if (snapshot == null) return null;
        proxies[kind] = snapshot;
      }
      final bypass = await _commandRunner.process('/usr/sbin/networksetup', [
        '-getproxybypassdomains',
        service,
      ]);
      if (bypass.exitCode != 0) return null;
      final text = bypass.stdout.toString().trim();
      return _ServiceSnapshot(
        proxies,
        text.startsWith("There aren't any bypass domains") || text.isEmpty
            ? const []
            : text.split('\n').map((line) => line.trim()).toList(),
      );
    } on ProcessException {
      return null;
    }
  }

  Future<List<String>?> _networkServices() async {
    try {
      final result = await _commandRunner.process('/usr/sbin/networksetup', [
        '-listallnetworkservices',
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      return MacosProxyCommands.parseNetworkServices(result.stdout.toString());
    } on ProcessException {
      return null;
    }
  }
}

class _ServiceSnapshot {
  _ServiceSnapshot(this.proxies, this.bypass);
  final Map<String, _ProxySnapshot> proxies;
  final List<String> bypass;

  Future<bool> restore(ProxyCommandRunner runner, String service) async {
    var restored = true;
    for (final entry in proxies.entries) {
      final value = entry.value;
      var endpointRestored = true;
      final state = '-set${entry.key}proxystate';
      if (!await runner.run([
        ProxyCommand('/usr/sbin/networksetup', [state, service, 'off']),
      ])) {
        restored = false;
      }
      if (value.server.isNotEmpty && value.port > 0) {
        endpointRestored = await runner.run([
          ProxyCommand('/usr/sbin/networksetup', [
            '-set${entry.key}proxy',
            service,
            value.server,
            '${value.port}',
          ]),
        ]);
        if (!endpointRestored) restored = false;
      }
      if (!await runner.run([
        ProxyCommand('/usr/sbin/networksetup', [
          state,
          service,
          value.enabled && endpointRestored ? 'on' : 'off',
        ]),
      ])) {
        restored = false;
      }
    }
    if (!await runner.run([
      MacosProxyCommands.buildProxyBypass(service, bypass),
    ])) {
      restored = false;
    }
    return restored;
  }
}

class _ProxySnapshot {
  _ProxySnapshot(this.enabled, this.server, this.port);
  final bool enabled;
  final String server;
  final int port;

  bool isLocalEndpoint(int expectedPort) =>
      enabled &&
      port == expectedPort &&
      const {
        '127.0.0.1',
        'localhost',
        '::1',
        '[::1]',
      }.contains(server.toLowerCase());

  static _ProxySnapshot? parse(
    String text, {
    bool requireUnauthenticated = true,
  }) {
    final values = <String, String>{};
    for (final line in text.split('\n')) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      values[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
    final enabled = values['Enabled'];
    final port = int.tryParse(values['Port'] ?? '');
    if ((enabled != 'Yes' && enabled != 'No') ||
        port == null ||
        !values.containsKey('Server') ||
        (requireUnauthenticated &&
            values['Authenticated Proxy Enabled'] != '0')) {
      return null;
    }
    // networksetup cannot retrieve saved credentials, so authenticated
    // configurations cannot be safely replaced and restored by this client.
    return _ProxySnapshot(enabled == 'Yes', values['Server']!, port);
  }
}

class MacosProxyCommands {
  static List<ProxyCommand> buildStart(
    String service,
    int port,
    List<String> bypassDomain,
  ) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxy',
        service,
        proxyHost,
        '$port',
      ]),
      buildProxyBypass(service, bypassDomain),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'on',
      ]),
    ];
  }

  static List<ProxyCommand> buildStop(String service) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setautoproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'off',
      ]),
      buildProxyBypass(service, const []),
    ];
  }

  static ProxyCommand buildProxyBypass(
    String service,
    List<String> bypassDomain,
  ) {
    return ProxyCommand('/usr/sbin/networksetup', [
      '-setproxybypassdomains',
      service,
      if (bypassDomain.isEmpty) 'Empty' else ...bypassDomain,
    ]);
  }

  static List<String> parseNetworkServices(String stdout) {
    return stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('*'))
        .where((line) => !line.startsWith('An asterisk '))
        .toList();
  }
}
