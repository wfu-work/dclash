import 'package:dclash_flutter/domains/network_health.dart';
import 'package:dclash_flutter/platform/network_health_host.dart';

class FakeHealthHost implements NetworkHealthHost {
  final calls = <String>[];
  Future<void> Function(int)? listener;
  Future<List<String>> Function(String)? dns;
  Future<SystemProxySnapshot?> Function()? proxy;

  static const matchingProxy = SystemProxySnapshot(
    http: SystemProxyEndpoint(enabled: true, host: '127.0.0.1', port: 7890),
    https: SystemProxyEndpoint(enabled: true, host: '127.0.0.1', port: 7890),
  );

  @override
  Future<void> checkListener(int port) async {
    calls.add('listener:$port');
    await listener?.call(port);
  }

  @override
  Future<List<String>> lookup(String host) async {
    calls.add('dns:$host');
    return dns == null ? ['203.0.113.1'] : await dns!(host);
  }

  @override
  Future<SystemProxySnapshot?> systemProxy() async {
    calls.add('proxy');
    return proxy == null ? matchingProxy : await proxy!();
  }
}
