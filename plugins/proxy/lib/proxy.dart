import 'dart:io';

import 'proxy_platform_interface.dart';
import 'src/linux_proxy.dart';
import 'src/macos_proxy.dart';
import 'src/proxy_command.dart';
import 'src/windows_proxy.dart';

export 'src/proxy_command.dart' show ProxyExecutableChecker, ProxyProcessRunner;

class Proxy {
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  late final LinuxProxy _linuxProxy;
  late final MacosProxy _macosProxy;

  Proxy({
    ProxyProcessRunner? processRunner,
    ProxyExecutableChecker? executableChecker,
  }) {
    final commandRunner = ProxyCommandRunner(processRunner ?? Process.run);
    _linuxProxy = LinuxProxy(
      commandRunner: commandRunner,
      executableChecker: executableChecker,
    );
    _macosProxy = MacosProxy(commandRunner: commandRunner);
  }

  Future<bool> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    if (port < _minPort || port > _maxPort) {
      return false;
    }
    return switch (Platform.operatingSystem) {
      'macos' => await _macosProxy.start(port, bypassDomain),
      'linux' => await _linuxProxy.start(
        port,
        bypassDomain,
        desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
        homeDir: Platform.environment['HOME'],
      ),
      'windows' => await ProxyPlatform.instance.startProxy(
        port,
        windowsBypassList(bypassDomain),
      ),
      String() => false,
    };
  }

  Future<bool> stopProxy() async {
    return switch (Platform.operatingSystem) {
      'macos' => await _macosProxy.stop(),
      'linux' => await _linuxProxy.stop(
        desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
        homeDir: Platform.environment['HOME'],
      ),
      'windows' => await ProxyPlatform.instance.stopProxy(),
      String() => false,
    };
  }

  /// Clears only a dead macOS loopback proxy at this application's port.
  /// Unlike stopProxy, this also works after the owning runtime has gone away.
  Future<bool> recoverStaleProxy(int port) async {
    if (!Platform.isMacOS) return true;
    return _macosProxy.recoverStale(port);
  }
}
