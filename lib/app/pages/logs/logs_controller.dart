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

  List<CoreLog> get visibleLogs {
    final search = query.value.trim().toLowerCase();
    return (paused.value ? _snapshot : core.logs).reversed
        .where(
          (log) =>
              (level.value == 'all' ||
                  log.level.toLowerCase() == level.value ||
                  (level.value == 'warning' &&
                      log.level.toLowerCase() == 'warn')) &&
              (search.isEmpty || log.message.toLowerCase().contains(search)),
        )
        .toList();
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
