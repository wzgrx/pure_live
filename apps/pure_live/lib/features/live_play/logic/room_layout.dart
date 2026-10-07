import 'dart:math' as math;

/// How the live room is shown (docs/specs/UI.md §5.3: one state for the
/// room; the picture is mounted once and moves between them). Android's
/// picture-in-picture is followed separately (the system's window).
enum RoomDisplay {
  /// The room page: the picture with the header, the room strip and the
  /// chat (phone stack, portrait panel or the wide split).
  inline,

  /// The picture fills the screen (phones: immersive, turned as the
  /// fullscreen orientation setting says; desktops: the window's full
  /// screen).
  fullscreen,

  /// A portrait stream filling an upright phone (3.x
  /// `VideoMode.portraitFullscreen`, docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏).
  portraitFullscreen,

  /// Desktops: the picture fills the window, the header and the chat hidden
  /// (3.x `isWindowFullscreen`).
  windowFullscreen,
}

/// How the page lays the room out while [RoomDisplay.inline].
enum RoomPageLayout {
  /// Picture (16:9) on top, the room strip and the chat below.
  phone,

  /// A portrait stream: the picture fills the area and a three-stop panel
  /// with the strip and the chat covers its lower part (U.2b).
  portraitPanel,

  /// The picture beside the chat column (U.2d).
  wide,

  /// A phone held sideways, not in fullscreen (a short window, 600 or
  /// wider; UI_PLAN §5.1: a compact height wins over the width): the
  /// picture at the full height under the app bar and only the chat list in
  /// a [phoneLandscapeChatWidth] column on its right (A07.17 c2, choice A:
  /// the tablet's split left the list one line).
  landscape,
}

/// How the controls over the picture are arranged: one control layer, three
/// arrangements (U.2b-U.2d).
enum ControlsArrangement {
  /// The room page: a title bar and one bottom bar.
  inline,

  /// Landscape fullscreen (U.2c) and the in-window fullscreen.
  landscape,

  /// Two rows at the top and two at the bottom (U.2b's portrait
  /// fullscreen).
  portraitFullscreen,
}

/// The least width that puts the chat beside the picture (UI_PLAN §5.1:
/// "expanded"; 3.x split from 680, which squeezed the picture, U.2d W1).
const double roomWideMinWidth = 840;

/// Heights below this are a phone held sideways, whatever the width.
const double roomCompactMaxHeight = 480;

/// The chat list's column of a phone held sideways (A07.17 c2).
const double phoneLandscapeChatWidth = 280;

/// The page layout for an area of [width] × [height]; [portraitPanel] when a
/// portrait stream gets the three-stop panel ([portraitPanelEligible]). A
/// short window sideways is [RoomPageLayout.landscape] on phones; a desktop
/// window as short keeps the split of [RoomPageLayout.wide] it always had.
RoomPageLayout roomPageLayout({
  required double width,
  required double height,
  required bool portraitPanel,
  bool mobile = true,
}) {
  if (height < roomCompactMaxHeight && width > height && width >= 600) {
    return mobile ? RoomPageLayout.landscape : RoomPageLayout.wide;
  }
  if (width >= roomWideMinWidth) return RoomPageLayout.wide;
  return portraitPanel ? RoomPageLayout.portraitPanel : RoomPageLayout.phone;
}

/// The controls for [display] in an area of [width] × [height]: a phone's
/// fullscreen follows the screen it got (portrait fullscreen when upright,
/// U.2b change 5), desktops never use the portrait rows.
ControlsArrangement controlsArrangement({
  required RoomDisplay display,
  required RoomPageLayout page,
  required double width,
  required double height,
  required bool mobile,
}) {
  final upright = mobile && height > width;
  return switch (display) {
    RoomDisplay.inline => ControlsArrangement.inline,
    RoomDisplay.fullscreen ||
    RoomDisplay.portraitFullscreen => upright ? ControlsArrangement.portraitFullscreen : ControlsArrangement.landscape,
    RoomDisplay.windowFullscreen => ControlsArrangement.landscape,
  };
}

/// Whether a portrait stream gets the three-stop panel (3.x
/// `useAdaptivePortraitFrame`): portrait adaptation and the adaptive height
/// on, and a layout other than "兼容 16:9".
bool portraitPanelEligible({
  required bool portraitStream,
  required bool adaptation,
  required bool adaptiveHeight,
  required String layoutMode,
}) => portraitStream && adaptation && adaptiveHeight && layoutMode != 'compatibility';

/// Whether fullscreen means the portrait fullscreen: a portrait stream on a
/// phone or tablet with portrait adaptation on, whatever the room layout
/// (U.2b change 5: 3.x squeezed the landscape row into the upright screen
/// for "兼容 16:9"), unless the fullscreen orientation is "始终横屏".
bool portraitFullscreenEligible({
  required bool mobile,
  required bool portraitStream,
  required bool adaptation,
  String policy = 'followSource',
}) => mobile && portraitStream && adaptation && policy != 'landscape';

/// The fullscreen orientation setting (`portraitFullscreenPolicy`).
enum FullscreenOrientation {
  /// Upright for portrait streams, sideways for the rest.
  followSource,

  /// Whatever the phone is held as.
  followSystem,

  /// Always sideways.
  landscape;

  /// The setting's value [name], else [followSource].
  static FullscreenOrientation of(String name) => values.asNameMap()[name] ?? followSource;
}

