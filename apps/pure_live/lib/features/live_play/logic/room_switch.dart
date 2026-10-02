import 'dart:math' as math;

import 'package:live_core/live_core.dart';

// The live room's "切换直播间" panel (docs/ui/compare/U.2m): its groups, the
// rooms in each, and v3's grid of small cards (3.x
// `content_first_panel_layout.dart:214-310`, `play_other.dart:229-268`).

/// The groups of the panel, in their order (U.2m c5).
enum RoomSwitchGroup {
  /// Followed rooms on air, by audience (3.x "已开播").
  onAir,

  /// The list the room was opened from (popular, an area, search; U.2b2).
  source,

  /// The watch history, newest first.
  history,

  /// Followed rooms showing a replay, by audience (3.x "录播").
  replays,
}

/// How the panel shows the rooms (the `roomSwitcherLayout` setting, U.2m c4).
enum RoomSwitchLayout {
  /// 3.x's small cards (the default, GitHub issue #37).
  grid,

  /// Rows with a 16:9 cover.
  list;

  /// The layout stored as [value]; the grid for anything else.
  static RoomSwitchLayout of(String value) => value == list.name ? list : grid;
}

/// The grid's padding (3.x `_buildRoomGrid`).
const double roomSwitchGridPadding = 6;

/// The space between cards (3.x).
const double roomSwitchGridSpacing = 5;

/// The narrowest card (3.x `resolveRoomHistoryColumns`): two fit from a
/// 353 wide grid.
const double roomSwitchMinCardWidth = 168;

/// The card's name line under the cover at the standard text size.
const double roomSwitchCardFooter = 26;

/// The least cover height of a card squeezed to keep two rows in view
/// (3.x `minimumCoverHeight`).
const double roomSwitchMinCover = 60;

/// The list style's row: a 112 × 63 cover and 6 above and below.
const double roomSwitchRowHeight = 75;

/// The columns of a grid [width] wide: as many 168 cards as fit (3.x's
/// rule, which stopped at two: the same columns up to a 525 wide grid, so on
/// every phone; wider grids get more, so a tablet held upright shows more
/// cards than 3.x, not fewer).
int roomSwitchColumns(double width) {
  if (!width.isFinite || width <= 0) return 1;
  final usable = math.max(0, width - roomSwitchGridPadding * 2);
  return math.max(1, ((usable + roomSwitchGridSpacing) / (roomSwitchMinCardWidth + roomSwitchGridSpacing)).floor());
}

/// The card height in a grid [width] × [height] of [columns] (3.x
/// `resolveRoomHistoryCardHeight`): a 16:9 cover over the [footer]; with two
/// or more columns squeezed until two rows fit, down to a 60 high cover
/// and never under 96.
double roomSwitchCardHeight({
  required double width,
  required double height,
  required int columns,
  double footer = roomSwitchCardFooter,
}) {
  final count = math.max(1, columns);
  final usable = math.max(0, width - roomSwitchGridPadding * 2 - roomSwitchGridSpacing * (count - 1));
  final natural = usable / count * 9 / 16 + footer;
  final floor = math.max(96, footer + roomSwitchMinCover).toDouble();
  if (count < 2 || !height.isFinite) return math.max(natural, floor);
  final twoRows = (height - roomSwitchGridPadding * 2 - roomSwitchGridSpacing) / 2;
  return math.max(floor, math.min(natural, twoRows));
}

/// The rooms of every group, the room being watched left out.
final class RoomSwitchLists {
  /// Creates the lists.
  const new({required this.onAir, required this.source, required this.history, required this.replays});

  /// No rooms.
  static const empty = RoomSwitchLists(onAir: [], source: [], history: [], replays: []);

  /// Followed rooms on air.
  final List<LiveRoom> onAir;

  /// The list the room was opened from; empty when it came from the follows
  /// or from nowhere (U.2m X3).
  final List<LiveRoom> source;

  /// The watch history.
  final List<LiveRoom> history;

  /// Followed replays.
  final List<LiveRoom> replays;

  /// The groups offered: the source only with a list.
  List<RoomSwitchGroup> get groups => [
    for (final group in RoomSwitchGroup.values)
      if (group != RoomSwitchGroup.source || source.isNotEmpty) group,
  ];

  /// The rooms of [group].
  List<LiveRoom> of(RoomSwitchGroup group) => switch (group) {
    RoomSwitchGroup.onAir => onAir,
    RoomSwitchGroup.source => source,
    RoomSwitchGroup.history => history,
    RoomSwitchGroup.replays => replays,
  };

  /// The group the panel opens on (U.2m X1): the one picked before on this
  /// page while it is still offered, else the source list when there is one
  /// (the user was going through it), else the followed rooms on air.
  RoomSwitchGroup initial(RoomSwitchGroup? remembered) {
    if (remembered != null && groups.contains(remembered)) return remembered;
    return source.isNotEmpty ? RoomSwitchGroup.source : RoomSwitchGroup.onAir;
  }
}

/// The panel's groups from the follows, the watch history and the [source]
/// list, without [current]; [rank] orders by audience (3.x
/// `_compareAudience`). A history room that is followed shows the follow's
/// state (refreshed with the follows) and keeps its watch time. A source
/// list made only of follows came from the follows page and is left out.
RoomSwitchLists roomSwitchLists({
  required List<LiveRoom> follows,
  required List<LiveRoom> history,
  required List<LiveRoom> source,
  required LiveRoom current,
  required List<LiveRoom> Function(List<LiveRoom> rooms) rank,
}) {
  bool other(LiveRoom room) => !room.hasSameIdentity(current);
  final followed = {for (final room in follows) room.identityKey: room};
  final fromFollows = source.isNotEmpty && source.every((room) => followed.containsKey(room.identityKey));
  return RoomSwitchLists(
    onAir: rank([
      for (final room in follows)
        if (room.isLiveNow && other(room)) room,
    ]),
    source: fromFollows
        ? const []
        : [
            for (final room in source)
              if (other(room)) room,
          ],
    history: [
      for (final room in history)
        if (other(room))
          switch (followed[room.identityKey]) {
            final follow? => follow.copyWith(lastWatchedAt: room.lastWatchedAt ?? follow.lastWatchedAt),
            null => room,
          },
    ],
    replays: rank([
      for (final room in follows)
        if (room.isRecord && other(room)) room,
    ]),
  );
}

/// The rooms whose streamer's name contains [query], ignoring case and the
/// spaces around it; all of them for an empty query.
List<LiveRoom> filterByStreamer(List<LiveRoom> rooms, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return rooms;
  return [
    for (final room in rooms)
      if (room.nick.toLowerCase().contains(needle)) room,
  ];
}

/// How long ago, in the unit the panel writes ("刚刚", "5 分钟前", "2 小时前",
/// "3 天前").
enum AgoUnit {
  /// Under a minute.
  now,

  /// Under an hour.
  minutes,

  /// Under a day.
  hours,

  /// A day or more.
  days,
}

/// How long before [now] [then] was.
({AgoUnit unit, int count}) agoOf(DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return (unit: AgoUnit.now, count: 0);
  if (elapsed.inHours < 1) return (unit: AgoUnit.minutes, count: elapsed.inMinutes);
  if (elapsed.inDays < 1) return (unit: AgoUnit.hours, count: elapsed.inHours);
  return (unit: AgoUnit.days, count: elapsed.inDays);
}
