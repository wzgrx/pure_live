import 'package:live_core/live_core.dart';

/// The picture behind a room's stream (docs/A-界面设计/A07-直播间界面/A07.16-京东直播间模糊背景
/// c1, c2): the ambient background of a portrait stream, the dimmed cover
/// of audio only and of a recovery. JD Live's play answer gives a blurred
/// frame of the broadcast ([JdLiveRoom.background], upgrade 28-3), which
/// comes first, as 3.x's room showed it; then the room's cover, then, with
/// [orAvatar], the streamer's avatar. '' when there is none.
String roomBackdropOf(LiveRoom room, {bool orAvatar = true}) {
  if (room.data case JdLiveRoom(:final background) when background.trim().isNotEmpty) return background;
  if (room.cover.trim().isNotEmpty || !orAvatar) return room.cover;
  return room.avatar;
}
