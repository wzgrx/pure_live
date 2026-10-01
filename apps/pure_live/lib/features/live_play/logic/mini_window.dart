import 'dart:math' as math;
import 'dart:ui';

import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/routes/route_path.dart';

// The rules of the room's mini windows (docs/ui/compare/U.2j): the in-app
// floating window, Android's picture-in-picture and the desktop mini window
// show the same picture with the same buttons; what they show and where they
// sit is decided here, without widgets.

/// Which mini window shows the room.
enum MiniKind {
  /// Android's system picture-in-picture: only the picture, the danmaku and
  /// the recording mark; the system draws the buttons.
  systemPip,

  /// The in-app floating window over the other pages ("退出小窗播放").
  inApp,

  /// The main window shrunk to a mini window (Windows; Linux and macOS with
  /// their desktop shell): the pin and the volume as well.
  desktop,
}

/// What a mini window shows over the picture (U.2j c8).
enum MiniStatus {
  /// Playing: nothing over the picture.
  playing,

  /// Paused: the play button stays on.
  paused,

  /// Opening: a spinner on black.
  loading,

  /// Buffering: a spinner over the last frame.
  buffering,

  /// The stream dropped and is coming back: dimmed, a spinner, "正在重连".
  reconnecting,

  /// Playback failed (or the broadcast ended): dimmed, the reason, refresh.
  failed,
}

/// The status of a room in a mini window.
MiniStatus miniStatusOf({required RoomStage stage, required PlaybackStatus playback, required bool reconnecting}) {
  switch (stage) {
    case RoomStage.loading:
      return MiniStatus.loading;
    case RoomStage.failed || RoomStage.unplayable || RoomStage.offline:
      return MiniStatus.failed;
    case RoomStage.playing:
      break;
  }
  if (reconnecting && playback != PlaybackStatus.error) return MiniStatus.reconnecting;
  return switch (playback) {
    PlaybackStatus.idle || PlaybackStatus.opening => MiniStatus.loading,
    PlaybackStatus.buffering => MiniStatus.buffering,
    PlaybackStatus.error => MiniStatus.failed,
    PlaybackStatus.paused || PlaybackStatus.stopped || PlaybackStatus.completed => MiniStatus.paused,
    PlaybackStatus.playing => MiniStatus.playing,
  };
}

/// The picture's width over height, 16:9 when unknown (3.x
/// `currentVideoRatio`).
double pictureRatio({int? width, int? height, bool portrait = false}) {
  if (width != null && height != null && width > 0 && height > 0) return width / height;
  return portrait ? 9 / 16 : 16 / 9;
}

/// The in-app floating window's base: the shortest side of the [screen] ×
/// 0.56, within 220–360 (c6: phones 220 as 3.x, tablets and computers
/// 360).
double inAppMiniBase(Size screen) => (math.min(screen.width, screen.height) * 0.56).clamp(220.0, 360.0);

/// The in-app floating window's size for a picture of [aspectRatio] (3.x
/// `resolveAppFloatingSize`): landscape pictures are [inAppMiniBase] wide; a
/// portrait picture is 1.2 × the base high, its width by the ratio and at
/// least 120.
Size inAppMiniSize({required Size screen, required double aspectRatio}) {
  final base = inAppMiniBase(screen);
  final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio.clamp(1 / 2.39, 4.0) : 16 / 9;
  if (ratio >= 1) return Size(base, base / ratio);
  var height = base * 1.2;
  var width = height * ratio;
  if (width < 120) {
    width = 120;
    height = width / ratio;
  }
  return Size(width, height);
}

/// The gap between the in-app floating window and the edges (c6).
const double inAppMiniMargin = 16;

/// The height of the home page's bottom navigation bar (Material 3).
const double bottomNavigationHeight = 80;

/// The home page puts its destinations in a bottom bar below this width and
/// in a side rail from it on (the home's `homeTabletBreakpoint`, U.3b c6;
/// copied, as features do not import each other).
const double homeRailMinWidth = 600;

/// What the bottom-right corner of the floating window keeps clear below it:
/// the bottom navigation bar on the home page of a narrow window (above it
/// by [inAppMiniMargin]), else only the margin (c6; 3.x always lifted it by
/// the bar's height).
double inAppMiniBottomClearance({required String route, required double width, required double safeBottom}) {
  final bar = route == RoutePath.kInitial && width < homeRailMinWidth;
  return safeBottom + (bar ? bottomNavigationHeight : 0) + inAppMiniMargin;
}

