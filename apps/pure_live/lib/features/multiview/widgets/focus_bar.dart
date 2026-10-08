import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/widgets/cell_controls.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';

/// The large cell's controls in the immersive and fullscreen modes (3.x
/// `_buildLargeControlBar`, docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c14): pause, refresh, the
/// danmaku and its settings, the quality and line buttons with their small
/// menus (U.2f), the volume (the cell's panel) and fullscreen. Scrolls
/// sideways when the cell is narrower than the bar.
class FocusControlBar extends StatelessWidget {
  /// Creates the bar of cell [index].
  const new({
    required this.controller,
    required this.index,
    required this.fullscreen,
    required this.onDanmakuSettings,
    required this.onVolume,
    required this.onFullscreen,
    this.onMenu,
    super.key,
  });

  /// The page's controller.
  final MultiviewController controller;

  /// The large cell.
  final int index;

  /// The page is in fullscreen (the last button leaves it).
  final bool fullscreen;

  /// Opens the danmaku settings panel.
  final VoidCallback onDanmakuSettings;

  /// Opens the cell's panel (its volume).
  final VoidCallback onVolume;

  /// Enters or leaves fullscreen.
  final VoidCallback onFullscreen;

  /// Told when a quality or line menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context) {
    final cell = controller.cells[index];
    final session = cell.session;
    final accent = OnVideoColors.accent(Theme.of(context).colorScheme);
    Widget button(String key, String tooltip, Widget icon, VoidCallback onPressed) => IconButton(
      key: ValueKey('multiview-bar-$key'),
      tooltip: tooltip,
      color: OnVideoColors.foreground,
      iconSize: 20,
      onPressed: onPressed,
      icon: icon,
    );
    final qualities = cell.qualities;
    return Container(
      key: const ValueKey('multiview-control-bar'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: OnVideoColors.scrim, borderRadius: BorderRadius.circular(10)),
      child: IconTheme(
        data: OnVideoColors.icons.copyWith(size: 20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: session == null
              ? const SizedBox.shrink()
              : StreamBuilder<PlaybackState>(
                  stream: session.states,
                  initialData: session.state,
                  builder: (context, snapshot) {
                    final playback = snapshot.data ?? session.state;
                    final paused = playback.status == PlaybackStatus.paused;
                    final danmaku = controller.danmakuEnabled;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        button(
                          'play',
                          i18n(paused ? 'multiview_play' : 'multiview_pause'),
                          Icon(paused ? AppIcons.cellPlay : AppIcons.cellPause),
                          () => unawaited(controller.togglePlay(index)),
                        ),
                        button(
                          'refresh',
                          i18n('multiview_refresh'),
                          const Icon(AppIcons.cellRefresh),
                          () => unawaited(controller.retry(index, reload: true)),
                        ),
                        button(
                          'danmaku',
                          i18n('danmaku'),
                          DanmakuIcon(
                            danmaku ? DanmakuIconKind.on : DanmakuIconKind.off,
                            color: danmaku ? accent : null,
                          ),
                          () => controller.setDanmakuEnabled(enabled: !danmaku),
                        ),
                        button(
                          'danmaku-settings',
                          i18n('danmaku_settings'),
                          const DanmakuIcon(DanmakuIconKind.settings),
                          onDanmakuSettings,
                        ),
                        if (qualities.isNotEmpty)
                          StreamMenuButton(
                            key: const ValueKey('multiview-bar-quality'),
                            entryKey: 'multiview-bar-quality-item',
                            tooltip: i18n('select_quality'),
                            label: qualityLabel(qualities[cell.qualityIndex.clamp(0, qualities.length - 1)]),
                            entries: [for (final quality in qualities) platformQualityName(quality.quality)],
                            current: cell.qualityIndex,
                            busy: cell.switching,
                            enabled: !cell.switching,
                            onVideo: true,
                            preferAbove: true,
                            onMenu: onMenu,
                            onSelected: (selected) => unawaited(controller.selectQuality(index, selected)),
                          ),
                        if (playback.lineCount > 0)
                          StreamMenuButton(
                            key: const ValueKey('multiview-bar-line'),
                            entryKey: 'multiview-bar-line-item',
                            tooltip: i18n('select_play_line'),
                            label: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                            entries: [
                              for (var line = 0; line < playback.lineCount; line++)
                                i18n('toolbox_line', args: {'index': '${line + 1}'}),
                            ],
                            current: playback.lineIndex,
                            enabled: !cell.switching,
                            onVideo: true,
                            preferAbove: true,
                            onMenu: onMenu,
                            onSelected: (selected) {
                              if (selected != playback.lineIndex) unawaited(controller.selectLine(index, selected));
                            },
                          ),
                        button('volume', i18n('multiview_volume'), const Icon(AppIcons.cellVolume), onVolume),
                        button(
                          'fullscreen',
                          i18n(fullscreen ? 'multiview_fullscreen_exit' : 'multiview_fullscreen'),
                          Icon(fullscreen ? AppIcons.gridExitFullscreen : AppIcons.gridFullscreen),
                          onFullscreen,
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}
