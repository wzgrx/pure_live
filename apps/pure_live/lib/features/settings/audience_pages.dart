import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// "观看数据与排行口径" (3.x `AudienceMetricSettingsPage`, U.6c c15): the two
// ways of showing and ranking, a switch for each platform that reports a
// real online count, the platforms that only report heat in one row, and
// what each platform reports on a page of its own.

/// 3.x's order of the platforms (its eight defaults first).
const List<String> _legacyOrder = [
  'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto', //
  'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'looklive',
];

/// The platforms of the app, 3.x's first, then the rest in the order of
/// [audienceCapabilities].
List<String> audiencePlatformOrder(Iterable<String> known) {
  final ids = known.toSet();
  return [
    for (final id in _legacyOrder)
      if (ids.contains(id)) id,
    for (final id in audienceCapabilities.keys)
      if (ids.contains(id) && !_legacyOrder.contains(id)) id,
  ];
}

/// "来源：…" of a platform.
String audienceSourceText(String id) => i18n(switch (AudiencePlatformCapability.of(id).onlineAvailability) {
  AudienceOnlineAvailability.roomList => 'audience_source_room_list',
  AudienceOnlineAvailability.roomRealtime => 'audience_source_room_realtime',
  AudienceOnlineAvailability.unsupported => 'audience_source_not_exposed',
});

/// The name of a platform.
String audiencePlatformName(WidgetRef ref, String id) =>
    platformName(id, fallback: ref.read(sitesProvider).maybeOf(id)?.name);

/// One of "平台热度优先" and "真实在线人数优先" (a radio row).
class AudienceModeTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, required this.online, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The "real online count" option.
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = watchSetting(ref, Settings.preferRealOnlineCounts) == online;
    final colors = Theme.of(context).colorScheme;
    return SettingsRow(
      key: entry.rowKey,
      leading: Icon(
        selected ? AppIcons.choiceOn : AppIcons.choiceOff,
        size: 22,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: entry.titleText,
      subtitle: entry.descriptionText,
      onTap: () => writeSetting(ref, Settings.preferRealOnlineCounts, online),
    );
  }
}

/// A switch for each platform with a real online count (20, 3.x listed 19
/// of which 10 could never be switched on): logo, name, where the count
/// comes from. Greyed out while popularity comes first.
class AudiencePlatformsTile extends ConsumerWidget {
  /// Creates the rows.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = watchSetting(ref, Settings.realOnlinePlatforms);
    final online = watchSetting(ref, Settings.preferRealOnlineCounts);
    final ids = [
      for (final id in audiencePlatformOrder(ref.read(sitesProvider).ids))
        if (AudiencePlatformCapability.of(id).supportsConcurrentOnline) id,
    ];
    final divider = Padding(
      padding: const EdgeInsetsDirectional.only(start: 56),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
      ),
    );
    return Column(
      key: entry.rowKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, id) in ids.indexed) ...[
          if (index > 0) divider,
          SettingsSwitchRow(
            key: ValueKey('settings-audience-$id'),
            leading: PlatformLogo(id),
            title: audiencePlatformName(ref, id),
            subtitle: audienceSourceText(id),
            value: selected.contains(id),
            enabled: online,
            disabledReason: i18n('settings_audience_needs_online'),
            onChanged: (on) => writeSetting(ref, Settings.realOnlinePlatforms, [
              for (final value in selected)
                if (value != id) value,
              if (on) id,
            ]),
          ),
        ],
      ],
    );
  }
}

/// The platforms that only report heat or cumulative views, in one row:
/// how many, their names and logos (U.6c X3).
class AudienceHeatOnlyTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = [
      for (final id in audiencePlatformOrder(ref.read(sitesProvider).ids))
        if (!AudiencePlatformCapability.of(id).supportsConcurrentOnline) id,
    ];
    final theme = Theme.of(context);
    final small = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 12,
      height: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      key: entry.rowKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            i18n('settings_audience_heat_only_count', args: {'count': '${ids.length}'}),
            style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(ids.map((id) => audiencePlatformName(ref, id)).join('、'), style: small),
          Text(i18n('settings_audience_heat_only_desc'), style: small),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final id in ids) PlatformLogo(id, size: 20)]),
          ),
        ],
      ),
    );
  }
}

/// What each platform reports (3.x's per-platform text, word for word;
/// platforms 3.x did not list show where the count comes from).
class AudienceInfoPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = audiencePlatformOrder(ref.read(sitesProvider).ids);
    final start = SettingsPane.of(context);
    return Scaffold(
      key: const ValueKey('settings-audience-info'),
      appBar: settingsAppBar(context, title: i18n('settings_audience_info'), embedded: start),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(start ? 24 : 16, 0, start ? 24 : 16, 32),
        itemCount: ids.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return SettingsNote(i18n('settings_audience_info_intro'), padding: const EdgeInsets.fromLTRB(8, 8, 8, 12));
          }
          final id = ids[index - 1];
          final detail = i18nOr('audience_${id}_detail', '');
          return Align(
            alignment: start ? Alignment.topLeft : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _InfoRow(
                key: ValueKey('settings-audience-info-$id'),
                logo: PlatformLogo(id),
                name: audiencePlatformName(ref, id),
                lines: [audienceSourceText(id), if (detail.isNotEmpty) detail],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A platform's name and every line of its explanation (no two-line limit).
class _InfoRow extends StatelessWidget {
  const new({required this.logo, required this.name, required this.lines, super.key});

  final Widget logo;
  final String name;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          logo,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  name,
                  style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: colors.onSurface),
                ),
                for (final line in lines)
                  Text(line, style: base.copyWith(fontSize: 12, height: 1.45, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
