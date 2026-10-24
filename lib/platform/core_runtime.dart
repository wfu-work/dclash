import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:proxy/proxy.dart';
import 'package:rust_api/rust_api.dart';

import 'core_rpc.dart';
import 'helper_client.dart';

abstract interface class CoreRuntime {
  Stream<Map<String, dynamic>> get events;
  void cancelPendingStart();
  Future<void> open(String homeDirectory, Map<String, dynamic> fields);
  Future<dynamic> invoke(String method, [dynamic arguments]);
  Future<void> start(Map<String, dynamic> fields);
  Future<void> stop();
  Future<void> close();
  Future<void> setSystemProxy(bool enabled, Map<String, dynamic> fields);
}

CoreRuntime createCoreRuntime() {
  if (Platform.isAndroid) return AndroidCoreRuntime();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return DesktopCoreRuntime();
  }
  throw const CoreException(
    'unsupported',
    'This platform does not support the DClash core',
  );
}

class DesktopCoreRuntime implements CoreRuntime {
  DesktopCoreRuntime({Proxy? proxy}) : _proxy = proxy ?? Proxy();
  IpcServer? _server;
  CoreRpc? _rpc;
  Process? _process;
  StreamSubscription<IpcEvent>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _rpcEvents;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Proxy _proxy;
  bool _proxyOwned = false;
  int? _proxyPort;
  bool _closing = false;
  bool _cancelled = false;
  Completer<void>? _connecting;
  HelperClient? _helper;
  String? _session;
  @override
  void cancelPendingStart() {
    _cancelled = true;
    final connecting = _connecting;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(
        const CoreException('cancelled', 'Core start was superseded'),
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  static String get artifactDirectory {
    final executable = p.dirname(Platform.resolvedExecutable);
    return Platform.isMacOS
        ? executable
        : p.join(executable, Platform.isLinux ? 'lib' : '');
  }

  static String get corePath => p.join(
    artifactDirectory,
    Platform.isWindows ? 'DClashCore.exe' : 'DClashCore',
  );

  @override
  Future<void> open(String homeDirectory, Map<String, dynamic> fields) async {
    _proxyPort = (fields['mixedPort'] as num?)?.toInt() ?? 7890;
    if (!await File(corePath).exists()) {
      throw const CoreException(
        'missing_core',
        'DClashCore is missing. Build the native core before connecting.',
      );
    }
    await ensureRustLibInitialized();
    if (_cancelled) {
      throw const CoreException('cancelled', 'Core start was superseded');
    }
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final address = Platform.isWindows
        ? r'\\.\pipe\DClashCore_' + nonce
        : '/tmp/DClashSocket_${random.nextInt(2000000000)}.sock';
    final connected = _connecting = Completer<void>();
    final ready = connected.future.timeout(const Duration(seconds: 45));
    ready.ignore();
    final server = _server = await IpcServer.bind(address: address);
    final rpc = _rpc = CoreRpc(
      send: (frame) => server.send(message: frame),
      homeDirectory: homeDirectory,
    );
    _rpcEvents = rpc.events.listen(_events.add);
    _subscription = server.events().listen(
      (event) {
        switch (event.kind) {
          case IpcEventKind.connected:
            if (!connected.isCompleted) connected.complete();
          case IpcEventKind.message:
            unawaited(rpc.receive(event.payload));
          case IpcEventKind.disconnected:
          case IpcEventKind.failed:
            final failure = CoreException(
              'disconnected',
              event.error ?? 'Core process disconnected',
            );
            rpc.fail(failure);
            if (!connected.isCompleted) connected.completeError(failure);
            if (!_closing) {
              _events.add({'type': 'crash', 'data': failure.toString()});
            }
        }
      },
      onError: (Object error, StackTrace stack) {
        rpc.fail(error, stack);
        if (!connected.isCompleted) connected.completeError(error, stack);
      },
    );
    // The connection listener is registered before launching the sidecar.
    if (fields['tunEnabled'] == true &&
        (Platform.isLinux || Platform.isWindows)) {
      _helper = HelperClient(artifactDirectory);
      _session = nonce;
      await _helper!.start(nonce, address);
    } else {
      final elevated = Platform.isMacOS && fields['tunEnabled'] == true;
      final command = 'exec ${_shellQuote(corePath)} ${_shellQuote(address)}';
      final process = _process = elevated
          ? await Process.start('/usr/bin/osascript', [
              '-e',
              'do shell script ${jsonEncode(command)} with administrator privileges',
            ])
          : await Process.start(corePath, [address]);
      process.stdout.listen((_) {});
      process.stderr.transform(utf8.decoder).listen((text) {
        if (text.isNotEmpty && !_closing) {
          _events.add({
            'type': 'log',
            'data': {'LogLevel': 'warning', 'Payload': text.trim()},
          });
        }
      });
      unawaited(
        process.exitCode.then((code) {
          if (!connected.isCompleted) {
            connected.completeError(
              CoreException(
                'process_exit',
                'Core exited before connecting ($code)',
              ),
            );
          }
        }),
      );
    }
    await ready;
    await invoke('initClash', {'home-dir': homeDirectory, 'version': 0});
  }

  static String _shellQuote(String text) =>
      "'${text.replaceAll("'", "'\\''")}'";
  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) {
    final rpc = _rpc;
    if (rpc == null) {
      throw const CoreException('not_ready', 'Core is not connected');
    }
    return rpc.invoke(method, arguments);
  }

  @override
  Future<void> start(Map<String, dynamic> fields) async {
    _proxyPort = (fields['mixedPort'] as num?)?.toInt() ?? 7890;
    await invoke('startListener');
    if (fields['systemProxy'] == true) await setSystemProxy(true, fields);
  }

  @override
  Future<void> setSystemProxy(bool enabled, Map<String, dynamic> fields) async {
    if (enabled) {
      final port = (fields['mixedPort'] as num?)?.toInt() ?? 7890;
      if (port < 1 || port > 65535) {
        throw const CoreException('system_proxy', 'Invalid system proxy port');
      }
      _proxyOwned = true;
      try {
        if (!await _proxy.startProxy(
          port,
          List<String>.from(fields['bypassDomains'] as List? ?? []),
        )) {
          throw const CoreException(
            'system_proxy',
            'Unable to enable the system proxy',
          );
        }
      } catch (e) {
        try {
          await setSystemProxy(false, const {});
        } catch (cleanup) {
          throw CoreException('system_proxy', '$e; proxy cleanup: $cleanup');
        }
        rethrow;
      }
      return;
    }
    if (!_proxyOwned) return;
    if (!await _proxy.stopProxy()) {
      throw const CoreException(
        'system_proxy',
        'Unable to restore the system proxy',
      );
    }
    _proxyOwned = false;
  }

  @override
  Future<void> stop() async {
    await setSystemProxy(false, const {});
    if (_rpc != null) await invoke('stopListener');
    await _recoverStaleProxy();
  }

  Future<void> _recoverStaleProxy() async {
    final port = _proxyPort;
    if (port != null && !await _proxy.recoverStaleProxy(port)) {
      throw const CoreException(
        'system_proxy',
        '无法清理残留的系统代理，请检查 macOS 网络代理设置后重试。',
      );
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    cancelPendingStart();
    Object? failure;
    try {
      await setSystemProxy(false, const {});
    } catch (e) {
      failure = e;
    }
    try {
      if (_rpc != null) await invoke('shutdown');
    } catch (_) {
      /* A crashed process cannot acknowledge shutdown. */
    }
    await _rpc?.close();
    await _server?.close();
    await _subscription?.cancel();
    await _rpcEvents?.cancel();
    final helper = _helper;
    if (helper != null && _session != null) {
      try {
        await helper.stop(_session!);
        helper.close();
        _helper = null;
      } catch (e) {
        failure ??= e;
      }
    }
    final process = _process;
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          failure ??= const CoreException(
            'process_exit',
            'Owned core process did not exit',
          );
        }
      }
    }
    try {
      await _recoverStaleProxy();
    } catch (e) {
      failure ??= e;
    }
    _rpc = null;
    _server = null;
    if (failure == null) _process = null;
    await _events.close();
    if (failure != null) throw failure;
  }
}

