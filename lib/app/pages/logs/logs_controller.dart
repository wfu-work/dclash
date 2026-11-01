import 'package:get/get.dart';

import '../../../domains/clash_connection.dart';
import '../../../services/core_ports.dart';

class LogsController extends GetxController {
  LogsController(this.core);
  final CoreActivityPort core;
  final query = ''.obs;
  final level = 'all'.obs;
  final paused = false.obs;
  List<CoreLog> _snapshot = [];
  final Expando<String> _normalizedMessages = Expando<String>();

  List<CoreLog> get visibleLogs {
    final search = query.value.trim().toLowerCase();
    return (paused.value ? _snapshot : core.logs).reversed
        .where(
          (log) =>
              (level.value == 'all' ||
                  log.level.toLowerCase() == level.value ||
                  (level.value == 'warning' &&
                      log.level.toLowerCase() == 'warn')) &&
              (search.isEmpty || _normalizedMessage(log).contains(search)),
        )
        .toList();
  }

  String _normalizedMessage(CoreLog log) {
    final cached = _normalizedMessages[log];
    if (cached != null) return cached;
    final value = log.message.toLowerCase();
    _normalizedMessages[log] = value;
    return value;
  }

  void togglePause() {
    if (!paused.value) _snapshot = core.logs.toList();
    paused.toggle();
  }

  void clear() {
    core.logs.clear();
    _snapshot = [];
    query.refresh();
  }

  String format(CoreLog log) =>
      '${log.time.toLocal().toIso8601String()} [${log.level.toUpperCase()}] ${log.message}';
  String get exportText => visibleLogs.reversed.map(format).join('\n');
}
