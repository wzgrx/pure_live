import 'dart:math' as math;

import 'package:live_store/live_store.dart' show VideoFit;
import 'package:pure_live_app/features/room/presentation.dart';

/// Pure decisions of the picture's gestures (spec/modules/live-room.md §3.2,
/// §3.3; principles §6.1). The widgets only measure and dispatch.

/// Height of the top and bottom control bands (ZN-1).
const double controlBand = 56;

/// Height of the portrait-fullscreen exit zone at the bottom (ZN-2).
const double portraitExitZone = 96;

/// What a tap on the picture does (T-01, D-01).
enum TapOutcome {
  /// Locked: only the lock button shows or hides (T-10).
  toggleLockButton,

  /// A tap in a visible control band: the controls stay and restart their
  /// timer; no danmaku hit test (INV-ROOM-01).
  keepControls,

  /// The tap hit an on-video danmaku: open its actions (REN-8).
  danmakuActions,

  /// Touch, controls visible and playing: hide them (REG-ROOM-003).
  hideControls,

  /// Show the controls, and resume if not playing.
  showControls,
}

/// T-01 / D-01, in order: lock, control band, danmaku, hide, show.
TapOutcome tapOutcome({
  required bool locked,
  required bool controlsVisible,
  required bool inControlBand,
  required bool hitDanmaku,
  required bool playing,
  required bool touch,
}) {
  if (locked) return TapOutcome.toggleLockButton;
  if (controlsVisible && inControlBand) return TapOutcome.keepControls;
  if (hitDanmaku) return TapOutcome.danmakuActions;
  if (touch && controlsVisible && playing) return TapOutcome.hideControls;
  return TapOutcome.showControls;
}

/// What a long press on the picture does (T-07).
enum LongPressOutcome {
  /// Locked: nothing (T-10).
  none,

  /// In a visible control band: only the controls show.
  keepControls,

  /// Hit a danmaku with long-press actions on: its actions.
  danmakuActions,

  /// Otherwise the quick panel (画质, 线路, 弹幕开关, 截图, 定时关闭, 画面比例).
  quickPanel,
}

/// T-07 in order: lock, control band, danmaku, quick panel.
LongPressOutcome longPressOutcome({
  required bool locked,
  required bool controlsVisible,
  required bool inControlBand,
  required bool hitDanmaku,
}) {
  if (locked) return LongPressOutcome.none;
  if (controlsVisible && inControlBand) return LongPressOutcome.keepControls;
  if (hitDanmaku) return LongPressOutcome.danmakuActions;
  return LongPressOutcome.quickPanel;
}

/// Where a double tap (or F, or the fullscreen button) goes (T-02, D-02):
/// null while locked; out of portrait fullscreen to inline; out of
/// fullscreen back to [returnTo]; into portrait fullscreen when the
/// condition holds (touch + portrait source); otherwise into fullscreen.
RoomPresentation? doubleTapTarget({
  required RoomPresentation current,
  required bool locked,
  required bool portraitCondition,
  RoomPresentation returnTo = RoomPresentation.inline,
}) {
  if (locked) return null;
  return switch (current) {
    RoomPresentation.portraitFullscreen => RoomPresentation.inline,
    RoomPresentation.fullscreen => returnTo,
    RoomPresentation.inline when portraitCondition => RoomPresentation.portraitFullscreen,
    _ => RoomPresentation.fullscreen,
  };
}

/// ZN-1: whether [y] in a picture of [height] is in a control band.
bool inControlBand(double y, double height, {double top = controlBand, double bottom = controlBand}) =>
    y < top || y > height - bottom;

/// What a vertical swipe adjusts (ZN-3, T-03).
enum SwipeTarget {
  /// Nothing (desktop left half).
  none,

  /// Screen brightness (phones only).
  brightness,

  /// Playback volume.
  volume,
}

/// ZN-3: left half brightness, right half volume; desktops have no
/// brightness.
SwipeTarget swipeTarget({required double x, required double width, required bool touch}) {
  final left = x < width / 2;
  if (!left) return SwipeTarget.volume;
  return touch ? SwipeTarget.brightness : SwipeTarget.none;
}

/// T-03: a swipe over half the picture height changes the value by 25%;
/// up raises it.
double swipeChange(double dy, double height) => height <= 0 ? 0 : -dy / (height / 2) * 0.25;

/// Scale factor that counts as a spread or a pinch.
const double pinchThreshold = 1.15;

/// T-06 and principles §6.1: spreading fills the screen (crop), pinching fits
/// it; one step per gesture; null when the gesture does not change the fit.
VideoFit? pinchFit(VideoFit current, double scale) {
  if (scale >= pinchThreshold) return current == VideoFit.cover ? null : VideoFit.cover;
  if (scale <= 1 / pinchThreshold) return current == VideoFit.contain ? null : VideoFit.contain;
  return null;
}

/// ZN-2: whether a gesture starting at [y] belongs to the portrait
/// fullscreen exit zone of a picture [height] tall.
bool startsInPortraitExitZone(double y, double height) => y >= height - portraitExitZone;

/// OLD-06 / T-04: an upward swipe of [upward] logical pixels at [velocity]
/// (negative is upward) leaves portrait fullscreen.
bool exitsPortraitFullscreen({required double upward, required double velocity}) =>
    upward >= 64 || (velocity <= -850 && upward >= 24);

/// PS-4: the three heights of the portrait panel in an area [available]
/// tall, and when a drag below the lowest enters portrait fullscreen.
final class PortraitPanelMetrics {
  new(this.available);

  /// Height of the area the video and panel share.
  final double available;

  /// The video keeps at least 120 dp.
  double get maxHeight => math.max(0, available - 120);

  /// 27% of the height, 190–250 dp.
  double get low => math.min((available * 0.27).clamp(190, 250), maxHeight);

  /// 68% of the height, the video keeping 120 dp.
  double get high => math.max(low, math.min(available * 0.68, maxHeight));

  /// 44% of the height.
  double get mid => (available * 0.44).clamp(low, high);

  /// Low, middle and high.
  List<double> get detents => [low, mid, high];

  /// The detent nearest to [height].
  double nearest(double height) {
    var best = low;
    for (final detent in detents) {
      if ((detent - height).abs() < (best - height).abs()) best = detent;
    }
    return best;
  }

  /// Pull below [low] that enters portrait fullscreen: 30% of the panel,
  /// 72–144 dp.
  double get fullscreenPull => (low * 0.3).clamp(72, 144).toDouble();

  /// Whether releasing at [height] with downward [velocity] (dp/s) enters
  /// portrait fullscreen.
  bool entersFullscreen(double height, double velocity) {
    final pulled = low - height;
    return pulled >= fullscreenPull || (velocity >= 900 && pulled >= 28);
  }
}
