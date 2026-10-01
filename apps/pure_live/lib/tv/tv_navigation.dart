import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// How the TV room is opened: the room and the list it came from, which the
/// room switches through with Up and Down and shows in its side list
/// (pure_live_TV `LivePlayArgs.playlist`).
@immutable
final class TvRoomArgs {
  /// Creates the arguments.
  const new({required this.room, this.playlist = const [], this.shown});

  /// The room to open.
  final LiveRoom room;

  /// The rooms of the page it was opened from, in its order; empty for a
  /// lone room.
  final List<LiveRoom> playlist;

  /// Set by the room to the room it shows (switching channels changes it),
  /// so the page below knows where to put the focus back.
  final ValueNotifier<LiveRoom?>? shown;

  /// [room]'s place in [playlist] (by identity), or -1.
  int get index => playlist.indexWhere(room.hasSameIdentity);
}

bool _opening = false;

/// Opens [room] in the TV room with [playlist] as its channel list; the
/// future completes with the room shown last when the user comes back
/// (after switching channels it is not [room]), or null.
///
/// The checks are the phone's (`AppNavigator.toLiveRoomDetail`): a retired
/// platform or a missing id is refused with the same words, and a second
/// request while one opens is ignored.
Future<LiveRoom?> openTvRoom(LiveRoom room, {List<LiveRoom> playlist = const []}) async {
  if (_opening) return null;
  final platform = room.platform.trim().toLowerCase();
  if (platform.isEmpty || room.roomId.isEmpty || !SiteIds.isSupported(platform)) {
    AppNavigator.toast(i18n(SiteIds.isRetired(platform) ? 'platform_retired' : 'get_room_info_failed_retry'));
    return null;
  }
  _opening = true;
  unawaited(Future<void>.delayed(AppNavigator.openGuard, () => _opening = false));
  final playable = [
    for (final item in playlist)
      if (SiteIds.isSupported(item.platform.trim().toLowerCase()) && item.roomId.isNotEmpty) item,
  ];
  final shown = ValueNotifier<LiveRoom?>(room);
  try {
    await AppNavigator.toNamed<Object?>(
      RoutePath.kLivePlay,
      arguments: TvRoomArgs(room: room, playlist: playable, shown: shown),
    );
    return shown.value;
  } finally {
    shown.dispose();
  }
}
