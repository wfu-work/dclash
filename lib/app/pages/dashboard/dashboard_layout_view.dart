import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/settings_service.dart';
import '../../widgets/app_widgets.dart';

class DashboardLayoutView extends StatefulWidget {
  const DashboardLayoutView({super.key});

  @override
  State<DashboardLayoutView> createState() => _DashboardLayoutViewState();
}

class _DashboardLayoutViewState extends State<DashboardLayoutView> {
  final _settings = Get.find<SettingsService>();
  late final List<String> _cards;
  late final Set<String> _visible;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _visible = Set<String>.from(_settings.fields['dashboardCards'] as List);
    _cards = [
      ..._visible,
      ...(SettingsService.defaults['dashboardCards'] as List)
          .cast<String>()
          .where((key) => !_visible.contains(key)),
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _settings.set(
        'dashboardCards',
        _cards.where(_visible.contains).toList(),
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        title: 'dashboardLayout'.tr,
        subtitle: 'dashboardLayoutHint'.tr,
        scroll: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: _saving || _visible.isEmpty ? null : _save,
            child: Text('save'.tr),
          ),
        ],
        child: ReorderableListView.builder(
          itemCount: _cards.length,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              _cards.insert(newIndex, _cards.removeAt(oldIndex));
            });
          },
          itemBuilder: (context, index) {
            final key = _cards[index];
            return Padding(
              key: ValueKey(key),
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: AppIcon(AppIcons.drag),
                      ),
                    ),
                    Expanded(child: Text(key.tr)),
                    AppSwitch(
                      value: _visible.contains(key),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              value ? _visible.add(key) : _visible.remove(key);
                            }),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
