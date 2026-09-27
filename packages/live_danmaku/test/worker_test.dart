import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Runs inside the worker isolate: every handshake gets a socket that
/// replays 30 Douyu chat packets, then stays open.
DanmakuTransport _replay() => _ReplayTransport();

final class _ReplayTransport implements DanmakuTransport {
  @override
  final FakeHttp http = FakeHttp();

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    required String site,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = FakeSocket();
    if (site == 'bilibili') {
      Timer(const Duration(milliseconds: 20), () {
        socket
          ..receive(BilibiliProtocol.packet(BilibiliProtocol.opAuthReply, utf8.encode('{"code":0}')))
          ..receive(
            BilibiliProtocol.packet(
              BilibiliProtocol.opNotice,
              utf8.encode(
                jsonEncode({
                  'cmd': 'DANMU_MSG',
                  'info': [
                    [0, 1, 25, 0, 0, 7],
                    'from bilibili',
                    [1, 'viewer'],
                  ],
                }),
              ),
            ),
          );
      });
      return socket;
    }
    Timer(const Duration(milliseconds: 20), () {
      for (var i = 0; i < 30; i++) {
        socket.receive(DouyuProtocol.packet('type@=chatmsg/rid@=1/cid@=c$i/nn@=n$i/txt@=message $i/', type: 690));
      }
    });
    return socket;
  }
}

final class _Credentials implements DanmakuCredentials {
  final List<String> rooms = [];

  @override
  Future<BilibiliDanmakuInfo> bilibili(RoomDetail room) async {
    rooms.add(room.ref.key);
    return const BilibiliDanmakuInfo(roomId: 5050, uid: 0, token: 't', servers: [], buvid: '', headers: {});
  }

  @override
  Future<String?> cookie(String platform) async => null;
}

RoomDetail _room(String platform, String id, Map<String, String> keys) => RoomDetail(
  card: RoomCard(ref: RoomRef(platform, id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.test/$id'),
  danmakuKeys: keys,
);

void main() {
  test('CONN-1: decoding, filtering and batching run in the worker; only batches come back', () async {
    final worker = await DanmakuWorker.spawn(transport: _replay);
    addTearDown(worker.dispose);
    final session = worker.open(
      _room('douyu', '1', {'rid': '1'}),
      settings: const DanmakuFilterSettings(blockedWords: ['MESSAGE 7']),
    );
    final batches = <DanmakuBatch>[];
    final received = Completer<void>();
    final subscription = session.batches.listen((batch) {
      batches.add(batch);
      if (batches.expand((batch) => batch.list).length >= 29 && !received.isCompleted) received.complete();
    });
    await received.future.timeout(const Duration(seconds: 10));
    final texts = batches.expand((batch) => batch.list).map((chat) => chat.text).toList();
    expect(texts, hasLength(29));
    expect(texts, isNot(contains('message 7')));
    expect(batches.every((batch) => batch.session == session.token && batch.room == 'douyu:1'), isTrue);
    final statuses = batches.expand((batch) => batch.system).map((notice) => notice.status);
    expect(statuses, containsAllInOrder([DanmakuStatus.connecting, DanmakuStatus.connected]));
    await session.close();
    await subscription.cancel();
  });

  test('credentials are answered on the calling isolate', () async {
    final credentials = _Credentials();
    final worker = await DanmakuWorker.spawn(transport: _replay, credentials: credentials);
    addTearDown(worker.dispose);
    final session = worker.open(_room('bilibili', '5050', {'roomId': '5050'}));
    final batch = await session.batches
        .firstWhere((batch) => batch.list.isNotEmpty)
        .timeout(const Duration(seconds: 10));
    expect(batch.list.single.text, 'from bilibili');
    expect(credentials.rooms, ['bilibili:5050']);
    await session.close();
  });

  test('a platform without a connector reports unsupported once', () async {
    final worker = await DanmakuWorker.spawn(transport: _replay);
    addTearDown(worker.dispose);
    final session = worker.open(_room('cc', '1', const {}));
    final batch = await session.batches.first.timeout(const Duration(seconds: 10));
    expect(batch.system.single.status, DanmakuStatus.unsupported);
    await session.close();
  });

  test('CONN-4: sessions are isolated by token; settings update without reconnecting', () async {
    final worker = await DanmakuWorker.spawn(transport: _replay);
    addTearDown(worker.dispose);
    final first = worker.open(_room('douyu', '1', {'rid': '1'}));
    final second = worker.open(_room('douyu', '1', {'rid': '1'}));
    expect(second.token, isNot(first.token));
    final firstBatches = <DanmakuBatch>[];
    first.batches.listen(firstBatches.add);
    await first.close();
    final seen = await second.batches.firstWhere((batch) => batch.list.isNotEmpty).timeout(const Duration(seconds: 10));
    expect(seen.session, second.token);
    expect(firstBatches.every((batch) => batch.session == first.token), isTrue);
    second.update(settings: const DanmakuFilterSettings(hideSuspectedBots: true), budget: DanmakuScreenBudget.pip);
    await second.close();
  });
}
