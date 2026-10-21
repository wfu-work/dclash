import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../widgets/app_widgets.dart';
import 'profile_editor.dart';

class EffectiveConfigView extends StatefulWidget {
  const EffectiveConfigView({
    super.key,
    required this.name,
    required this.displayContent,
    required this.exportContent,
    required this.onExport,
  });
  final String name, displayContent, exportContent;
  final Future<bool> Function() onExport;

  @override
  State<EffectiveConfigView> createState() => _EffectiveConfigViewState();
}

class _EffectiveConfigViewState extends State<EffectiveConfigView> {
  late final _content = TextEditingController(text: widget.displayContent);
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final exported = await widget.onExport();
      if (exported && mounted) {
        AppMessage.success(context, 'featureExported'.tr);
      }
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.exportContent));
      if (mounted) {
        AppMessage.success(context, 'featureCopied'.tr);
      }
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 1000,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'profileAction_effective'.tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'featureDone'.tr,
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(AppIcons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'profileEffectiveHelp'.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ProfileCodeEditor(controller: _content, readOnly: true),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _copy,
                  icon: const AppIcon(AppIcons.copy, size: 18),
                  label: Text('featureCopy'.tr),
                ),
                FilledButton.icon(
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.share, size: 18),
                  label: Text('profileAction_effectiveExport'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
