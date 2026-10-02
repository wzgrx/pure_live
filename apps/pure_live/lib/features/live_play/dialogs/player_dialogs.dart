import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/i18n/i18n.dart';

// The small menus the video's buttons open (docs/ui/compare/U.2n c5, c6):
// "画面比例" from the room menu and the fullscreen bar, "本直播间画面方向" (U.2b
// change 10) from the orientation button; next to the button, the picture
// not dimmed.

/// 3.x's video fit list: the setting `videoFitIndex` is an index into it.
const List<BoxFit> videoFits = [
  BoxFit.contain,
  BoxFit.cover,
  BoxFit.fill,
  BoxFit.fitHeight,
  BoxFit.fitWidth,
  BoxFit.scaleDown,
];

/// The names of [videoFits] (3.x `AppConsts.videoFitType`).
const List<String> videoFitKeys = [
  'video_fit_default',
  'video_fit_crop_center',
  'video_fit_fill_screen',
  'video_fit_fit_height',
  'video_fit_fit_width',
  'video_fit_scale_down',
];

/// The fit stored in [settings], as an index of [videoFits].
int videoFitIndexOf(SettingsStore settings) => settings.get(Settings.videoFitIndex).clamp(0, videoFits.length - 1);

/// The name of fit [index].
String videoFitName(int index) => i18n(videoFitKeys[index.clamp(0, videoFitKeys.length - 1)]);

/// The next fit (3.x `advanceVideoFitIndex`: the fullscreen text button).
Future<void> advanceVideoFit(SettingsStore settings) =>
    settings.set(Settings.videoFitIndex, (videoFitIndexOf(settings) + 1) % videoFits.length);

/// Picks the picture's fit in the small menu next to [anchor] (docs/ui/
/// compare/U.2n c5): the room menu's "画面比例" and the fullscreen bar's
/// button open this same menu; the current fit in the primary colour with
/// a tick; a choice applies at once. [preferAbove] on a bar along the
/// bottom.
Future<void> showVideoFitMenu(BuildContext anchor, SettingsStore settings, {bool preferAbove = false}) async {
  final current = videoFitIndexOf(settings);
  final chosen = await showSmallMenu(
    anchor,
    entries: [for (var index = 0; index < videoFits.length; index++) videoFitName(index)],
    current: current,
    entryKey: 'video-fit',
    preferAbove: preferAbove,
  );
  if (chosen != null && chosen != current) await settings.set(Settings.videoFitIndex, chosen);
}

/// The name of [orientation] (3.x's keys).
String roomOrientationName(RoomOrientation orientation) => i18n(switch (orientation) {
  RoomOrientation.automatic => 'portrait_override_auto',
  RoomOrientation.portrait => 'portrait_override_portrait',
  RoomOrientation.landscape => 'portrait_override_landscape',
});

/// The line under each orientation (U.2b change 10: what each one does to
/// the room, so "强制竖屏" does not read as turning the phone).
String roomOrientationDescription(RoomOrientation orientation) => i18n(switch (orientation) {
  RoomOrientation.automatic => 'live_play_orientation_auto_desc',
  RoomOrientation.portrait => 'live_play_orientation_portrait_desc',
  RoomOrientation.landscape => 'live_play_orientation_landscape_desc',
});

/// "本直播间画面方向" (3.x `PortraitOrientationPickerDialog`, U.2b change 10;
/// docs/ui/compare/U.2n c6): a small menu next to [anchor] (the
/// orientation button, on a bar along the bottom: above it), titled, each
/// option with its line, the current one in the primary colour with a
/// tick; a tap applies it and closes the menu. "记住单个直播间方向" under a
/// line applies the moment it is switched and leaves the menu open (3.x
/// kept it as a draft until an option was tapped).
Future<void> showRoomOrientationMenu(
  BuildContext anchor,
  RoomOrientationChoice choice, {
  bool preferAbove = true,
}) async {
  const options = RoomOrientation.values;
  final chosen = await showSmallMenu(
    anchor,
    title: i18n('portrait_room_override'),
    entries: [for (final orientation in options) roomOrientationName(orientation)],
    descriptions: [for (final orientation in options) roomOrientationDescription(orientation)],
    current: options.indexOf(choice.value),
    entryKey: 'room-orientation',
    preferAbove: preferAbove,
    width: 320,
    footer: _RememberOrientation(choice: choice),
  );
  if (chosen == null) return;
  final orientation = options[chosen];
  if (orientation != choice.value) await choice.choose(orientation, remember: choice.remember);
}

/// "记住单个直播间方向" in the orientation menu: switches at once.
class _RememberOrientation extends StatelessWidget {
  const new({required this.choice});

  final RoomOrientationChoice choice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: choice,
      builder: (context, _) => MergeSemantics(
        child: InkWell(
          key: const ValueKey('room-orientation-remember'),
          onTap: () => unawaited(choice.setRemember(remember: !choice.remember)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n('portrait_remember_room_override'),
                        style: theme.textTheme.bodyMedium?.regular.copyWith(fontSize: 14, color: scheme.onSurface),
                      ),
                      Text(
                        i18n('portrait_remember_room_override_desc'),
                        style: theme.textTheme.bodySmall?.regular.copyWith(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  key: const ValueKey('room-orientation-remember-switch'),
                  value: choice.remember,
                  onChanged: (value) => unawaited(choice.setRemember(remember: value)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
