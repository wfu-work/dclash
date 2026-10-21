import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';

class HelperManagementRows extends StatefulWidget {
  const HelperManagementRows({
    super.key,
    required this.coreActive,
    required this.onManage,
  });

  final bool coreActive;
  final Future<void> Function(bool uninstall) onManage;

  @override
  State<HelperManagementRows> createState() => _HelperManagementRowsState();
}

class _HelperManagementRowsState extends State<HelperManagementRows> {
  bool _busy = false;

  Future<void> _manage(bool uninstall) async {
    if (_busy || widget.coreActive) return;
    setState(() => _busy = true);
    try {
      await widget.onManage(uninstall);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AppSettingsRow(
        title: 'helperInstall'.tr,
        subtitle: (widget.coreActive ? 'helperStopFirst' : 'helperHint').tr,
        icon: AppIcons.admin,
        trailing: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: _busy || widget.coreActive ? null : () => _manage(false),
      ),
      AppSettingsRow(
        title: 'helperUninstall'.tr,
        icon: AppIcons.minusCircle,
        onTap: _busy || widget.coreActive ? null : () => _manage(true),
      ),
    ],
  );
}
