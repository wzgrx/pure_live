import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:pure_live_app/core/recording.dart';

RoomDetail _detail(String roomId, {LiveState state = LiveState.live}) => RoomDetail(
  card: RoomCard(ref: RoomRef('douyu', roomId), title: '标题', anchorName: '主播$roomId', state: state),
  link: Uri.parse('https://www.douyu.com/$roomId'),
);

/// Rooms whose strict check waits for [gate], then reports the room offline.
final class _Rooms implements RecordRooms {
  Completer<void> gate = Completer<void>();

  @override
  Future<RoomDetail> detail(RoomRef room) async {
    await gate.future;
    return _detail(room.roomId, state: LiveState.offline);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => throw UnimplementedError();
}

final class _Channel implements RecordServiceChannel {
  new(this.store);

  final MemoryRecordTaskStore store;
  final calls = <String>[];
  Future<void> Function()? timeout;

  /// The stored task states when the service was stopped.
  Map<String, Object?>? storedAtStop;

  @override
  Future<bool> update(RecordNotice notice) async {
    calls.add('${notice.title} / ${notice.text}');
    return true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    storedAtStop = {for (final MapEntry(:key, :value) in store.stored.entries) key: value['state']};
  }

  @override
  void handleTimeout(Future<void> Function()? handler) => timeout = handler;
}

void main() {
  RecordTask task(String roomId, RecordState state, {String anchor = ''}) => RecordTask(
    room: RoomRef('douyu', roomId),
    createdAt: DateTime(2026),
    state: state,
    snapshot: RecordRoomSnapshot(anchorName: anchor),
  );

  test('F-REC-06: the notification counts recordings and names the streamers', () {
    expect(recordServiceNotice([task('1', RecordState.completed), task('2', RecordState.waitingLive)]), isNull);
    expect(recordServiceNotice([task('1', RecordState.recording, anchor: '甲'), task('2', RecordState.queued)]), (
      title: '正在录制 2 个直播间',
      text: '甲、2',
    ));
    expect(
      recordServiceNotice([
        for (var i = 1; i <= 4; i++) task('$i', RecordState.recording, anchor: '主播$i'),
        task('9', RecordState.finalizing),
      ]),
      (title: '正在录制 4 个直播间', text: '主播1、主播2、主播3 等；1 个正在收尾'),
    );
    expect(recordServiceNotice([task('1', RecordState.finalizing)])?.title, '正在处理录制文件');
  });

  test('F-REC-06: the service runs while a task holds a session and stops after its state is stored', () {
    fakeAsync((async) {
      final rooms = _Rooms();
      final store = MemoryRecordTaskStore();
      final manager = RecordManager(rooms: rooms, store: store, root: '/rec', files: MemoryRecordFiles());
      final channel = _Channel(store);
      unawaited(manager.init());
      async.flushMicrotasks();
      final keepAlive = RecordKeepAlive(manager, channel);
      expect(channel.calls, isEmpty);

      unawaited(manager.add(_detail('1')));
      async.elapse(const Duration(seconds: 1));
      expect(channel.calls, ['正在录制 1 个直播间 / 主播1']);

      rooms.gate.complete();
      async.elapse(const Duration(seconds: 5));
      expect(manager.task('douyu:1')!.state, RecordState.completed);
      expect(channel.calls.last, 'stop');
      expect(channel.storedAtStop, {'douyu:1': 'completed'}, reason: 'stored before the keep-alive goes (§13)');
      expect(channel.calls.where((call) => call == 'stop'), hasLength(1));

      unawaited(keepAlive.dispose());
      unawaited(manager.dispose());
      async.elapse(const Duration(seconds: 15));
    });
  });

  test('F-REC-06: a system timeout finishes the tasks, stops the service and waits for the app in front', () {
    fakeAsync((async) {
      final rooms = _Rooms();
      final store = MemoryRecordTaskStore();
      final manager = RecordManager(rooms: rooms, store: store, root: '/rec', files: MemoryRecordFiles());
      final channel = _Channel(store);
      unawaited(manager.init());
      async.flushMicrotasks();
      final keepAlive = RecordKeepAlive(manager, channel);
      unawaited(manager.add(_detail('1')));
      async.elapse(const Duration(seconds: 1));
      expect(channel.calls, hasLength(1));

      unawaited(channel.timeout!());
      async.elapse(const Duration(seconds: 1));
      final failed = manager.task('douyu:1')!;
      expect(failed.state, RecordState.failed);
      expect(failed.failure?.kind, RecordErrorKind.backgroundInterrupted);
      expect(channel.calls.last, 'stop');
      expect(keepAlive.blocked, isTrue);

      // The user starts it again in the background: no service until the app is in front.
      rooms.gate = Completer<void>();
      unawaited(manager.start('douyu:1'));
      async.elapse(const Duration(seconds: 1));
      expect(manager.task('douyu:1')!.state.active, isTrue);
      expect(channel.calls.last, 'stop');
      keepAlive.resumed();
      async.flushMicrotasks();
      expect(channel.calls.last, '正在录制 1 个直播间 / 主播1');

      unawaited(keepAlive.dispose());
      unawaited(manager.dispose());
      async.elapse(const Duration(seconds: 15));
    });
  });
}
