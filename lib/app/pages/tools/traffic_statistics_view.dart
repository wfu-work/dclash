import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../domains/traffic_statistics.dart';
import '../../../services/traffic_statistics_service.dart';
import '../../widgets/app_widgets.dart';

class TrafficStatisticsView extends StatefulWidget {
  const TrafficStatisticsView({super.key, this.statistics});
  final TrafficStatisticsService? statistics;

  @override
  State<TrafficStatisticsView> createState() => _TrafficStatisticsViewState();
}

class _TrafficStatisticsViewState extends State<TrafficStatisticsView> {
  late final statistics =
      widget.statistics ?? Get.find<TrafficStatisticsService>();
  TrafficPeriod _period = TrafficPeriod.today;
  TrafficDimension _dimension = TrafficDimension.application;
  TrafficSort _sort = TrafficSort.total;
  DateTime? _date;
  String _query = '';
  int _limit = 50;

  String _name(String value) => switch (value) {
    TrafficStatisticsService.unknown => 'trafficUnknown'.tr,
    TrafficStatisticsService.other => 'trafficOther'.tr,
    _ => value,
  };

  String _dateLabel(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatShortDate(date);

  Future<void> _retry() async {
    try {
      await statistics.flush();
    } on Object catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppPage(
        title: 'trafficStatistics'.tr,
        subtitle: 'trafficHelp'.tr,
        maxContentWidth: 920,
        child: Obx(() {
          statistics.revision.value;
          final daily = statistics.dailyUsage(_period);
          // The date can expire if the page stays open past midnight.
          final selectedDate = daily.any((day) => day.date == _date)
              ? _date
              : null;
          final usage = statistics.usage(_period, date: selectedDate);
          final allRanks = statistics.ranking(
            _dimension,
            _period,
            sort: _sort,
            date: selectedDate,
          );
          final query = _query.trim().toLowerCase();
          final ranks = allRanks
              .where((entry) => _name(entry.name).toLowerCase().contains(query))
              .toList();
          final maxRank = allRanks.fold(
            1,
            (maximum, entry) => math.max(maximum, entry.usage.valueFor(_sort)),
          );
          final maxDaily = daily.fold(
            1,
            (maximum, day) => math.max(maximum, day.usage.total),
          );
          final status = statistics.core.preview
              ? 'trafficPreview'
              : statistics.core.running
              ? 'trafficCollecting'
              : 'trafficStopped';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final period in TrafficPeriod.values)
                    ChoiceChip(
                      key: ValueKey('trafficPeriod_${period.name}'),
                      label: Text('trafficPeriod_${period.name}'.tr),
                      selected: _period == period,
                      onSelected: (_) => setState(() {
                        _period = period;
                        _date = null;
                        _limit = 50;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          selectedDate == null
                              ? 'trafficPeriod_${_period.name}'.tr
                              : _dateLabel(context, selectedDate),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        AppPill(label: status.tr),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth < 480
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 32) / 3;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final metric in [
                              ('trafficTotal', usage.total),
                              ('upload', usage.upload),
                              ('download', usage.download),
                            ])
                              SizedBox(
                                width: width,
                                child: Column(
                                  key: ValueKey('trafficSummary_${metric.$1}'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      metric.$1.tr,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatBytes(metric.$2),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (selectedDate != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _date = null),
                          child: Text('trafficAllDates'.tr),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (statistics.saveError.value) ...[
                const SizedBox(height: 16),
                AppMessage(
                  message: 'trafficSaveFailed'.tr,
                  tone: AppMessageTone.warning,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _retry,
                    child: Text('trafficRetrySave'.tr),
                  ),
                ),
              ],
              AppSection(
                title: 'trafficRankings'.tr,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final dimension in TrafficDimension.values)
                            ChoiceChip(
                              key: ValueKey(
                                'trafficDimension_${dimension.name}',
                              ),
                              label: Text(
                                'trafficDimension_${dimension.name}'.tr,
                              ),
                              selected: _dimension == dimension,
                              onSelected: (_) => setState(() {
                                _dimension = dimension;
                                _limit = 50;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppDropdown<TrafficSort>(
                          key: const ValueKey('trafficSort'),
                          value: _sort,
                          items: [
                            for (final sort in TrafficSort.values)
                              DropdownMenuItem(
                                value: sort,
                                child: Text('trafficSort_${sort.name}'.tr),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _sort = value;
                                _limit = 50;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('trafficSearch'),
                        decoration: InputDecoration(
                          labelText: 'trafficSearch'.tr,
                          prefixIcon: const AppIcon(AppIcons.search),
                        ),
                        onChanged: (value) => setState(() {
                          _query = value;
                          _limit = 50;
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (ranks.isEmpty)
                        AppEmpty(
                          icon: AppIcons.swap,
                          title:
                              (query.isEmpty
                                      ? 'trafficEmpty'
                                      : 'trafficNoResults')
                                  .tr,
                          message: query.isEmpty ? 'trafficEmptyHelp'.tr : null,
                        )
                      else
                        for (
                          var index = 0;
                          index < math.min(_limit, ranks.length);
                          index++
                        )
                          _RankingRow(
                            key: ValueKey('trafficRank_$index'),
                            index: index + 1,
                            name: _name(ranks[index].name),
                            usage: ranks[index].usage,
                            fraction:
                                ranks[index].usage.valueFor(_sort) / maxRank,
                          ),
                      if (ranks.length > _limit)
                        TextButton(
                          onPressed: () => setState(() => _limit += 50),
                          child: Text('trafficShowMore'.tr),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'trafficCoverage'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              AppSection(
                title: 'trafficDaily'.tr,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'trafficDailyHelp'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      for (final day in daily)
                        Semantics(
                          selected: selectedDate == day.date,
                          button: true,
                          child: InkWell(
                            key: ValueKey(
                              'trafficDay_${day.date.toIso8601String().substring(0, 10)}',
                            ),
                            onTap: () => setState(() {
                              _date = selectedDate == day.date
                                  ? null
                                  : day.date;
                              _limit = 50;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        _dateLabel(context, day.date),
                                        style: TextStyle(
                                          fontWeight: selectedDate == day.date
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                      Text(formatBytes(day.usage.total)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: day.usage.total / maxDaily,
                                    minHeight: 5,
                                  ),
                                  const SizedBox(height: 8),
                                  _TrafficBreakdown(usage: day.usage),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    ),
  );
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    super.key,
    required this.index,
    required this.name,
    required this.usage,
    required this.fraction,
  });
  final int index;
  final String name;
  final TrafficAmount usage;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Tooltip(
                message: name,
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(formatBytes(usage.total)),
            _TrafficBreakdown(usage: usage),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: fraction, minHeight: 4),
      ],
    ),
  );
}

class _TrafficBreakdown extends StatelessWidget {
  const _TrafficBreakdown({required this.usage});
  final TrafficAmount usage;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      Text(
        '${'upload'.tr} ↑ ${formatBytes(usage.upload)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Text(
        '${'download'.tr} ↓ ${formatBytes(usage.download)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
