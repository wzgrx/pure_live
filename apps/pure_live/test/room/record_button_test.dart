import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/features/room/record_button.dart';

import '../danmaku/fake_danmaku.dart';
import '../fakes.dart';

RecordTask _task(RecordState state) => RecordTask(room: RoomRef('douyu', '1'), createdAt: DateTime(2026), state: state);

void main() {
  test('F-ROOM-14: the menu follows the task state', () {
    expect(roomRecordActions(null, live: true), [RoomRecordAction.recordNow, RoomRecordAction.openCenter]);
    expect(roomRecordActions(null, live: false), [RoomRecordAction.watch, RoomRecordAction.openCenter]);
    expect(roomRecordActions(_task(RecordState.recording), live: true), [
      RoomRecordAction.stop,
      RoomRecordAction.openCenter,
    ]);
    expect(roomRecordActions(_task(RecordState.waitingLive), live: false), [
      RoomRecordAction.checkNow,
      RoomRecordAction.remove,
      RoomRecordAction.openCenter,
    ]);
    expect(roomRecordActions(_task(RecordState.finalizing), live: true), [
      RoomRecordAction.openCenter,
    ], reason: 'finishing files: nothing to stop');
    expect(roomRecordActions(_task(RecordState.completed), live: true), [
      RoomRecordAction.recordNow,
      RoomRecordAction.remove,
      RoomRecordAction.openCenter,
    ]);
    expect(roomRecordActions(_task(RecordState.stopped), live: false), [
      RoomRecordAction.watch,
      RoomRecordAction.remove,
      RoomRecordAction.openCenter,
    ]);
  });

  Future<void> pumpButton(WidgetTester tester, RecordTask? task, {LiveState state = LiveState.live}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordTaskProvider.overrideWith((ref, key) => Stream.value(task)),
            recordManagerProvider.overrideWithValue(fakeRecordManager()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: RoomRecordButton(detail: liveRoom(state: state)),
              ),
            ),
          ),
        ),
      );

  testWidgets('a recording room shows its state and offers stop', (tester) async {
    await pumpButton(tester, _task(RecordState.recording));
    await tester.pump();
    expect(find.text('录制中'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-record')));
    await tester.pump();
    expect(find.text('停止录制'), findsOneWidget);
    expect(find.text('录制中心'), findsOneWidget);
    expect(find.text('立即录制'), findsNothing);
  });

  testWidgets('an offline room without a task offers to record when it goes live', (tester) async {
    await pumpButton(tester, null, state: LiveState.offline);
    await tester.pump();
    expect(find.text('录制'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-record')));
    await tester.pump();
    expect(find.text('开播时自动录制'), findsOneWidget);
    expect(find.text('立即录制'), findsNothing);
  });

  testWidgets('a watched room offers a check and removal of the watch', (tester) async {
    await pumpButton(tester, _task(RecordState.waitingLive), state: LiveState.offline);
    await tester.pump();
    expect(find.text('等待开播'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-record')));
    await tester.pump();
    expect(find.text('立即检查开播'), findsOneWidget);
    expect(find.text('移除监控'), findsOneWidget);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('stopping a recording asks first; cancel keeps it recording (F-REC-02)', (tester) async {
    await pumpButton(tester, _task(RecordState.recording));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-record')));
    await settle(tester);
    await tester.tap(find.text('停止录制'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('正在停止录制，已录的文件会保留'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('room-record')));
    await settle(tester);
    await tester.tap(find.text('停止录制'));
    await settle(tester);
    await tester.tap(find.text('停止'));
    await settle(tester);
    expect(find.text('正在停止录制，已录的文件会保留'), findsOneWidget);
  });

  testWidgets('removing a watch asks first (F-REC-02)', (tester) async {
    await pumpButton(tester, _task(RecordState.waitingLive), state: LiveState.offline);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-record')));
    await settle(tester);
    await tester.tap(find.text('移除监控'));
    await settle(tester);
    expect(find.text('不再等待“1”开播？已录的文件会保留。'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await settle(tester);
    expect(find.text('已移除录制任务，已录的文件会保留'), findsOneWidget);
  });
}
