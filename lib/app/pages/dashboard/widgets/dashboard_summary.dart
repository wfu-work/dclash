import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../domains/clash_profile.dart';
import '../../../widgets/app_widgets.dart';
import '../dashboard_controller.dart';

/// Summary cards share a row; expanded details always use the full row below.
class DashboardSummary extends StatefulWidget {
  const DashboardSummary({
    super.key,
    required this.controller,
    required this.sections,
    required this.onOpenProfiles,
  });

  final DashboardController controller;
  final List<String> sections;
  final VoidCallback onOpenProfiles;

  @override
  State<DashboardSummary> createState() => _DashboardSummaryState();
}

class _DashboardSummaryState extends State<DashboardSummary> {
  bool _details = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final enlarged = MediaQuery.textScalerOf(context).scale(14) > 19;
      final paired =
          widget.sections.length == 2 && box.maxWidth >= 720 && !enlarged;
      final cardWidth = paired ? (box.maxWidth - 16) / 2 : box.maxWidth;
      final compact = cardWidth < 320 || enlarged;
      return Obx(() {
        final profile = widget.controller.profiles.active;
        final cards = [
          for (final section in widget.sections)
            section == 'currentProfile'
                ? _profile(context, profile, compact)
                : _outbound(context),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (paired)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[1]),
                  ],
                ),
              )
            else
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                cards[i],
              ],
            if (_details &&
                profile != null &&
                widget.sections.contains('currentProfile')) ...[
              const SizedBox(height: 16),
              _profileDetails(context, profile),
            ],
          ],
        );
      });
    },
  );

  Widget _title(BuildContext context, String label, IconData icon) => Row(
    children: [
      AppIcon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    ],
  );

  Widget _profile(BuildContext context, ClashProfile? profile, bool compact) {
    final theme = Theme.of(context);
    final action = Semantics(
      expanded: profile == null ? null : _details,
      child: TextButton.icon(
        key: const ValueKey('dashboardProfileDetailsAction'),
        onPressed: profile == null
            ? widget.onOpenProfiles
            : () => setState(() => _details = !_details),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          minimumSize: const Size(0, 36),
          textStyle: theme.textTheme.labelMedium,
        ),
        iconAlignment: IconAlignment.end,
        icon: AppIcon(
          profile == null
              ? AppIcons.chevronRight
              : _details
              ? AppIcons.chevronUp
              : AppIcons.chevronDown,
          size: 16,
        ),
        label: Text(
          (profile == null
                  ? 'browseProfiles'
                  : _details
                  ? 'dashboardCollapseDetails'
                  : 'dashboardProfileDetails')
              .tr,
        ),
      ),
    );
    final metadata = [
      if (profile?.source == ProfileSource.remote)
        _InfoField(
          label: 'profileDetailExpiry'.tr,
          value: profile!.expiresAt == null
              ? 'profileNoExpiry'.tr
              : _date(profile.expiresAt!),
        ),
      if (profile != null)
        _InfoField(
          label: 'profileDetailUpdated'.tr,
          value: profile.updatedAt == null
              ? 'profileNeverUpdated'.tr
              : _date(profile.updatedAt!),
        ),
    ];
    return AppCard(
      key: const ValueKey('dashboardProfileCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            _title(context, 'currentProfile'.tr, AppIcons.profile),
            Align(alignment: Alignment.centerRight, child: action),
          ] else
            Row(
              children: [
                Expanded(
                  child: _title(context, 'currentProfile'.tr, AppIcons.profile),
                ),
                const SizedBox(width: 8),
                action,
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                profile?.name ?? 'noProfile'.tr,
                style: theme.textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (profile != null)
                AppPill(label: 'profileSource_${profile.source.name}'.tr),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            profile == null
                ? 'addProfileHint'.tr
                : profile.total > 0
                ? 'dashboardQuota'.trParams({
                    'used': formatBytes(profile.used),
                    'total': formatBytes(profile.total),
                  })
                : '${'total'.tr} ${formatBytes(profile.used)}',
            style: theme.textTheme.bodySmall,
          ),
          if (profile != null && profile.total > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (profile.used / profile.total).clamp(0.0, 1.0),
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < metadata.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    metadata[i],
                  ],
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < metadata.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: metadata[i]),
                  ],
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _profileDetails(BuildContext context, ClashProfile profile) {
    final host = Uri.tryParse(profile.url)?.host;
    final fields = <(String, String)>[
      ('profileDetailSource'.tr, 'profileSource_${profile.source.name}'.tr),
      (
        'profileDetailUpdated'.tr,
        profile.updatedAt == null
            ? 'profileNeverUpdated'.tr
            : _date(profile.updatedAt!),
      ),
      if (profile.source == ProfileSource.remote) ...[
        (
          'profileDetailUpdateMode'.tr,
          profile.autoUpdateHours > 0
              ? 'profileUpdateEveryHours'.trParams({
                  'hours': '${profile.autoUpdateHours}',
                })
              : 'profileUpdateManual'.tr,
        ),
        (
          'profileDetailExpiry'.tr,
          profile.expiresAt == null
              ? 'profileNoExpiry'.tr
              : _date(profile.expiresAt!),
        ),
      ],
    ];
    return AppCard(
      key: const ValueKey('dashboardProfileDetails'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onOpenProfiles,
              icon: const AppIcon(AppIcons.chevronRight, size: 16),
              iconAlignment: IconAlignment.end,
              label: Text('browseProfiles'.tr),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final columns =
                  box.maxWidth >= 450 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 19
                  ? 2
                  : 1;
              return Wrap(
                spacing: 20,
                runSpacing: 16,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: (box.maxWidth - (columns - 1) * 20) / columns,
                      child: _InfoField(label: field.$1, value: field.$2),
                    ),
                  if (profile.source == ProfileSource.remote &&
                      host != null &&
                      host.isNotEmpty)
                    SizedBox(
                      width: box.maxWidth,
                      child: _InfoField(
                        label: 'profileSubscriptionUrl'.tr,
                        value: host,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _outbound(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final checking = controller.checking.value;
    final error = controller.outboundError.value;
    final ip = controller.outboundIp.value;
    final detectedAt = controller.outboundDetectedAt.value;
    final running = controller.core.running;
    final title = checking
        ? 'dashboardDetectingOutbound'.tr
        : error != null
        ? 'dashboardOutboundFailed'.tr
        : ip.isEmpty
        ? 'notDetected'.tr
        : ip;
    return AppCard(
      key: const ValueKey('dashboardOutboundCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: _title(context, 'currentOutbound'.tr, AppIcons.outbound),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: error != null ? theme.colorScheme.error : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (error != null)
                Text(
                  AppMessage.formatError(error),
                  key: const ValueKey('dashboardOutboundError'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              else
                Text(
                  !running
                      ? 'connectFirst'.tr
                      : detectedAt == null
                      ? 'dashboardOutboundHint'.tr
                      : 'dashboardOutboundUpdated'.trParams({
                          'time': MaterialLocalizations.of(context)
                              .formatTimeOfDay(
                                TimeOfDay.fromDateTime(detectedAt),
                                alwaysUse24HourFormat: true,
                              ),
                        }),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('dashboardDetectOutboundAction'),
                  onPressed: !running || checking ? null : _detectOutbound,
                  icon: checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.refresh, size: 16),
                  label: Text(
                    (error != null
                            ? 'retry'
                            : ip.isEmpty
                            ? 'dashboardDetectOutbound'
                            : 'dashboardRecheckOutbound')
                        .tr,
                  ),
                ),
                Text(
                  '127.0.0.1:${controller.settings.fields['mixedPort']}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _detectOutbound() async {
    try {
      await widget.controller.detectIp();
    } on Object {
      // The controller retains the error for the inline error and retry action.
    }
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _InfoField extends StatelessWidget {
  const _InfoField({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}
