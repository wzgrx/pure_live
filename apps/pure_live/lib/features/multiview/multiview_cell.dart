import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_settings.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/multiview/multiview_sheets.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// One cell (CEL-1): the video, the chat layer when the cell is the danmaku
/// target (DM-3), the state overlay, the sound-focus and pick-target marks
/// (AUD-4), and in 1+N's big cell the control bar (OPS-3).
///
/// Cells have no lines of their own: the grid's 2 dp black gaps part them
/// (principles §7 rule 4); a cell without a picture is a shade lighter so
/// the slot still shows. The sound focus is a 2 dp primary border and the
/// speaker in the label; the pick target a 2 dp tertiary border and a
/// "放到这里" badge, so neither relies on colour, and a cell that is both
/// shows both.
class MultiviewCellView extends ConsumerWidget {
  const new({
    required this.index,
    required this.focusNode,
    required this.onTap,
    required this.onPick,
    this.autofocus = false,
    this.onKeyEvent,
    this.covered = false,
    this.danmaku,
    this.controls,
    this.big = false,
    this.picksReplace = false,
    super.key,
  });

  /// The empty slot's shade (the pure black theme's container colour).
  static const Color slotColor = Color(0xFF161618);

  final int index;

  /// The cell's focus: the D-pad moves between cells, OK acts like a tap
  /// (OPS-1: sound focus on a playing cell, the picker on a free one) and a
  /// long OK opens the cell menu (OPS-2). Up and down never switch rooms.
  final FocusNode focusNode;

  /// OPS-1, decided by the page.
  final VoidCallback onTap;

  /// Opens the picker for this cell (retry without a room, CEL-5).
  final VoidCallback onPick;

  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  /// An opaque page covers the multiview page (RS-3; SURF-1, SURF-4).
  final bool covered;

  /// The on-video chat layer, on the danmaku target only (DM-3).
  final Widget? danmaku;

  /// The big cell's control bar while shown (OPS-3).
  final Widget? controls;

  /// 1+N's big cell: its label also shows the quality.
  final bool big;