/// The top-left of the floating window of [window] size in [area]: where the
/// user dragged it ([dragged]), else the bottom-right corner; always inside
/// [area], [inAppMiniMargin] from the sides, [topClearance] from the top and
/// [bottomClearance] from the bottom (a rotation or a smaller window brings
/// it back).
Offset inAppMiniOffset({
  required Size area,
  required Size window,
  required double bottomClearance,
  required double topClearance,
  Offset? dragged,
}) {
  final maxLeft = math.max<double>(0, area.width - window.width - inAppMiniMargin);
  final maxTop = math.max(topClearance, area.height - window.height - bottomClearance);
  final wanted = dragged ?? Offset(maxLeft, maxTop);
  return Offset(
    wanted.dx.clamp(math.min(inAppMiniMargin, maxLeft), maxLeft),
    wanted.dy.clamp(math.min(topClearance, maxTop), maxTop),
  );
}

/// Whether the room's page hands its player to the in-app floating window
/// when it closes (3.x `shouldFloatAfterLivePlayExit` and
/// `navigation_observer.dart`): the setting is on, the room plays (a stream
/// is open, no loading error), the page did not close it on purpose, and the
/// page below is not another room or multi-view (they play themselves).
bool shouldFloatOnLeave({
  required bool enabled,
  required RoomStage stage,
  required bool suppressed,
  required String topRoute,
}) =>
    enabled &&
    !suppressed &&
    stage == RoomStage.playing &&
    topRoute != RoutePath.kLivePlay &&
    topRoute != RoutePath.kMultiview;

/// Whether leaving the app now enters picture-in-picture by itself (J1):
/// the setting is on, the room page is on top, and the picture plays (not
/// audio only, paused or off the air).
bool shouldAutoEnterPip({
  required bool enabled,
  required bool onTop,
  required RoomStage stage,
  required PlaybackStatus status,
  required bool audioOnly,
}) =>
    enabled &&
    onTop &&
    stage == RoomStage.playing &&
    !audioOnly &&
    (status == PlaybackStatus.playing || status == PlaybackStatus.buffering);

/// The mini windows' danmaku size and speed (3.x `CompactDanmakuMetrics`):
/// with automatic scaling the text and speed follow the window's width over
/// 350 (0.65–1), but the text stays at least 10 (c7: 3.x's 220 wide window
/// had 7.8) unless the user chose smaller.
final class CompactDanmakuMetrics {
  const new _({required this.fontSize, required this.speed, required this.laneHeight});

  /// Resolves the metrics for a window [width] wide.
  factory resolve({required double width, required bool autoScale, required double fontSize, required double speed}) {
    final safeWidth = width.isFinite && width > 0 ? width : referenceWidth;
    final scale = autoScale ? (safeWidth / referenceWidth).clamp(0.65, 1.0) : 1.0;
    final scaled = fontSize * scale;
    final size = autoScale ? math.max(scaled, math.min(fontSize, minimumFontSize)) : fontSize;
    return CompactDanmakuMetrics._(
      fontSize: size,
      speed: speed * scale,
      // 3.x's track: 1.8 × the text or the text + 10, within 18–44.
      laneHeight: math.max(size * 1.8, size + 10).clamp(18.0, 44.0),
    );
  }

  /// The width the configured size is for.
  static const double referenceWidth = 350;

  /// The smallest automatic size (c7).
  static const double minimumFontSize = 10;

  /// The text size.
  final double fontSize;

  /// Logical pixels a second.
  final double speed;

  /// The height of a lane.
  final double laneHeight;
}

/// The mini windows' danmaku frame rate (3.x `resolvedDanmakuFps(pip:
/// true)`): the manual [configured] rate (15–240), or with [automatic] the
/// display's highest rate capped by the refresh-rate [mode]: `powerSaving`
/// 30, `balanced` 60, `performance` the display's.
int compactDanmakuFps({
  required bool automatic,
  required int configured,
  required String mode,
  double? maxRefreshRate,
  double? currentRefreshRate,
}) {
  if (!automatic) return configured.clamp(15, 240);
  final maximum = maxRefreshRate ?? 0;
  final current = currentRefreshRate ?? 0;
  final detected = maximum > 0 ? maximum : (current > 0 ? current : 60.0);
  final device = detected.round().clamp(15, 240);
  return switch (mode) {
    'performance' => device,
    'balanced' => device.clamp(15, 60),
    _ => device.clamp(15, 30),
  };
}

/// [text] without the codes the platform names as pictures ([codes]): the
/// mini windows' "纯文字" (3.x `pipDanmakuNoEmojiMode` left the pictures out).
String withoutEmoteCodes(String text, Iterable<String> codes) {
  var result = text;
  for (final code in codes) {
    if (code.isNotEmpty) result = result.replaceAll(code, '');
  }
  return result.trim();
}
