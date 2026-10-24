import 'package:dclash_flutter/services/core_service.dart';

class DiagnosticCore extends CoreService {
  DiagnosticCore(super.profiles, super.settings, {super.preview});

  final calls = <(String, dynamic)>[];
  Map<String, dynamic> nativeRoute = {
    'core-epoch': 1,
    'picks-version': 1,
    'picks': <String, String>{},
  };
  Future<dynamic> Function(String, Map)? respond;

  @override
  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    calls.add((method, arguments));
    if (method == 'watchRoute') return Map<String, dynamic>.from(nativeRoute);
    if (respond != null) return respond!(method, arguments as Map);
    return method == 'probe'
        ? probe(arguments as Map)
        : [service((arguments as Map)['names'].single as String)];
  }

  Map<String, dynamic> probe(Map arguments) => {
    ...nativeRoute,
    'url': '${arguments['url']}',
    'status-code': 204,
    'delay': 42,
    'chains': ['Tokyo', 'Proxy'],
    'rule': 'DomainSuffix',
    'rule-payload': 'example.com',
  };

  Map<String, dynamic> service(String name) => {
    ...nativeRoute,
    'name': name,
    'status': 'available',
    'region': 'JP',
    'delay': 65,
    'chains': ['Tokyo', 'Proxy'],
    'checked-at': 1792713600000,
  };
}
