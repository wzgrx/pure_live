import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

/// How a page was opened: its path (a `RoutePath` value), the arguments
/// (3.x `Get.arguments`), and whether it is a tab of the home shell.
///
/// Every page takes one, so the route table never changes when a page is
/// rebuilt (M13 replaces only `lib/pages/<page>/`).
@immutable
final class RouteArgs {
  /// Creates the arguments.
  const new(this.path, {this.arguments, this.inHome = false});

  /// The route path.
  final String path;

  /// The arguments: a `LiveRoom` or [LiveRoomArgs] for the live room,
  /// `[LiveSite, LiveArea]` for an area's rooms, null for most pages.
  final Object? arguments;

  /// Whether the page is a home tab (the phone layout puts the menu and the
  /// search menu in its app bar, 3.x `showAction`).
  final bool inHome;
}

/// The live room opened from a list (docs/T05/T05c/T05c.1 U.2b2, the TV's
/// `TvRoomArgs.playlist`): the follows, popular, an area's rooms or the
/// search results hand their rooms over in their order, and the portrait
/// fullscreen swipes through them. A room opened any other way (a link, the
/// history, the floating window) gets a lone `LiveRoom` instead.
@immutable
final class LiveRoomArgs {
  /// Creates the arguments.
  const new({required this.room, this.playlist = const []});

  /// The room to open.
  final LiveRoom room;

  /// The rooms of the page it was opened from, in its order.
  final List<LiveRoom> playlist;

  /// The room [arguments] (a `LiveRoom` or a [LiveRoomArgs]) opens, or null.
  static LiveRoom? roomOf(Object? arguments) => switch (arguments) {
    final LiveRoom room => room,
    LiveRoomArgs(:final room) => room,
    _ => null,
  };
}
