import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/pages/multiview/multiview_controller.dart';

import '../../live_play_support.dart';
import '../../support.dart';

/// A Bilibili adapter whose rooms answer by id (the multi-view tests).
class RoomsSite extends FakeSite {
  /// Creates the platform.
  new() : super(liveRoom());

  /// Rooms that are not on air.
  final Set<String> offline = {};

  /// Rooms whose detail fails.
  final Set<String> failing = {};

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    detailCalls++;
    if (failing.contains(roomId)) throw const TransportFailure(SiteIds.bilibili, TransportReason.connect);
    return pickRoom(roomId, status: offline.contains(roomId) ? LiveStatus.offline : LiveStatus.live);
  }
}

/// Bilibili room [id] as a card (the picker's data).
LiveRoom pickRoom(String id, {LiveStatus status = LiveStatus.live}) => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: id,
  nick: '主播$id',
  title: '标题$id',
  liveStatus: status,
  danmakuData: 'args-$id',
);

/// A controller over [site] and fake players; [danmaku] collects the
/// connections it makes.
MultiviewController multiviewController(
  LiveStore store,
  RoomsSite site, {
  List<FakeDanmaku>? danmaku,
  List<FakeEngine>? engines,
  bool mobile = false,
  List<String>? toasts,
}) => MultiviewController(
  siteOf: (platform) => platform == SiteIds.bilibili ? site : null,
  newSession: () {
    final engine = FakeEngine();
    engines?.add(engine);
    return fakeSession(engine);
  },
  danmakuFor: (platform) {
    final connection = FakeDanmaku();
    danmaku?.add(connection);
    return connection;
  },
  danmakuSupports: (platform) => platform == SiteIds.bilibili,
  store: store,
  mobile: mobile,
  toast: toasts?.add,
);

/// An in-memory store.
Future<LiveStore> memoryStore() => LiveStore.memory(cipher: FakeCipher());