  /// The picker panel is on screen (LYT-7): its picks go to the target cell
  /// even when that cell plays, so the target is marked on a playing cell
  /// too.
  final bool picksReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiviewProvider);
    if (index >= state.cells.length) return const SizedBox();
    final cell = state.cells[index];
    final controller = ref.read(multiviewProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final focused = index == state.audioFocus && cell.status == CellStatus.playing;
    final targeted = index == state.target && (cell.assignable || picksReplace);
    final session = cell.session;
    final menu = cell.status == CellStatus.playing ? () => unawaited(showMultiviewCellMenu(context, ref, index)) : null;
    final controls = this.controls;
    // The remote's ring (3 dp, near-white, inside the cell) differs from the
    // sound focus (2 dp primary with the speaker badge; AUD-4).
    return FocusFrame(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onTap,
      onMenu: menu,
      onKeyEvent: onKeyEvent,
      grow: false,
      ringInside: true,
      radius: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: menu,
        onSecondaryTap: menu,
        child: DecoratedBox(
          // Sound focus and pick target are both visible (AUD-4): the focus
          // outside, the target inside it.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: focused ? Border.all(color: scheme.primary, width: 2) : null),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: targeted ? Border.all(color: scheme.tertiary, width: 2) : null),
            child: ColoredBox(
              color: cell.status == CellStatus.playing ? Colors.black : slotColor,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (session != null && cell.status == CellStatus.playing)
                    LiveVideoView(key: GlobalObjectKey(session), session: session, occluded: covered),
                  ?danmaku,
                  // Labels and the bar over the picture grow at most 1.3×
                  // (principles §2.3).
                  OnVideoTextScale(
                    child: _CellOverlay(
                      cell: cell,
                      focused: focused,
                      targeted: targeted,
                      muteAll: state.muteAll,
                      big: big,
                      label: controls == null,
                      onRetry: () {
                        if (cell.room != null) {
                          unawaited(controller.refresh(index));
                        } else {
                          onPick();
                        }
                      },
                    ),
                  ),
                  if (controls != null)
                    Positioned(
                      left: Space.s2,
                      right: Space.s2,
                      bottom: Space.s2,
                      child: OnVideoTextScale(child: controls),
                    ),
                  if (targeted)
                    Positioned(
                      left: Space.s1,
                      top: Space.s1,
                      child: OnVideoTextScale(
                        child: DecoratedBox(
                          key: const ValueKey('multiview-target'),
                          decoration: BoxDecoration(
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(Radii.r1),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.s1, vertical: 1),
                            child: Text(
                              t.multiview.pickTarget,
                              style: TextStyle(color: scheme.onTertiary, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CellOverlay extends StatelessWidget {
  const new({
    required this.cell,
    required this.focused,
    required this.targeted,
    required this.muteAll,
    required this.big,
    required this.label,
    required this.onRetry,
  });

  final MultiviewCell cell;
  final bool focused;
  final bool targeted;
  final bool muteAll;
  final bool big;

  /// The name label shows (hidden under the control bar, OPS-3).
  final bool label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final name = cell.detail?.card.anchorName;
    switch (cell.status) {
      case CellStatus.empty:
        // The pick target is brighter; its border marks it too (AUD-4).
        final tone = targeted ? ink : Colors.white54;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, color: tone, size: 36),
              const SizedBox(height: Space.s1),
              Text(t.multiview.addRoom, style: TextStyle(color: tone)),
            ],
          ),
        );
      case CellStatus.resolving:
        return const Center(child: CircularProgressIndicator(color: ink));
      case CellStatus.offline:
        return Center(
          child: Text(
            t.multiview.offlineCell(name: name ?? ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        );
      case CellStatus.error:
        return _Failure(title: describeError(cell.error ?? 'error').title, onRetry: onRetry);
      case CellStatus.playing:
        final session = cell.session;
        return StreamBuilder<PlaybackState>(
          stream: session?.states,
          initialData: session?.state,
          builder: (context, snapshot) {
            final playback = snapshot.data;
            final quality = big ? playback?.quality?.label : null;
            return Stack(
              children: [
                // REC-MV-6: recovery gave up; the cell says so and offers a retry.
                if (playback?.phase == PlaybackPhase.error)
                  _Failure(title: t.multiview.interrupted, onRetry: onRetry)
                else if (cell.paused || (playback?.showsPaused ?? false))
                  const Center(child: Icon(Icons.pause_circle_outline, color: Colors.white70, size: 40))
                else if (playback?.showsBuffering ?? false)
                  const Center(
                    child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(color: ink, strokeWidth: 2)),
                  ),
                if (label)
                  Positioned(
                    left: Space.s1,
                    bottom: Space.s1,
                    right: Space.s1,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(Radii.r1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.s1, vertical: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (focused) Icon(muteAll ? Icons.volume_off : Icons.volume_up, size: 14, color: ink),
                              if (focused) const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  [?name, ?quality].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: ink, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
    }
  }
}

class _Failure extends StatelessWidget {
  const new({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: Space.s2),
        FilledButton.tonal(onPressed: onRetry, child: Text(t.common.retry)),
      ],
    ),
  );
}

/// The big cell's control bar in 1+N (OPS-3): play or pause, refresh,
/// danmaku on or off and its settings, quality, line (more than one),
/// volume, fullscreen.
class MultiviewControlBar extends ConsumerWidget {
  const new({required this.index, required this.fullscreen, this.onFullscreen, super.key});

  final int index;

  /// The page is in fullscreen.
  final bool fullscreen;

  /// Toggles fullscreen; null hides the button (TV).
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiviewProvider);
    final cell = state.cells.elementAtOrNull(index);
    final session = cell?.session;
    if (cell == null || session == null || cell.status != CellStatus.playing) return const SizedBox.shrink();
    final controller = ref.read(multiviewProvider.notifier);
    final danmakuOn = ref.watch(danmakuPrefsProvider.select((prefs) => prefs.enabled));
    const ink = Color(0xEBFFFFFF);
    Widget button(IconData icon, String tooltip, VoidCallback onPressed, {Color? color}) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: Sizes.iconDense, color: color ?? ink),
      onPressed: onPressed,
    );
    return StreamBuilder<PlaybackState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snapshot) {
        final playback = snapshot.data ?? session.state;
        return DecoratedBox(
          decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(Radii.r2)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cell.paused)
                  button(Icons.play_arrow, t.common.resume, () => controller.setPaused(index, paused: false))
                else
                  button(Icons.pause, t.common.pause, () => controller.setPaused(index, paused: true)),
                button(Icons.refresh, t.common.refresh, () => unawaited(controller.refresh(index))),
                if (danmakuOn) ...[
                  button(
                    state.danmaku ? Icons.subtitles : Icons.subtitles_off_outlined,
                    state.danmaku ? t.multiview.danmakuOff : t.multiview.danmakuOn,
                    controller.toggleDanmaku,
                    color: state.danmaku ? Theme.of(context).colorScheme.primary : null,
                  ),
                  button(Icons.tune, t.danmaku.settings, () => unawaited(showDanmakuSettingsSheet(context))),
                ],
                if (playback.qualities.length > 1)
                  button(
                    Icons.hd_outlined,
                    t.multiview.quality,
                    () => unawaited(showMultiviewQualitySheet(context, ref, index)),
                  ),
                if (playback.lines.length > 1)
                  button(
                    Icons.alt_route,
                    t.multiview.line,
                    () => unawaited(showMultiviewLineSheet(context, ref, index)),
                  ),
                button(
                  Icons.volume_up_outlined,
                  t.multiview.volume,
                  () => unawaited(showMultiviewVolumeSheet(context, index)),
                ),
                if (onFullscreen case final toggle?)
                  button(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    fullscreen ? t.multiview.exitFullscreen : t.multiview.fullscreen,
                    toggle,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
