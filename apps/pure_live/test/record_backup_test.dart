import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/recording.dart';

RecordManager _manager({bool polling = false}) => RecordManager(
  rooms: SiteRecordRooms((_) => null),
  store: MemoryRecordTaskStore(),
  root: '/rec',
  files: MemoryRecordFiles(),
  settings: RecordSettings(polling: polling),
);

void main() {
  test('F-BAK-01: recording tasks travel in a full backup and come back monitored', () async {
    final source = _manager();
    final target = _manager(polling: true);
    final sourceStore = await LiveStore.inMemory();
    final targetStore = await LiveStore.inMemory();
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
      await sourceStore.close();
      await targetStore.close();
    });
    await source.init();
    await target.init();
    await source.importTasks([
      RecordTask(
        room: RoomRef('douyu', '9999'),
        createdAt: DateTime.utc(2026, 9),
        state: RecordState.stopped,
        stopCause: StopCause.user,
        snapshot: const RecordRoomSnapshot(anchorName: '甲', title: '标题'),
        quality: RecordQuality.superHd,
      ),
      RecordTask(
        room: RoomRef('huya', '998'),
        createdAt: DateTime.utc(2026, 9, 2),
        state: RecordState.stopped,
        stopCause: StopCause.pollingOff,
        autoReconnect: false,
      ),
    ]);
    await target.importTasks([
      RecordTask(room: RoomRef('bilibili', '1'), createdAt: DateTime.utc(2026), state: RecordState.completed),
    ]);

    final document = await BackupService(
      sourceStore,
      recordTasks: RecordTaskBackupAdapter(() => source),
    ).export(now: DateTime.utc(2026, 9, 28));
    final items = (document['sections']! as Map<String, Object?>)['recordTasks']! as List<Object?>;
    expect(items, hasLength(2));
    expect(jsonEncode(items), isNot(contains('/rec')), reason: 'no file paths or sessions');
    expect((items.first! as Map)['quality'], 'superHigh');
    expect([for (final item in items) (item! as Map)['monitor']], [false, true]);

    final report = await BackupService(
      targetStore,
      recordTasks: RecordTaskBackupAdapter(() => target),
    ).restore(jsonDecode(jsonEncode(document)));
    expect(report.counts['recordTasks']!.written, 2);
    expect(target.tasks.map((task) => task.key), ['douyu:9999', 'huya:998'], reason: 'the local idle task is replaced');
    final douyu = target.task('douyu:9999')!;
    expect(douyu.state, RecordState.stopped);
    expect(douyu.stopCause, StopCause.user);
    expect(douyu.quality, RecordQuality.superHd);
    expect(douyu.snapshot.anchorName, '甲');
    final huya = target.task('huya:998')!;
    expect(huya.state, RecordState.waitingLive, reason: 'monitored and polling is on');
    expect(huya.autoReconnect, isFalse);
  });
}
