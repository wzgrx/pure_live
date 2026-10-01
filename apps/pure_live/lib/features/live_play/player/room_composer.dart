import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

/// The local danmaku composer the fullscreen bars leave room for (3.x
/// `FullscreenLocalDanmakuComposer`; docs/ui/compare/U.2c change 3, U.2b
/// change 7). Local interaction (U.2k) provides it: the bars only place it.
///
/// - Landscape fullscreen: the field between the two button groups, at most
///   420 wide; on a narrow bar (under 760) a star button in its place, in
///   the local danmaku [color], that opens the field in a row above the bar.
/// - Portrait fullscreen: the field on the bottom rows' first line, before
///   the quality and line buttons.
/// - While [available] is false (local interaction off) the bars leave it
///   out and keep the other buttons where they are.
///
/// The controls stay up while the field has focus.
abstract interface class RoomComposer {
  /// Whether local interaction is on, so the composer shows.
  ValueListenable<bool> get available;

  /// The local danmaku colour: the narrow bar's star (white by default).
  ValueListenable<Color> get color;

  /// The input field (the one component of U.2k's three inputs);
  /// [autofocus] when the narrow bar's star opened it.
  Widget buildField(BuildContext context, {required bool autofocus});

  /// Releases what the composer holds (the room is closing).
  void dispose();
}

/// Makes the composer of a room, or null for none.
typedef RoomComposerFactory = RoomComposer? Function(LiveRoomController room);

/// The live room's composer factory: null until local interaction (U.2k)
/// provides one, so the bars show no composer.
final roomComposerProvider = Provider<RoomComposerFactory?>((ref) => null);

/// Hands the bars the room's [composer].
class RoomComposerScope extends InheritedWidget {
  /// Creates the scope.
  const new({required this.composer, required super.child, super.key});

  /// The room's composer, or null.
  final RoomComposer? composer;

  /// The composer above [context], or null.
  static RoomComposer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomComposerScope>()?.composer;

  @override
  bool updateShouldNotify(RoomComposerScope oldWidget) => !identical(composer, oldWidget.composer);
}
