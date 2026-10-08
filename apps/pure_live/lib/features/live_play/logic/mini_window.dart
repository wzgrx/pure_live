import 'dart:math' as math;
import 'dart:ui';

import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_status.dart';
import 'package:pure_live/routes/route_path.dart';

// The rules of the room's mini windows (docs/A-界面设计/A07-直播间界面/A07.8-小窗): the in-app
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

/// The picture's size to lay a window out by: the video's, and before its
/// first frame the size its line declares (F.1b); unknown otherwise. A
/// placeholder track's size (A07.20) is not a picture's.
({int? width, int? height}) expectedPictureSize(PlaybackState state) {
  final width = state.videoWidth;
  final height = state.videoHeight;
  if (width != null && height != null && width > 0 && height > 0 && !pictureIsPlaceholder(state)) {
    return (width: width, height: height);
  }
  if (state.declaredAspectRatio != null) return (width: state.line?.width, height: state.line?.height);
  return (width: null, height: null);
}

/// The picture's width × height for the mini windows (3.x
/// `resolveCompactWindowAspectRatio`): [width] × [height] when known, else
/// 9 × 16 for a [portrait] picture and 16 × 9 for the rest. A [portrait]
/// picture is 9 × 16 whatever its size when the windows do not
/// [followPortrait] its real ratio (`portraitPipFollowSource`, F.1d).
(int, int) miniPictureSize({int? width, int? height, bool portrait = false, bool followPortrait = true}) {
  if (portrait && !followPortrait) return (9, 16);
  if (width != null && height != null && width > 0 && height > 0) return (width, height);
  return portrait ? (9, 16) : (16, 9);
}

/// [miniPictureSize] as width over height (3.x `currentVideoRatio`).
double pictureRatio({int? width, int? height, bool portrait = false, bool followPortrait = true}) {
  final (w, h) = miniPictureSize(width: width, height: height, portrait: portrait, followPortrait: followPortrait);
  return w / h;
}

/// The in-app floating window's base: the shortest side of the [screen] ×
/// 0.56, within 220–360 (c6: phones 220 as 3.x, tablets and computers
/// 360).
double inAppMiniBase(Size screen) => (math.min(screen.width, screen.height) * 0.56).clamp(220.0, 360.0);

/// The in-app floating window's size for a picture of [aspectRatio] (3.x
/// `resolveAppFloatingSize`): landscape pictures are [inAppMiniBase] wide; a
/// portrait picture is 1.2 × the base high, its width by the ratio and at
/// least [inAppMiniMinPortraitWidth]. A size from "小窗大小" multiplies the
/// base by its [factor] (A07.22).
Size inAppMiniSize({required Size screen, required double aspectRatio, double factor = 1}) {
  final base = inAppMiniBase(screen) * factor;
  final ratio = _windowRatio(aspectRatio);
  if (ratio >= 1) return Size(base, base / ratio);
  var height = base * 1.2;
  var width = height * ratio;
  if (width < inAppMiniMinPortraitWidth) {
    width = inAppMiniMinPortraitWidth;
    height = width / ratio;
  }
  return Size(width, height);
}

double _windowRatio(double aspectRatio) =>
    aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio.clamp(1 / 2.39, 4.0) : 16 / 9;

/// The narrowest a portrait picture's window gets (3.x: 120).
const double inAppMiniMinPortraitWidth = 120;

/// "小窗大小" (A07.22, V01.5): the factor of each size on [inAppMiniBase];
/// `medium` is A07.8 c6's size (the default). On a phone 176, 220 and 275
/// wide.
const Map<String, double> inAppMiniSizes = {'small': 0.8, 'medium': 1, 'large': 1.25};

/// The shortest a resize makes the window's long side (A07.22).
const double inAppMiniMinExtent = 160;

/// A resize makes the window's long side at most the screen's short side ×
/// this (A07.22: the window does not cover the page it floats over).
const double inAppMiniMaxFraction = 0.9;

/// Whether the window of a picture of [aspectRatio] is a portrait one: its
/// height is its long side, and its resize is remembered apart (A07.22).
bool inAppMiniPortrait(double aspectRatio) => _windowRatio(aspectRatio) < 1;

/// The room the floating window may take in an [area]: [inAppMiniMargin]
/// from the sides, the clearances from the top and the bottom
/// ([inAppMiniOffset]'s).
Size inAppMiniRoom({required Size area, required double topClearance, required double bottomClearance}) =>
    Size(math.max(0, area.width - inAppMiniMargin * 2), math.max(0, area.height - topClearance - bottomClearance));