class AndroidCoreRuntime implements CoreRuntime {
  static const _service = MethodChannel('com.cloudrift.dclash/service');
  static const _core = MethodChannel('com.cloudrift.dclash/core');
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  CoreRpc? _rpc;
  StreamSubscription<Map<String, dynamic>>? _rpcEvents;
  int _revision = 0;
  bool _wanted = false;
  @override
  void cancelPendingStart() {
    if (!_wanted) return;
    _wanted = false;
    unawaited(
      _service.invokeMethod<bool>('stop', ++_revision).then((_) {}).catchError((
        Object e,
      ) {
        _rpc?.fail(e);
      }),
    );
  }

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Future<void> open(String homeDirectory, Map<String, dynamic> fields) async {
    await ensureRustLibInitialized();
    final rpc = _rpc = CoreRpc(
      homeDirectory: homeDirectory,
      send: (bytes) {
        unawaited(
          _core
              .invokeMethod<Uint8List>('invokeMethod', utf8.decode(bytes))
              .then((reply) {
                if (reply == null) {
                  throw const CoreException(
                    'empty_response',
                    'Android core returned no response',
                  );
                }
                return rpcReceive(reply);
              })
              .catchError((Object error, StackTrace stack) {
                _rpc?.fail(error, stack);
              }),
        );
      },
    );
    _rpcEvents = rpc.events.listen(_events.add);
    _service.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is Uint8List) {
        await rpc.receive(call.arguments as Uint8List);
      }
      if (call.method == 'stopped' && _wanted && call.arguments == _revision) {
        _events.add({'type': 'crash', 'data': 'Android VPN service stopped'});
      }
    });
    final error = await _service.invokeMethod<String>('init');
    if (error != null && error.isNotEmpty) {
      throw CoreException('android_init', error);
    }
    await invoke('initClash', {'home-dir': homeDirectory, 'version': 0});
  }

  Future<void> rpcReceive(Uint8List bytes) async => _rpc?.receive(bytes);
  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) {
    final rpc = _rpc;
    if (rpc == null) {
      throw const CoreException('not_ready', 'Android core is not connected');
    }
    return rpc.invoke(method, arguments);
  }

  @override
  Future<void> start(Map<String, dynamic> fields) async {
    final state = {
      'currentProfileName': fields['profileName'] ?? 'DClash',
      'setupParams': {
        'test-url': fields['testUrl'] ?? 'https://www.gstatic.com/generate_204',
        'selected-map': <String, String>{},
      },
      'vpnOptions': {
        'enable': fields['tunEnabled'] == true,
        'port': fields['mixedPort'] ?? 7890,
        'ipv6': fields['ipv6'] == true,
        'dnsHijacking': true,
        'accessControlProps': {
          'enable': fields['accessControlEnabled'] == true,
          'mode': fields['accessControlMode'] ?? 'rejectSelected',
          'acceptList': fields['accessControlMode'] == 'acceptSelected'
              ? fields['accessControlPackages'] ?? <String>[]
              : <String>[],
          'rejectList': fields['accessControlMode'] == 'rejectSelected'
              ? fields['accessControlPackages'] ?? <String>[]
              : <String>[],
        },
        'allowBypass': fields['allowBypass'] == true,
        'systemProxy': fields['systemProxy'] == true,
        'bypassDomain': fields['bypassDomains'] ?? <String>[],
        'stack': fields['stack'] ?? 'mixed',
        'routeAddress': <String>[],
      },
    };
    final syncError = await _service.invokeMethod<String>(
      'syncState',
      jsonEncode(state),
    );
    if (syncError != null && syncError.isNotEmpty) {
      throw CoreException('android_state', syncError);
    }
    _wanted = true;
    final accepted = await _service.invokeMethod<bool>('start', ++_revision);
    if (accepted != true) {
      throw const CoreException(
        'android_start',
        'Android service rejected start',
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (_wanted && DateTime.now().isBefore(deadline)) {
      if ((await _service.invokeMethod<int>('getRunTime') ?? 0) > 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw const CoreException(
      'android_start',
      'VPN permission was denied or the Android service could not start',
    );
  }

  @override
  Future<void> setSystemProxy(bool enabled, Map<String, dynamic> fields) async {
    throw const CoreException(
      'restart_required',
      'Android VPN settings require a service restart',
    );
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    if (await _service.invokeMethod<bool>('stop', ++_revision) != true) {
      throw const CoreException(
        'android_stop',
        'Android service rejected stop',
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if ((await _service.invokeMethod<int>('getRunTime') ?? 0) == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const CoreException('android_stop', 'Android service did not stop');
  }

  @override
  Future<void> close() async {
    _service.setMethodCallHandler(null);
    await _service.invokeMethod<bool>('shutdown');
    await _rpcEvents?.cancel();
    await _rpc?.close();
    _rpc = null;
    await _events.close();
  }
}
