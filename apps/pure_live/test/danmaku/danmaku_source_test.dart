import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';

/// A platform without a chat connector: the worker answers with one
/// `unsupported` notice and never touches the network.
RoomDetail _noChatRoom(String id) => RoomDetail(
  card: RoomCard(ref: RoomRef('iptv', id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.test/$id'),
);

void main() {
  test('ADR 0019: one worker isolate for every room; batches come back; dispose stops it', () async {
    var spawns = 0;
    final source = WorkerDanmakuSource(() {
      spawns++;
      return DanmakuWorker.spawn();
    });
    final first = await source.open(
      _noChatRoom('1'),
      settings: const DanmakuFilterSettings(),
      budget: DanmakuScreenBudget.room,
    );
    final batch = await first.batches.first.timeout(const Duration(seconds: 20));
    expect(batch.room, 'iptv:1');
    expect(batch.system.single.status, DanmakuStatus.unsupported);

    final second = await source.open(
      _noChatRoom('2'),
      settings: const DanmakuFilterSettings(),
      budget: DanmakuScreenBudget.none,
    );
    expect(spawns, 1, reason: 'the second room reuses the worker');
    await first.close();
    await second.close();

    await source.dispose();
    expect(
      () => source.open(_noChatRoom('3'), settings: const DanmakuFilterSettings(), budget: DanmakuScreenBudget.room),
      throwsStateError,
    );
  });
}
