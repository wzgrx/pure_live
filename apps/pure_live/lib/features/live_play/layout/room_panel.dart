import 'package:flutter/material.dart';

// The panel itself moved to lib/shared (the multi-view page shows it too).
export 'package:pure_live/shared/panels/side_panel.dart';

/// The panels the live room opens beside the picture (docs/ui/compare/U.2f,
/// 统一规则): recording and the danmaku settings. One at a time.
enum RoomPanelKind {
  /// The record panel (the bar's record button, the "● 录制中" mark).
  record,

  /// The danmaku settings (the picture's settings button).
  danmaku,
}

/// The panel open in the room, or null.
final class RoomPanelController extends ValueNotifier<RoomPanelKind?> {
  /// Creates the controller with no panel open.
  new() : super(null);

  /// Opens [kind] (closing another one).
  void open(RoomPanelKind kind) {
    if (value != kind) value = kind;
  }

  /// Closes the panel.
  void close() => value = null;
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
