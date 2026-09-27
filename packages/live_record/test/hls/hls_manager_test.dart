import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';
import '../support/fake_live.dart';

void main() {
  test('an HLS room: recorded, stopped, remuxed to MP4 by Mp4Remuxer; the HLS client is closed', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final server = FakeHlsServer();
      final rooms = FakeRooms(lines: const ['hw'])..formats['hw'] = StreamFormat.hls;
      final manager = RecordManager(
        rooms: rooms,
        store: MemoryRecordTaskStore(),
        root: '/rec',
        files: files,
        opener: RecordOpener(flv: (_) => FakeCdn().open, hls: (_) => server),
        remuxer: Mp4Remuxer(files: files),
      );
      unawaited(manager.init());
      async.flushMicrotasks();
      unawaited(manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 20));
      final recording = manager.task('douyu:9999')!;
      expect(recording.state, RecordState.recording);
      expect(recording.session!.bytes, greaterThan(0));
      expect(recording.session!.media, greaterThanOrEqualTo(const Duration(seconds: 16)));

      unawaited(manager.stop('douyu:9999'));
      async.elapse(const Duration(seconds: 5));
      final task = manager.task('douyu:9999')!;
      expect(task.state, RecordState.stopped);
      expect(task.failure, isNull);
      expect(task.session!.segments.single, endsWith('_001.ts'));
      expect(task.session!.outputs.single, endsWith('_001.mp4'));
      expect(files.paths, contains(task.session!.outputs.single));
      expect(files.paths.where((path) => path.endsWith('.ts')), isEmpty, reason: 'the source goes after the remux');
      expect(server.closed, isTrue);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('crash recovery finishes a .ts.part and remuxes it at the next launch (§14.1)', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now());
      final part = '${layout.segment(1, extension: 'ts')}.part';
      final server = FakeHlsServer();
      files.put(part, [
        for (var seq = 0; seq < 4; seq++) ...server.segmentBytes(seq),
        ...server.segmentBytes(4).sublist(0, 600),
      ]);
      final store = MemoryRecordTaskStore([
        RecordTask(
          room: RoomRef('douyu', '9999'),
          createdAt: clock.now(),
          state: RecordState.recording,
          session: RecordSessionInfo(layout: layout),
        ),
      ]);
      final manager = RecordManager(
        rooms: FakeRooms(),
        store: store,
        root: '/rec',
        files: files,
        opener: RecordOpener(flv: (_) => FakeCdn().open),
        remuxer: Mp4Remuxer(files: files),
      );
      unawaited(manager.init());
      async.elapse(const Duration(seconds: 2));
      final task = manager.task('douyu:9999')!;
      expect(task.state, RecordState.stopped);
      expect(task.session!.outputs.single, endsWith('_001.mp4'));
      expect(files.paths.where((path) => path.endsWith('.part')), isEmpty);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
