import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/areas/areas_common.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// [count] shortened as 3.x showed it (`readableCount`): 万 from 10000 in
/// Chinese, K from 1000 in English; anything else unchanged.
String readableCount(String count) {
  final value = int.tryParse(count.trim());
  if (value == null) return count;
  if (currentStrings?.language == AppLanguage.en) {
    return value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}${i18n('count_k')}' : count;
  }
  return value >= 10000 ? '${(value / 10000).toStringAsFixed(1)}${i18n('count_wan')}' : count;
}

/// What a room card shows for [room] (3.x `RoomCard`'s fields): the
/// audience as the user's setting prefers it, addresses normalised, the
/// restriction named.
RoomCardData roomCardData(LiveRoom room, {required bool preferRealOnline, required List<String> realOnlinePlatforms}) {
  final platformEnabled = realOnlinePlatforms.contains(room.platform);
  final type = room.audienceType(preferRealOnline: preferRealOnline, platformEnabled: platformEnabled);
  final value = room.audienceValue(preferRealOnline: preferRealOnline, platformEnabled: platformEnabled);
  return RoomCardData(
    platformId: room.platform,
    title: room.title,
    anchorName: room.displayNick(platformLabel(room.platform)),
    avatarUrl: normalizeImageUrl(room.avatar),
    coverUrl: normalizeImageUrl(room.cover),
    isLive: room.isLiveNow,
    isReplay: room.isRecord,
    audience: RoomAudience(
      kind: RoomAudienceKind.values.byName(type.name),
      value: value.isEmpty ? '' : readableCount(value),
    ),
    restrictionLabel: room.isRestricted ? restrictionLabel(room.effectiveRestriction) : null,
  );
}

/// The words for [restriction] on a card.
String restrictionLabel(LiveRestriction restriction) => i18n('area_rooms_restriction_${restriction.name}');

/// The card settings for this device (3.x `RoomCardSettingsController.resolve`:
/// phones use the mobile settings, desktops the desktop ones): the saved
/// appearance, else the preset's.
RoomCardAppearance watchCardAppearance(WidgetRef ref) {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final preset = watchSetting(ref, mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset);
  final config = watchSetting(ref, mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig);
  final base = RoomCardAppearance.fromPreset(
    RoomCardPreset.values.where((value) => value.storageKey == preset).firstOrNull ?? RoomCardPreset.standard,
  );
  if (config.isEmpty) return base;
  try {
    return RoomCardAppearance.fromJson(Map<String, dynamic>.of(config), fallback: base);
  } on Object {
    return base;
  }
}

/// The font sizes of the settings (the card heights follow them).
LiveFontSizes watchFontSizes(WidgetRef ref) => LiveFontSizes(
  bodySmall: watchSetting(ref, Settings.fontSizeBodySmall),
  bodyMedium: watchSetting(ref, Settings.fontSizeBodyMedium),
  bodyLarge: watchSetting(ref, Settings.fontSizeBodyLarge),
  titleMedium: watchSetting(ref, Settings.fontSizeTitleMedium),
  titleLarge: watchSetting(ref, Settings.fontSizeTitleLarge),
);

/// The card menu of [room] (3.x `RoomCard.onLongPress`): the streamer, the
/// title and room number, follow or unfollow, copy the room's link.
Future<void> showRoomMenu(BuildContext context, WidgetRef ref, LiveRoom room) => showDialog<void>(
  context: context,
  builder: (dialogContext) => _RoomMenu(room: room),
);

class _RoomMenu extends ConsumerStatefulWidget {
  const new({required this.room});

  final LiveRoom room;

  @override
  ConsumerState<_RoomMenu> createState() => _RoomMenuState();
}

class _RoomMenuState extends ConsumerState<_RoomMenu> {
  bool? _followed;
  bool _busy = false;

  LiveRoom get _room => widget.room;

  @override
  void initState() {
    super.initState();
    ref.read(storeProvider).follows.contains(_room).then((value) {
      if (mounted) setState(() => _followed = value);
    }).ignore();
  }

  Future<void> _toggle() async {
    final follows = ref.read(storeProvider).follows;
    final name = _room.displayNick(platformLabel(_room.platform));
    setState(() => _busy = true);
    try {
      if (_followed ?? false) {
        if (!await confirmUnfollow(context, name)) return;
        await follows.remove(_room);
        AppNavigator.toast(i18n('area_rooms_unfollow_done', args: {'name': name}));
      } else {
        await follows.add(_room);
        AppNavigator.toast(i18n('area_rooms_follow_done', args: {'name': name}));
      }
      final now = await follows.contains(_room);
      if (mounted) setState(() => _followed = now);
    } on Object {
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _room.link?.trim() ?? '';
    final followed = _followed;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: Row(
        children: [
          PlatformLogo(_room.platform),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _room.displayNick(platformLabel(_room.platform)),
              style: context.textStyles.t16Bold,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (link.isNotEmpty)
            IconButton(
              tooltip: i18n('copy_link'),
              icon: Icon(Icons.link_rounded, color: theme.colorScheme.primary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                AppNavigator.toast(i18n('area_rooms_link_copied'));
              },
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_room.title.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_room.title, style: context.textStyles.t14Medium.copyWith(height: 1.45)),
              ),
            const SizedBox(height: 14),
            Text(
              i18n('room_id_label', args: {'id': _room.roomId}),
              style: context.textStyles.t11Bold.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_room.isRestricted) ...[
              const SizedBox(height: 6),
              Text(
                restrictionLabel(_room.effectiveRestriction),
                style: context.textStyles.t12.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (followed != null)
          FilledButton.tonal(
            key: const ValueKey('room-menu-follow'),
            onPressed: _busy ? null : _toggle,
            child: Text(i18n(followed ? 'unfollow' : 'follow')),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close'))),
      ],
    );
  }
}
