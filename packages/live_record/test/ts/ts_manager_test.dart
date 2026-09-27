import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_live.dart';
import '../support/ts_live.dart';

void main() {
  test('an IPTV-style line: recorded through the opener, cut once, stopped, remuxed to MP4 (§8, §10)', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final cdn = FakeTsCdn();
      final rooms = FakeRooms(lines: const ['udpxy'])..formats['udpxy'] = StreamFormat.other;
      final manager = RecordManager(
        rooms: rooms,
        store: MemoryRecordTaskStore(),
        root: '/rec',
        files: files,
        opener: RecordOpener(flv: (_) => FakeCdn().open, stream: (_) => cdn.open),
        remuxer: Mp4Remuxer(files: files),
      );
      unawaited(manager.init());
      async.flushMicrotasks();
      unawaited(manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 15));
      expect(manager.task('douyu:9999')!.state, RecordState.recording);
      cdn.cutAll();
      async.elapse(const Duration(seconds: 15));
      final recording = manager.task('douyu:9999')!;
      expect(recording.state, RecordState.recording);
      expect(recording.session!.connections, 2);
      expect(recording.session!.gaps, 1);

      unawaited(manager.stop('douyu:9999'));
      async.elapse(const Duration(seconds: 5));
      final task = manager.task('douyu:9999')!;
      expect(task.state, RecordState.stopped);
      expect(task.failure, isNull);
      expect(task.session!.segments.single, endsWith('_001.ts'));
      expect(task.session!.outputs.single, endsWith('_001.mp4'));
      expect(files.paths, contains(task.session!.outputs.single));
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