/// The three heights of the portrait room's panel in an area [height] high
/// (3.x `portraitPanelRange`: 27 %, 44 % and 68 %, at least 120 left for
/// the picture). The lowest keeps the strip, the tabs and two chat lines in
/// view (U.2b change 4: 3.x's 200 left only the tabs once the strip has two
/// lines; 250 on a 393 × 852 phone). "沉浸" starts at the lowest, the rest in
/// the middle.
///
/// [least] is the lowest stop ([portraitPanelLeast]). The local danmaku
/// composer is a star on the chat list here (A07.17 c3), so it takes no
/// height of its own.
({double minimum, double middle, double maximum, double initial}) portraitPanelStops(
  double height,
  String mode, {
  double least = portraitPanelLeast,
}) {
  final area = height.isFinite ? math.max(0, height).toDouble() : 0.0;
  final minimum = math.min(least, area);
  final ceiling = math.max(minimum, area - 120);
  final maximum = (area * 0.68).clamp(minimum, ceiling);
  final middle = (area * 0.44).clamp(minimum, maximum);
  return (minimum: minimum, middle: middle, maximum: maximum, initial: mode == 'immersive' ? minimum : middle);
}

/// The lowest panel: the handle row 48, the two-line strip 92, the tabs 48
/// and two chat lines 62.
const double portraitPanelLeast = 250;

/// The stop nearest [height].
double nearestStop(double height, Iterable<double> stops) =>
    stops.reduce((a, b) => (a - height).abs() <= (b - height).abs() ? a : b);

/// Whether a drag of the panel that went [dismissed] past its lowest stop
/// (and ended at [velocity], downwards positive) enters the portrait
/// fullscreen (3.x `resolvePortraitPanelDragEnd`): 30 % of the panel
/// (72–144), or a fling of 900 after at least 28.
bool panelDragEntersFullscreen({required double dismissed, required double panelHeight, required double velocity}) {
  if (dismissed <= 0 || panelHeight <= 0) return false;
  final distance = (panelHeight * 0.30).clamp(72.0, 144.0);
  return dismissed >= distance || (velocity >= 900 && dismissed >= 28);
}

/// Where an upward swipe brings the portrait fullscreen back to the panel:
/// the lowest [portraitRestoreZone] of the screen, and the bottom bar.
const double portraitRestoreZone = 96;

/// Whether an upward swipe of [upward] ending at [velocity] (upwards
/// negative) restores the panel (3.x `shouldRestorePortraitPanelFromSwipe`).
bool swipeRestoresPanel({required double upward, required double velocity}) =>
    upward >= 64 || (velocity <= -850 && upward >= 24);

/// What a vertical drag on the picture changes.
enum PictureDrag {
  /// The window's brightness.
  brightness,

  /// The volume.
  volume,

  /// The room: the next one upwards, the previous one downwards (U.2b2).
  switchRoom,
}

/// What a vertical drag starting [x] across a picture [width] wide changes:
/// the left half the brightness and the right half the volume (3.x); with
/// [switchRooms] (the portrait fullscreen's swipe, U.2b2) the picture is in
/// thirds and the middle one switches rooms.
PictureDrag pictureDragAt({required double x, required double width, bool switchRooms = false}) {
  if (!switchRooms) return x < width / 2 ? PictureDrag.brightness : PictureDrag.volume;
  if (x < width / 3) return PictureDrag.brightness;
  return x > width * 2 / 3 ? PictureDrag.volume : PictureDrag.switchRoom;
}

/// Where a swipe between rooms that moved the picture by [offset] (upwards
/// negative) of a screen [extent] high and ended at [velocity] (upwards
/// negative) goes (U.2b2): 1 to the next room (upwards), -1 to the previous
/// (downwards), 0 back to this one. A third of the screen or a fling of 800
/// after 48 switches; a fling back the other way keeps the room.
int swipeSwitchStep({required double offset, required double extent, required double velocity}) {
  if (extent <= 0 || offset == 0) return 0;
  final fling = velocity.abs() >= 800;
  if (fling && velocity.sign != offset.sign) return 0;
  final far = offset.abs() >= extent / 3 || (fling && offset.abs() >= 48);
  if (!far) return 0;
  return offset < 0 ? 1 : -1;
}

/// How a portrait stream fills the upright fullscreen (3.x
/// `PortraitFullscreenDisplayMode`, the setting `portraitFullscreenDisplayMode`).
enum PortraitDisplayMode {
  /// The whole picture, plain black around it.
  complete,

  /// The whole picture over the ambient background (default).
  ambient,

  /// Zoomed in by at most 8 %, the rest ambient.
  balanced,

  /// Fills the screen, cropping the sides.
  cover;

  /// The setting's value [name], else [ambient].
  static PortraitDisplayMode of(String name) => values.asNameMap()[name] ?? ambient;
}

/// The zoom of [PortraitDisplayMode.balanced] for a picture of
/// [aspectRatio] in [width] × [height] (3.x
/// `resolvePortraitFullscreenBalancedScale`): what would fill the box, but
/// no more than [maximum].
double balancedScale({
  required double width,
  required double height,
  required double aspectRatio,
  double maximum = 1.08,
}) {
  if (width <= 0 || height <= 0 || !aspectRatio.isFinite || aspectRatio <= 0) return 1;
  final box = width / height;
  final cover = box < aspectRatio ? aspectRatio / box : box / aspectRatio;
  return cover.clamp(1.0, maximum);
}

/// The width of the wide room's chat column (3.x: 34 % of the window, 300 to
/// 400; U.2d choice H3).
double chatColumnWidth(double width) => (width * 0.34).clamp(300.0, 400.0);
