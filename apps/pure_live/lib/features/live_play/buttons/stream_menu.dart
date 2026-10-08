import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';

/// The quality and line buttons, "原画 ⌄" "线路1 ⌄" (3.x `ResolutionSelector`
/// and `LineSelector`), in the room strip and in the fullscreen bar alike
/// (U.2f: every client has the same two buttons and the same small menu).
/// [onVideo] draws them white on the picture; there the menus open above the
/// buttons when they fit ([preferAbove]).
class StreamPickers extends StatelessWidget {
  /// Creates the pickers.
  const new({
    required this.controller,
    this.onVideo = false,
    this.preferAbove = false,
    this.onReopen,
    this.onMenu,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// White on the picture.
  final bool onVideo;

  /// Open the menus above the buttons when there is room (the fullscreen
  /// bar along the bottom).
  final bool preferAbove;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  /// Told when a menu opens (true) and closes (false): the player keeps its
  /// controls up meanwhile.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context) => ListenableSelector<(RoomStage, int, int, bool, bool, String)>(
    listenable: controller,
    selector: () => (
      controller.stage,
      controller.qualities.length,
      controller.qualityIndex,
      controller.switching,
      controller.switchingLine,
      controller.qualities.map((quality) => '${quality.quality}${quality.isPlaybackUnconfirmed ? '?' : ''}').join('|'),
    ),
    builder: (context, value, _) {
      final (stage, count, _, switchingQuality, switchingLine, _) = value;
      if (stage != RoomStage.playing || count == 0) return const SizedBox.shrink();
      final qualities = controller.qualities;
      final index = controller.qualityIndex.clamp(0, qualities.length - 1);
      final current = qualities[index];
      final switching = switchingQuality || switchingLine;
      return StreamBuilder<PlaybackState>(
        stream: controller.session.states,
        initialData: controller.session.state,
        builder: (context, snapshot) {
          final playback = snapshot.data ?? controller.session.state;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamMenuButton(
                key: const ValueKey('live-play-quality'),
                entryKey: 'live-play-quality-item',
                tooltip: i18n('select_quality'),
                label: '${platformQualityName(current.quality)}${current.isPlaybackUnconfirmed ? '?' : ''}',
                entries: [for (final quality in qualities) platformQualityName(quality.quality)],
                current: index,
                busy: switchingQuality,
                enabled: !switching,
                onVideo: onVideo,
                preferAbove: preferAbove,
                onMenu: onMenu,
                onSelected: (selected) {
                  if (selected == index) return;
                  onReopen?.call();
                  unawaited(controller.selectQuality(selected));
                },
              ),
              // 3.x showed the line button whenever there was a source.
              if (playback.lineCount > 0)
                StreamMenuButton(
                  key: const ValueKey('live-play-line'),
                  entryKey: 'live-play-line-item',
                  tooltip: i18n('select_play_line'),
                  label: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                  entries: [
                    for (var line = 0; line < playback.lineCount; line++)
                      i18n('toolbox_line', args: {'index': '${line + 1}'}),
                  ],
                  current: playback.lineIndex,
                  busy: switchingLine,
                  enabled: !switching,
                  onVideo: onVideo,
                  preferAbove: preferAbove,
                  onMenu: onMenu,
                  onSelected: (selected) {
                    if (selected == playback.lineIndex) return;
                    onReopen?.call();
                    unawaited(controller.selectLine(selected));
                  },
                ),
            ],
          );
        },
      );
    },
  );
}
