import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/app_widgets.dart';

class LicensesView extends StatefulWidget {
  const LicensesView({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<LicensesView> createState() => _LicensesViewState();
}

class _LicensesViewState extends State<LicensesView> {
  late Future<List<_ComponentLicenses>> _licenses = _loadLicenses();

  Future<List<_ComponentLicenses>> _loadLicenses() async {
    final components = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        components.putIfAbsent(package, () => []).add(entry);
      }
    }
    final names = components.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final name in names) _ComponentLicenses(name, components[name]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPage(
      title: 'thirdPartyLicenses'.tr,
      maxContentWidth: 820,
      automaticallyImplyLeading: !widget.embedded,
      scroll: false,
      child: FutureBuilder<List<_ComponentLicenses>>(
        future: _licenses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('licensesLoadFailed'.tr),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        setState(() => _licenses = _loadLicenses()),
                    child: Text('retry'.tr),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final components = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Text(
                  'thirdPartyLicensesHint'.tr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: components.isEmpty
                      ? Center(child: Text('licensesEmpty'.tr))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: components.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final component = components[index];
                            return AppSettingsRow(
                              title: component.name,
                              icon: AppIcons.code,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _LicenseDetails(component: component),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return widget.embedded ? page : Scaffold(body: SafeArea(child: page));
  }
}

class _ComponentLicenses {
  const _ComponentLicenses(this.name, this.entries);

  final String name;
  final List<LicenseEntry> entries;
}

class _LicenseDetails extends StatelessWidget {
  const _LicenseDetails({required this.component});

  final _ComponentLicenses component;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        title: component.name,
        maxContentWidth: 820,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < component.entries.length; i++) ...[
                if (i > 0) const Divider(height: 32),
                for (final paragraph in component.entries[i].paragraphs)
                  Padding(
                    padding: EdgeInsets.only(
                      left: paragraph.indent < 0 ? 0 : paragraph.indent * 12.0,
                      bottom: 12,
                    ),
                    child: SelectableText(
                      paragraph.text,
                      textAlign:
                          paragraph.indent == LicenseParagraph.centeredIndent
                          ? TextAlign.center
                          : TextAlign.start,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
