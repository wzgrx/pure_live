import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/cast/cast_controller.dart';

import '../danmaku/fake_danmaku.dart' show liveRoom;
import 'fake_cast.dart';

final CastDevice _tv = castDevice('客厅电视', id: 'uuid:tv');
final CastDevice _box = castDevice('卧室盒子', id: 'uuid:box', host: '192.168.1.21');
final CastMedia _media = CastMedia(url: upstreamUrl, title: '主播1 - 标题1');
final RoomRef _room = RoomRef('douyu', '1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('castSourceOf', () {
    final detail = liveRoom();

    test('the upstream URL of the line, titled "streamer - title", MIME by format and path', () {
      final flv = castSourceOf(detail, playingState());
      expect(flv.media, CastMedia(url: upstreamUrl, title: '主播1 - 标题1'));
      expect(flv.problem, isNull);
      expect(flv.needsHeaders, isFalse);
      expect(flv.expires, isFalse);
      final hls = castSourceOf(
        detail,
        playingState(url: Uri.parse('https://cdn.example.com/live/1'), format: StreamFormat.hls),
      );
      expect(hls.media!.mimeType, CastMime.hls);
      final ts = castSourceOf(detail, playingState(url: Uri.parse('http://192.168.1.1:4022/udp/239.1.1.1.ts')));
      expect(ts.media!.mimeType, CastMime.mpegTs, reason: 'IPTV TS lines are marked flv (ADR 0024)');
    });

    test('falls back to the committed line; no line at all is a problem', () {
      const quality = Quality(id: 'hd', label: '原画', rank: 3);
      final line = StreamLine(url: upstreamUrl, format: StreamFormat.flv, lineId: 'ws', requested: quality);
      final committed = PlaybackState(
        commit: SourceCommit(
          session: 1,
          intentRevision: 1,
          roomKey: 'douyu:1',
          quality: quality,
          line: line,
          audioOnly: false,
        ),
      );
      expect(castSourceOf(detail, committed).media!.url, upstreamUrl);
      expect(castSourceOf(detail, const PlaybackState()).problem, '还没有拿到直播地址，等画面出来后再投屏');
    });

    test('rejects other schemes, user info and local hosts', () {
      String? problem(String url) => castSourceOf(detail, playingState(url: Uri.parse(url))).problem;
      expect(problem('rtmp://live.example.com/app/stream'), '当前线路不是 http(s) 地址，电视打不开');
      expect(problem('rtsp://192.168.1.2/ch1'), '当前线路不是 http(s) 地址，电视打不开');
      expect(problem('http://user:pass@cdn.example.com/1.flv'), '当前线路的地址无效');
      for (final local in [
        'http://127.0.0.1:38211/relay/7f3a',
        'http://localhost:8080/1.flv',
        'http://[::1]:8080/1.flv',
        'http://0.0.0.0:8080/1.flv',
      ]) {
        expect(problem(local), '当前线路是本机地址，电视访问不到', reason: local);
      }
      expect(problem('http://192.168.1.1:4022/udp/239.1.1.1'), isNull, reason: 'a LAN proxy is reachable');
    });

    test('headers and leases are flagged', () {
      final source = castSourceOf(
        detail,
        playingState(
          headers: const {'referer': 'https://www.huya.com/'},
          lease: Lease(refreshAt: DateTime(2026, 9, 28, 12), cutsConnection: true),
        ),
      );
      expect(source.media, isNotNull);
      expect(source.needsHeaders, isTrue);
      expect(source.expires, isTrue);
    });
  });

  group('CastNotifier', () {
    late FakeRenderers renderers;
    late ProviderContainer container;

    setUp(() {
      renderers = FakeRenderers();
      container = ProviderContainer(overrides: [castRendererProvider.overrideWithValue(renderers.call)]);
      addTearDown(container.dispose);
    });

    CastNotifier notifier() => container.read(castProvider.notifier);

    test('casts, then a tap while connecting joins the same sequence', () async {
      final first = notifier().cast(_tv, _media, room: _room, roomTitle: '主播1');
      final second = notifier().cast(_box, _media, room: _room, roomTitle: '主播1');
      expect(container.read(castProvider).phase, CastPhase.connecting);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(renderers.log, ['set 客厅电视 $upstreamUrl video/x-flv', 'play 客厅电视']);
      final state = container.read(castProvider);
      expect(state.casting, isTrue);
      expect(state.device, _tv);
      expect(state.room, _room);
      expect(state.tvState, TransportState.playing);
    });

    test('recasting to the same renderer does not stop it first', () async {
      await notifier().cast(_tv, _media, room: _room, roomTitle: '主播1');
      await notifier().cast(_tv, _media, room: _room, roomTitle: '主播1');
      expect(renderers.log.where((line) => line.startsWith('stop')), isEmpty);
    });

    test('a failure is kept with its device; nothing is left to stop', () async {
      renderers.failures['play 客厅电视'] = const UpnpActionFailure('Play', 704);
      expect(await notifier().cast(_tv, _media, room: _room, roomTitle: '主播1'), isFalse);
      final state = container.read(castProvider);
      expect(state.phase, CastPhase.failed);
      expect(state.device, _tv);
      expect(castFailureText(state.failure!), '设备不支持这种直播流格式，换一条线路试试');
      expect(await notifier().stop(), isTrue);
      expect(renderers.log.where((line) => line.startsWith('stop')), isEmpty);
    });

    test('stop reports a renderer that did not confirm, and forgets the cast anyway', () async {
      await notifier().cast(_tv, _media, room: _room, roomTitle: '主播1');
      renderers.failures['stop 客厅电视'] = const CastNetworkFailure('reset');
      expect(await notifier().stop(), isFalse);
      expect(container.read(castProvider).phase, CastPhase.idle);
    });

    test('stop waits for a cast in progress', () async {
      unawaited(notifier().cast(_tv, _media, room: _room, roomTitle: '主播1'));
      expect(await notifier().stop(), isTrue);
      expect(renderers.log, ['set 客厅电视 $upstreamUrl video/x-flv', 'play 客厅电视', 'stop 客厅电视']);
      expect(container.read(castProvider).casting, isFalse);
    });

    test('refreshStatus asks the renderer; an error makes the state unknown', () async {
      await notifier().refreshStatus();
      expect(renderers.log, isEmpty, reason: 'nothing cast');
      await notifier().cast(_tv, _media, room: _room, roomTitle: '主播1');
      await notifier().refreshStatus();
      expect(container.read(castProvider).tvState, TransportState.pausedPlayback);
      expect(container.read(castProvider).casting, isTrue);
      renderers.failures['info 客厅电视'] = const CastTimeoutFailure(Duration(seconds: 6));
      await notifier().refreshStatus();
      expect(container.read(castProvider).tvState, isNull);
      expect(container.read(castProvider).casting, isTrue);
    });
  });

  test('failure copy', () {
    expect(castFailureText(const CastTimeoutFailure(Duration(seconds: 6))), contains('同一个 Wi-Fi'));
    expect(castFailureText(const UpnpActionFailure('SetAVTransportURI', 705)), '设备正忙，稍后再试');
    expect(castFailureText(const UpnpActionFailure('SetAVTransportURI', 716)), '设备打不开这个直播地址，换一条线路试试');
    expect(castFailureText(const UpnpActionFailure('Play', 501)), '设备拒绝了投屏（错误码 501）');
    expect(castFailureText(const CastHttpFailure(404)), '设备返回了错误（HTTP 404）');
    expect(castFailureText(const CastProtocolFailure()), '设备的回应无法识别');
    expect(castFailureText(StateError('x')), '投屏失败');
    expect(tvStateText(TransportState.noMediaPresent), '电视已停止播放');
    expect(tvStateText(TransportState.unknown), isNull);
  });

  group('multicast lock', () {
    const channel = MethodChannel('purelive/cast-test');
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
    });

    test('overlapping holds acquire and release once', () async {
      final lock = MulticastLock(channel: channel, enabled: true);
      await lock.acquire();
      await lock.acquire();
      await lock.release();
      expect(calls, ['acquire']);
      await lock.release();
      await lock.release();
      expect(calls, ['acquire', 'release']);
    });

    test('off the platform nothing is called', () async {
      final lock = MulticastLock(channel: channel, enabled: false);
      await lock.acquire();
      await lock.release();
      expect(calls, isEmpty);
    });

    test('a missing channel is ignored', () async {
      final lock = MulticastLock(channel: const MethodChannel('purelive/cast-missing'), enabled: true);
      await lock.acquire();
      await lock.release();
    });

    test('a search holds the lock until it ends or is cancelled', () async {
      final lock = MulticastLock(channel: channel, enabled: true);
      final devices = await searchWithLock(lock, () => Stream.fromIterable([_tv, _box])).toList();
      expect(devices, [_tv, _box]);
      expect(calls, ['acquire', 'release']);

      final endless = StreamController<CastDevice>();
      final subscription = searchWithLock(lock, () => endless.stream).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['acquire', 'release', 'acquire']);
      await subscription.cancel();
      expect(calls, ['acquire', 'release', 'acquire', 'release']);
      await endless.close();
    });
  });
}
