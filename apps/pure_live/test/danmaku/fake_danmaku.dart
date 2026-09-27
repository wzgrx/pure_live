import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart' show DanmakuHit, DanmakuItem;
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';

/// A chat connection the test drives: [emit] delivers a batch the way the
/// worker would (one per event-loop turn).
final class FakeDanmakuFeed implements DanmakuFeed {
  new(this.room, this.initialSettings, this.initialBudget);

  final RoomDetail room;
  final DanmakuFilterSettings initialSettings;
  final DanmakuScreenBudget initialBudget;
  final StreamController<DanmakuBatch> _batches = StreamController<DanmakuBatch>();

  /// Settings sent with [update], in order.
  final List<DanmakuFilterSettings> settings = [];

  /// Budgets sent with [update], in order.
  final List<DanmakuScreenBudget> budgets = [];
  bool closed = false;

  @override
  Stream<DanmakuBatch> get batches => _batches.stream;

  @override
  void update({DanmakuFilterSettings? settings, DanmakuScreenBudget? budget}) {
    if (settings != null) this.settings.add(settings);
    if (budget != null) budgets.add(budget);
  }

  @override
  Future<void> close() async {
    closed = true;
    unawaited(_batches.close());
  }

  /// Delivers [batch] (stamped with this feed's room).
  void emit(DanmakuBatch batch) {
    if (!closed) _batches.add(batch);
  }

  /// The latest filter settings the worker has.
  DanmakuFilterSettings get current => settings.isEmpty ? initialSettings : settings.last;
}

/// Opens [FakeDanmakuFeed]s.
final class FakeDanmakuSource implements DanmakuSource {
  final List<FakeDanmakuFeed> feeds = [];

  @override
  Future<DanmakuFeed> open(
    RoomDetail room, {
    required DanmakuFilterSettings settings,
    required DanmakuScreenBudget budget,
  }) async {
    final feed = FakeDanmakuFeed(room, settings, budget);
    feeds.add(feed);
    return feed;
  }
}

/// Records what the room feeds the on-video layer.
final class RecordingOnVideo implements OnVideoDanmaku {
  final List<DanmakuItem> items = [];
  final Set<Object> pauses = {};
  int clears = 0;

  @override
  void addAll(Iterable<DanmakuItem> items) => this.items.addAll(items);

  @override
  void clear() {
    clears++;
    items.clear();
  }

  @override
  DanmakuHit? itemAtGlobal(Offset globalPosition) => null;

  @override
  void pause(Object reason) => pauses.add(reason);

  @override
  void resume(Object reason) => pauses.remove(reason);
}

var _micros = 0;

/// A chat line of [room].
DanmakuChat chatLine(String user, String text, {String room = 'douyu:1', int session = 1, bool local = false}) =>
    DanmakuChat(room: room, session: session, receivedAt: ++_micros, userName: user, text: text, isLocal: local);

/// A gift line of [room].
DanmakuGift giftLine(String user, String gift, {int count = 1, String room = 'douyu:1'}) =>
    DanmakuGift(room: room, session: 1, receivedAt: ++_micros, userName: user, giftName: gift, count: count);

/// A super chat of room douyu:1 ending at [end].
DanmakuSuperChat superChat(String id, String user, String text, {required DateTime end, int price = 30}) =>
    DanmakuSuperChat(
      room: 'douyu:1',
      session: 1,
      receivedAt: ++_micros,
      id: id,
      userName: user,
      text: text,
      price: price,
      startAt: end.subtract(const Duration(minutes: 1)),
      endAt: end,
    );

/// A batch of chat lines (also offered for the screen).
DanmakuBatch batchOf(
  List<DanmakuChat> chats, {
  List<DanmakuGift> gifts = const [],
  List<DanmakuSuperChat> superChats = const [],
  Map<AudienceKind, int> online = const {},
  List<DanmakuSystem> system = const [],
}) => DanmakuBatch(
  room: 'douyu:1',
  session: 1,
  list: chats,
  screen: chats,
  gifts: gifts,
  superChats: superChats,
  online: online,
  system: system,
);

/// A live Douyu room 1.
RoomDetail liveRoom({String id = '1', LiveState state = LiveState.live}) => RoomDetail(
  card: RoomCard(ref: RoomRef('douyu', id), title: '标题$id', anchorName: '主播$id', state: state),
  link: Uri.parse('https://www.douyu.com/$id'),
);
