import 'dart:convert';

import 'package:get/get.dart';

import '../../../services/core_ports.dart';

class FeedController extends GetxController {
  FeedController(this.core, {required this.dns});
  final CoreActivityPort core;
  final bool dns;
  final query = ''.obs;
  final paused = false.obs;
  List<Map<String, dynamic>> _snapshot = [];
  List<Map<String, dynamic>> get records =>
      dns ? core.dnsQueries : core.requests;
  List<Map<String, dynamic>> get visibleRecords {
    final search = query.value.trim().toLowerCase();
    return (paused.value ? _snapshot : records).reversed
        .where(
          (item) =>
              search.isEmpty ||
              encodeRecord(item).toLowerCase().contains(search),
        )
        .toList();
  }

  void togglePause() {
    if (!paused.value) {
      _snapshot = records
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    paused.toggle();
  }

  void clear() {
    records.clear();
    _snapshot = [];
    query.refresh();
  }

  static String encodeRecord(Map<String, dynamic> record) =>
      JsonEncoder.withIndent('  ', (value) => value.toString()).convert(record);

  static String value(Map<String, dynamic> item, List<String> keys) {
    final metadata = item['metadata'];
    for (final values in [item, if (metadata is Map) metadata]) {
      for (final key in keys) {
        final raw = values[key];
        if (raw == null) continue;
        final text = raw is List ? raw.join(', ') : raw.toString();
        if (text.isNotEmpty) return text;
      }
    }
    return '—';
  }
}
