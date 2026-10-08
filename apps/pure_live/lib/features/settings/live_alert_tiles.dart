import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';

// "开播提醒" in settings → 刷新 (docs/O-Android系统集成/O01-通知和前台服务/O01.1-开播提醒;
// V01.1 L3): which follows it covers.

final StreamProvider<List<StoreTag>> _tagsProvider = StreamProvider.autoDispose<List<StoreTag>>(
  (ref) => ref.watch(storeProvider).tags.watchAll(),
);

/// The tags whose follows "开播提醒" covers (V01.1 L3): a heading row, then
/// a switch per tag in the tags' order. No tag on covers every follow (a
/// streamer or a few: give them one tag). Without tags the heading says
/// every follow is covered and where tags are made. Greyed out while
/// "开播提醒" is off.
class LiveAlertTagsTile extends ConsumerWidget {
  /// Creates the rows.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = watchSetting(ref, Settings.liveAlertEnabled);
    final chosen = watchSetting(ref, Settings.liveAlertTagIds);
    final tags = ref.watch(_tagsProvider).value ?? const <StoreTag>[];
    final ticked = {
      for (final tag in tags)
        if (chosen.contains(tag.id)) tag.id,
    };
    final reason = i18n('settings_needs_on', args: {'name': i18n('live_alert')});
    return Column(
      key: entry.rowKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          icon: AppIcons.tag,
          title: entry.titleText,
          subtitle: tags.isEmpty ? i18n('live_alert_tags_none') : entry.descriptionText,
          enabled: on,
          disabledReason: reason,
        ),
        for (final tag in tags)
          SettingsSwitchRow(
            key: ValueKey('settings-live-alert-tag-${tag.id}'),
            leading: const SizedBox(width: 22),
            title: tag.name,
            value: ticked.contains(tag.id),
            enabled: on,
            onChanged: (value) => writeSetting(ref, Settings.liveAlertTagIds, [
              // Ids of deleted tags go; the order is the tags' order.
              for (final other in tags)
                if (other.id == tag.id ? value : ticked.contains(other.id)) other.id,
            ]),
          ),
      ],
    );
  }
}
