import 'dart:math' as math;

/// How the live room is shown (docs/ui/UI_PLAN.md §5.3: one state for the
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
  /// `VideoMode.portraitFullscreen`, docs/ui/compare/U.2b).
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

  /// A short window (a phone held sideways): the picture fills it with the
  /// landscape bars (UI_PLAN §5.1: a compact height wins).
  landscape,
}

/// How the controls over the picture are arranged: one control layer, three
/// arrangements (U.2b-U.2d).
enum ControlsArrangement {
  /// The room page: a title bar and one bottom bar.
  inline,

  /// Landscape fullscreen (U.2c), the in-window fullscreen and a short
  /// window.
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

/// The page layout for an area of [width] × [height]; [portraitPanel] when a
/// portrait stream gets the three-stop panel ([portraitPanelEligible]).
RoomPageLayout roomPageLayout({required double width, required double height, required bool portraitPanel}) {
  if (height < roomCompactMaxHeight && width > height) return RoomPageLayout.landscape;
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
    RoomDisplay.inline => page == RoomPageLayout.landscape ? ControlsArrangement.landscape : ControlsArrangement.inline,
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
({double minimum, double middle, double maximum, double initial}) portraitPanelStops(double height, String mode) {
  final area = height.isFinite ? math.max(0, height).toDouble() : 0.0;
  final minimum = math.min(portraitPanelLeast, area);
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
