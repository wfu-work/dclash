import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../domains/clash_connection.dart';
import '../../../widgets/app_widgets.dart';

class ConnectionDetails extends StatelessWidget {
  const ConnectionDetails({super.key, required this.connection});
  final ClashConnection connection;
  @override
  Widget build(BuildContext context) {
    final values = <String, String>{
      'connectionHost'.tr: connection.host,
      'connectionNetwork'.tr: connection.network.toUpperCase(),
      'connectionSource'.tr: connection.source,
      'connectionDestination'.tr: connection.destination,
      'connectionProcess'.tr: connection.process.isEmpty
          ? '—'
          : connection.process,
      'connectionRule'.tr: connection.rule,
      'connectionChains'.tr: connection.chains.reversed.join(' → '),
      'connectionUpload'.tr: formatBytes(connection.upload),
      'connectionDownload'.tr: formatBytes(connection.download),
      'connectionStarted'.tr: connection.startedAt.toLocal().toString(),
      'connectionId'.tr: connection.id,
    };
    return AlertDialog(
      title: Text('connectionDetails'.tr),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: values.entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 105,
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            entry.value.isEmpty ? '—' : entry.value,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            try {
              await Clipboard.setData(
                ClipboardData(
                  text: values.entries
                      .map((entry) => '${entry.key}: ${entry.value}')
                      .join('\n'),
                ),
              );
              if (context.mounted) {
                AppMessage.success(context, 'featureCopied'.tr);
              }
            } catch (error) {
              if (context.mounted) showAppError(context, error);
            }
          },
          icon: const AppIcon(AppIcons.copy, size: 17),
          label: Text('featureCopy'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text('featureDone'.tr),
        ),
      ],
    );
  }
}
