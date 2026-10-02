import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';

// The panel itself moved to lib/shared (the multi-view page shows it too).
export 'package:pure_live/shared/panels/side_panel.dart';

/// The panels the live room opens beside the picture (docs/ui/compare/U.2f,
/// 统一规则): recording, the danmaku settings, switching rooms (U.2m), the
/// room menu's settings and a long-pressed danmaku (U.2n). One at a time.
enum RoomPanelKind {
  /// The record panel (the bar's record button, the "● 录制中" mark).
  record,

  /// The danmaku settings (the picture's settings button).
  danmaku,

  /// The IPTV programme guide in landscape fullscreen (docs/ui/compare/U.2g
  /// c16: under the picture in portrait, in the right column on wide
  /// windows, here on the right).
  guide,

  /// The local interaction (the room menu's "本地互动体验", U.2k).
  localInteraction,

  /// The local danmaku style (a local composer's star, U.2k).
  localStyle,

  /// "切换直播间" (docs/ui/compare/U.2m): the room menu's first entry, the
  /// fullscreen bars' ⇄ and the picture states' button.
  switchRoom,

  /// "定时关闭" (docs/ui/compare/U.2n c1): the room menu.
  sleepTimer,

  /// "房间音量" (U.2n c1, c2): the room menu.
  volume,

  /// "获取直链" (U.2n c1, c4): the room menu.
  streamLink,

  /// "投屏" (U.2n c1, c4): the room menu and the fullscreen top bar.
  cast,

  /// A long-pressed (or tapped flying) danmaku (U.2n c1; UI_PLAN §7):
  /// [RoomPanelController.message].
  message,
}

/// The panel open in the room, or null.
final class RoomPanelController extends ValueNotifier<RoomPanelKind?> {
  /// Creates the controller with no panel open.
  new() : super(null);

  /// The danmaku of [RoomPanelKind.message].
  LiveMessage? get message => _message;
  LiveMessage? _message;

  /// Opens [kind] (closing another one).
  void open(RoomPanelKind kind) {
    if (value != kind) value = kind;
  }

  /// Opens the actions of [message] (another message replaces the one shown).
  void openMessage(LiveMessage message) {
    _message = message;
    if (value == RoomPanelKind.message) {
      notifyListeners();
    } else {
      value = RoomPanelKind.message;
    }
  }

  /// Closes the panel.
  void close() => value = null;
}

/// Opens a room panel where there is no room page around [context] (a lone
/// button, the settings page): the app's panel for pages without a picture
/// (docs/ui/compare/U.1d c10: from the bottom with a handle on phones,
/// [heightFactor] of the screen high; on the right from
/// [sidePanelBreakpoint]). [builder] gets the sheet's context and what
/// closes it.
Future<void> showRoomPanelSheet(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double heightFactor = 0.6,
}) {
  final side = MediaQuery.sizeOf(context).width >= sidePanelBreakpoint;
  return showAdaptivePanel<void>(
    context,
    side: side,
    builder: (sheetContext) {
      final panel = builder(sheetContext, () => Navigator.of(sheetContext).pop());
      return side ? panel : SizedBox(height: MediaQuery.sizeOf(sheetContext).height * heightFactor, child: panel);
    },
  );
}

/// Gives the room's widgets (the bar's record button, the picture's
/// buttons) the [RoomPanelController] of the page.
class RoomPanelScope extends InheritedNotifier<RoomPanelController> {
  /// Creates the scope.
  const new({required RoomPanelController super.notifier, required super.child, super.key});

  /// The page's controller, or null outside a live room (a lone button
  /// then shows its panel in a sheet). Does not rebuild [context] when a
  /// panel opens.
  static RoomPanelController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RoomPanelScope>()?.notifier;
}