/// The user's resize [scale] of the floating window, bounded (A07.22): the
/// window of [size] ("小窗大小", a key of [inAppMiniSizes]) times the scale
/// keeps its long side from [inAppMiniMinExtent] (a portrait picture's
/// width from [inAppMiniMinPortraitWidth]) up to the [screen]'s short side
/// × [inAppMiniMaxFraction] and inside the [room]; the size's own window is
/// always allowed, so 1 is never changed.
double inAppMiniScale({
  required Size screen,
  required double aspectRatio,
  required double scale,
  String size = 'medium',
  Size? room,
}) {
  if (!scale.isFinite || scale <= 0) return 1;
  final ratio = _windowRatio(aspectRatio);
  final natural = inAppMiniSize(screen: screen, aspectRatio: aspectRatio, factor: inAppMiniSizes[size] ?? 1);
  final portrait = ratio < 1;
  final long = portrait ? natural.height : natural.width;
  final smallest = math.max(inAppMiniMinExtent, portrait ? inAppMiniMinPortraitWidth / ratio : 0);
  var largest = math.min(screen.width, screen.height) * inAppMiniMaxFraction;
  if (room != null) {
    largest = math.min(
      largest,
      portrait ? math.min(room.height, room.width / ratio) : math.min(room.width, room.height * ratio),
    );
  }
  final extent = (long * scale).clamp(math.min(long, smallest), math.max(long, largest));
  return extent / long;
}

/// The floating window's size (A07.22): "小窗大小"'s [size] for a picture
/// of [aspectRatio], times the user's resize [scale] as [inAppMiniScale]
/// bounds it.
Size inAppMiniWindowSize({
  required Size screen,
  required double aspectRatio,
  String size = 'medium',
  double scale = 1,
  Size? room,
}) {
  final natural = inAppMiniSize(screen: screen, aspectRatio: aspectRatio, factor: inAppMiniSizes[size] ?? 1);
  if (scale == 1) return natural;
  final bounded = inAppMiniScale(screen: screen, aspectRatio: aspectRatio, scale: scale, size: size, room: room);
  return natural * bounded;
}

/// Which bottom corner of the floating window has the resize grip (A07.22).
enum MiniGripCorner {
  /// For a window on the right half of the screen (where it starts).
  bottomLeft,

  /// For a window on the left half.
  bottomRight,
}

/// The grip's corner for a floating [window] in an [area]: the bottom one
/// towards the middle, so pulling it outwards has room to grow (a grip at
/// the corner the window sits in has none: 16 from the edge).
MiniGripCorner inAppMiniGripCorner({required Rect window, required Size area}) =>
    window.center.dx > area.width / 2 ? MiniGripCorner.bottomLeft : MiniGripCorner.bottomRight;

/// The long side a grip drag asks for (A07.22): the window's long side when
/// the drag began ([from]) plus the way the finger [moved] sideways since:
/// away from the window (leftwards on a [MiniGripCorner.bottomLeft] grip)
/// grows it, the picture's shape kept. Up and down do not count: a window
/// resting on the bottom has no room below, and a finger pulling it larger
/// towards the middle of the screen goes up as well (by the upright axis it
/// would shrink it; upstream media_core 7319d2d took the axis moved
/// further).
double inAppMiniGripExtent({required Size from, required MiniGripCorner corner, required Offset moved}) {
  final portrait = from.width < from.height;
  final wider = corner == MiniGripCorner.bottomLeft ? -moved.dx : moved.dx;
  final long = portrait ? from.height : from.width;
  return long + (portrait ? wider * from.height / from.width : wider);
}

/// How a resize moves the floating window (A07.22).
enum MiniResizeAnchor {
  /// A bottom-left grip: the top-right corner stays.
  topRight,

  /// A bottom-right grip: the top-left corner stays.
  topLeft,

  /// Two fingers: the centre stays.
  centre,
}

/// The top-left of a window resized from [from] to [size], [anchor] kept in
/// place; [inAppMiniOffset] then keeps it on screen (a window at the bottom
/// grows upwards).
Offset inAppMiniResizedOffset({required Rect from, required Size size, required MiniResizeAnchor anchor}) =>
    switch (anchor) {
      MiniResizeAnchor.topLeft => from.topLeft,
      MiniResizeAnchor.topRight => Offset(from.right - size.width, from.top),
      MiniResizeAnchor.centre => from.center - Offset(size.width / 2, size.height / 2),
    };

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
/// 350, from 0.65 up to [maxScale] (D03.3 c3: a picture-in-picture pulled
/// larger, a tablet's or a desktop's window, grows them; 3.x stopped at 1),
/// but the text stays at least 10 (c7: 3.x's 220 wide window had 7.8)
/// unless the user chose smaller.
final class CompactDanmakuMetrics {
  const new _({required this.fontSize, required this.speed, required this.laneHeight});

  /// Resolves the metrics for a window [width] wide.
  factory resolve({required double width, required bool autoScale, required double fontSize, required double speed}) {
    final safeWidth = width.isFinite && width > 0 ? width : referenceWidth;
    final scale = autoScale ? (safeWidth / referenceWidth).clamp(0.65, maxScale) : 1.0;
    final scaled = fontSize * scale;
    final size = autoScale ? math.max(scaled, math.min(fontSize, minimumFontSize)) : fontSize;
    return CompactDanmakuMetrics._(
      fontSize: size,
      speed: speed * scale,
      // 3.x's track: 1.8 × the text or the text + 10, within 18–88 (3.x
      // 44, raised with [maxScale] as upstream did).
      laneHeight: math.max(size * 1.8, size + 10).clamp(18.0, 88.0),
    );
  }

  /// The width the configured size is for.
  static const double referenceWidth = 350;

  /// The most a wide window enlarges the configured size and speed (upstream
  /// pure_live b2cca41c7, "画中画弹幕随窗口放大成比例缩放"; 3.x had 1).
  static const double maxScale = 2;

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
