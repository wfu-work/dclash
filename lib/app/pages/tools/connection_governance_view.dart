import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/clash_connection.dart';
import '../../../services/core_service.dart';
import '../../widgets/app_widgets.dart';

enum _ConnectionGroup { application, domain, node }

class ConnectionGovernanceView extends StatefulWidget {
  const ConnectionGovernanceView({super.key, this.core});
  final CoreService? core;
  @override
  State<ConnectionGovernanceView> createState() =>
      _ConnectionGovernanceViewState();
}

class _ConnectionGovernanceViewState extends State<ConnectionGovernanceView> {
  late final core = widget.core ?? Get.find<CoreService>();
  _ConnectionGroup group = _ConnectionGroup.application;
  String query = '';
  final closing = <String>{}.obs;

  String _name(ClashConnection connection) => switch (group) {
    _ConnectionGroup.application =>
      connection.process.isEmpty
          ? 'connectionGovernanceUnknown'.tr
          : connection.process.replaceAll('\\', '/').split('/').last,
    _ConnectionGroup.domain =>
      connection.host.isEmpty ? connection.destination : connection.host,
    _ConnectionGroup.node =>
      connection.chains.isEmpty
          ? 'connectionGovernanceDirect'.tr
          : connection.chains.first,
  };

  Future<void> _close(
    BuildContext context,
    List<ClashConnection> connections,
  ) async {
    if (connections.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'connectionGovernanceClose'.tr,
      message: 'connectionGovernanceCloseConfirm'.trParams({
        'count': '${connections.length}',
      }),
    );
    if (!confirmed || !mounted) return;
    closing.addAll(connections.map((connection) => connection.id));
    try {
      for (final connection in connections) {
        await core.closeConnection(connection.id);
      }
    } on Object catch (error) {
      if (mounted && messenger != null) {
        AppMessage.error(messenger.context, error);
      }
    } finally {
      closing.removeAll(connections.map((connection) => connection.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        maxContentWidth: 920,
        title: 'connectionGovernance'.tr,
        subtitle: 'connectionGovernanceHelp'.tr,
        child: Obx(() {
          final groups = <String, List<ClashConnection>>{};
          final search = query.trim().toLowerCase();
          for (final connection in core.connections) {
            final name = _name(connection);
            if (search.isNotEmpty &&
                !'$name ${connection.host} ${connection.chains.join(' ')}'
                    .toLowerCase()
                    .contains(search)) {
              continue;
            }
            (groups[name] ??= []).add(connection);
          }
          final rows = groups.entries.toList()
            ..sort((a, b) {
              final aTotal = a.value.fold(
                0,
                (sum, item) => sum + item.upload + item.download,
              );
              final bTotal = b.value.fold(
                0,
                (sum, item) => sum + item.upload + item.download,
              );
              return bTotal.compareTo(aTotal);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _ConnectionGroup.values)
                    ChoiceChip(
                      key: ValueKey('governanceGroup_${value.name}'),
                      label: Text('connectionGovernance_${value.name}'.tr),
                      selected: group == value,
                      onSelected: (_) => setState(() => group = value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              AppSearchField(
                onChanged: (value) => setState(() => query = value),
                hint: 'connectionGovernanceSearch'.tr,
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                AppEmpty(
                  icon: AppIcons.connections,
                  title: 'connectionGovernanceEmpty'.tr,
                  message: core.running
                      ? 'connectionGovernanceEmptyHelp'.tr
                      : 'featureStartCore'.tr,
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < rows.length; index++) ...[
                        _ConnectionGroupRow(
                          name: rows[index].key,
                          connections: rows[index].value,
                          closing: closing,
                          onClose: () => _close(context, rows[index].value),
                        ),
                        if (index + 1 < rows.length) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
    ),
  );
}

class _ConnectionGroupRow extends StatelessWidget {
  const _ConnectionGroupRow({
    required this.name,
    required this.connections,
    required this.closing,
    required this.onClose,
  });
  final String name;
  final List<ClashConnection> connections;
  final Set<String> closing;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final upload = connections.fold(0, (sum, item) => sum + item.upload);
    final download = connections.fold(0, (sum, item) => sum + item.download);
    final busy = connections.any(
      (connection) => closing.contains(connection.id),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          const AppIcon(AppIcons.connections, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  'connectionGovernanceSummary'.trParams({
                    'count': '${connections.length}',
                    'upload': formatBytes(upload),
                    'download': formatBytes(download),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'connectionGovernanceClose'.tr,
            onPressed: busy ? null : onClose,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppIcon(AppIcons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
