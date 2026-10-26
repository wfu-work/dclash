import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/settings_service.dart';
import '../../widgets/app_widgets.dart';

class DashboardLayoutView extends StatefulWidget {
  const DashboardLayoutView({super.key, this.embedded = false, this.settings});

  final bool embedded;
  final SettingsService? settings;

  @override
  State<DashboardLayoutView> createState() => _DashboardLayoutViewState();
}

class _DashboardLayoutViewState extends State<DashboardLayoutView> {
  late final _settings = widget.settings ?? Get.find<SettingsService>();
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
      if (mounted) {
        if (widget.embedded) {
          AppMessage.success(context, 'saved'.tr);
        } else {
          Navigator.pop(context);
        }
      }
    } on Object catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPage(
      title: 'dashboardLayout'.tr,
      automaticallyImplyLeading: !widget.embedded,
      subtitle: 'dashboardLayoutHint'.tr,
      scroll: false,
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                  _cards
                    ..clear()
                    ..addAll(
                      (SettingsService.defaults['dashboardCards'] as List)
                          .cast<String>(),
                    );
                  _visible
                    ..clear()
                    ..addAll(_cards);
                }),
          child: Text('settingsRestoreLayout'.tr),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );
    return widget.embedded ? page : Scaffold(body: SafeArea(child: page));
  }
}
