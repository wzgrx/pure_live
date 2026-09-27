import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// One room of a switch list.
@immutable
final class RoomEntry {
  const new(this.ref, {this.name = '', this.title = ''});

  /// The room.
  final RoomRef ref;

  /// Streamer's name; empty when unknown.
  final String name;

  /// Broadcast title; empty when unknown.
  final String title;

  /// What the switch hint shows.
  String get label => name.isEmpty ? ref.roomId : name;
}

/// The list a room was opened from (spec/product.md F-NEW-04, live-room
/// T-05, principles §6.3): the live rooms of the follows grid, a discover or
/// area page, or search results, in the order shown. Passed as the room
/// route's `extra`; up and down on a remote, PageUp and PageDown, and the
/// optional portrait swipe step through it.
@immutable
final class RoomOrigin {
  const new(this.entries, {this.label});

  /// The live rooms of cards, in order.
  factory fromCards(Iterable<RoomCard> cards, {String? label}) => RoomOrigin([
    for (final card in cards)
      if (card.state == LiveState.live) RoomEntry(card.ref, name: card.anchorName, title: card.title),
  ], label: label);

  /// Rooms in order.
  final List<RoomEntry> entries;

  /// Name of the list for the TV room list panel (`开播的关注`).
  final String? label;
}

/// Audience figure used to order live follows (the follows page's order).
int followAudience(StoredRoom room) =>
    room.audience.online ?? room.audience.popularity ?? room.audience.cumulative ?? 0;

/// The live follows by audience, as the follows page shows them: the list
/// for rooms opened from a link, search history or elsewhere (T-05).
List<RoomEntry> liveFollowEntries(Iterable<FollowedRoom> follows) {
  final live = [
    for (final follow in follows)
      if (follow.room.lastState == LiveState.live) follow.room,
  ]..sort((a, b) => followAudience(b).compareTo(followAudience(a)));
  return [for (final room in live) RoomEntry(room.ref, name: room.anchorName, title: room.title)];
}

/// The room [step] places after [current] in [list] (-1 previous, +1
/// next), or null at either end: switching never wraps around (T-05). A
/// room that is not in the list (opened from elsewhere) goes to the first
/// entry on next and the last on previous.
RoomEntry? neighborRoom(List<RoomEntry> list, RoomRef current, int step) {
  if (list.isEmpty || step == 0) return null;
  final index = list.indexWhere((entry) => entry.ref == current);
  if (index < 0) return step > 0 ? list.first : list.last;
  final target = index + step;
  return target < 0 || target >= list.length ? null : list[target];
}
