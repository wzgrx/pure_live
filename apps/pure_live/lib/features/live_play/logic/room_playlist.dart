import 'dart:math' as math;

import 'package:live_core/live_core.dart';

/// The rooms a live room was opened from (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏 U.2b2), in
/// that page's order, and where the room is among them: the portrait
/// fullscreen swipes up to the next and down to the previous, wrapping
/// around at either end (the TV's Up and Down, `TvLivePlayPage.switchBy`).
final class RoomPlaylist {
  /// The list [rooms] with [current] in it; a room missing from the list
  /// goes first (as the TV room).
  new(List<LiveRoom> rooms, {required LiveRoom current})
    : rooms = List.unmodifiable(rooms.any(current.hasSameIdentity) ? rooms : [current, ...rooms]),
      _index = math.max(0, rooms.indexWhere(current.hasSameIdentity));

  /// The rooms, in their page's order.
  final List<LiveRoom> rooms;

  int _index;

  /// The room shown now.
  int get index => _index;

  /// Whether there is another room to swipe to (a lone room has none).
  bool get swipeable => rooms.length > 1;

  /// The room [step] places away (1 the next, -1 the previous), wrapping
  /// around; null when there is nothing to swipe to.
  LiveRoom? neighbour(int step) => swipeable ? rooms[(_index + step) % rooms.length] : null;

  /// Moves [step] places and returns the room there.
  LiveRoom move(int step) {
    if (swipeable) _index = (_index + step) % rooms.length;
    return rooms[_index];
  }
}
