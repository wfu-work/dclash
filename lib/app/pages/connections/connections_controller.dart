import 'package:get/get.dart';

import '../../../domains/clash_connection.dart';
import '../../../services/core_service.dart';

class ConnectionsController extends GetxController {
  ConnectionsController(this.core);
  final CoreService core;
  final query = ''.obs;
  final sort = 'recent'.obs;
  final closing = <String>{}.obs;
  final closingAll = false.obs;

  List<ClashConnection> get visibleConnections {
    final search = query.value.trim().toLowerCase();
    final list = core.connections
        .where(
          (item) =>
              search.isEmpty ||
              '${item.host} ${item.source} ${item.destination} ${item.rule} ${item.process} ${item.chains.join(' ')}'
                  .toLowerCase()
                  .contains(search),
        )
        .toList();
    switch (sort.value) {
      case 'recent':
        list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      case 'download':
        list.sort((a, b) => b.download.compareTo(a.download));
      case 'upload':
        list.sort((a, b) => b.upload.compareTo(a.upload));
    }
    return list;
  }

  Future<void> closeConnection(String id) async {
    if (!closing.add(id)) return;
    try {
      await core.closeConnection(id);
    } finally {
      closing.remove(id);
    }
  }

  Future<void> closeAll() async {
    if (closingAll.value) return;
    closingAll.value = true;
    try {
      await core.closeAll();
    } finally {
      closingAll.value = false;
    }
  }
}
