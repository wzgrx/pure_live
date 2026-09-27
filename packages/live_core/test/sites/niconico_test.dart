// niconico live: parsing, the watching seat and the lease-held adapter over
// the recorded samples (spec/sites/niconico.md). No legacy expected values (ADR 0016).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// The recorded seat conversation (fixtures/niconico/seat/S04-seat).
List<Map<String, dynamic>> _seatFrames() => [
  for (final line in File('../../fixtures/niconico/seat/S04-seat/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
];

/// A socket that replays the recorded server messages after the client's
/// `startWatching`.
final class _ReplaySocket implements NiconicoSocket {
  new(this._incoming);

  final List<String> _incoming;
  final StreamController<String> _controller = StreamController<String>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String text) {
    if (closed) return;
    sent.add(text);
    if (sent.length == 1) {
      scheduleMicrotask(() {
        for (final message in _incoming) {
          if (!_controller.isClosed) _controller.add(message);
        }
      });
    }
  }

  /// Server-side close.
  void drop() => unawaited(_controller.close());

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

List<String> _serverMessages({bool withPing = false}) => [
  for (final frame in _seatFrames())
    if (frame['dir'] == 'in')
      if (withPing || !(frame['text'] as String).contains('"ping"')) frame['text'] as String,
];

NiconicoSite _site(List<String> samples, {required List<_ReplaySocket> sockets, List<Uri>? urls}) => NiconicoSite(
  ReplayHttp.fixtures('../../fixtures/niconico', samples),
  connect: (url, headers) async {
    urls?.add(url);
    return sockets.removeAt(0);
  },
);

void main() {
  group('§2/§3 lists', () {
    test('S01 recent common: user rooms, cumulative watch count, pages by totalCount', () {
      final body = Fixture.load('niconico', 'S01-recent-common-p1').body;
      final root = jsonDecode(body) as Map<String, dynamic>;
      final rows = (root['data'] as List).cast<Map<String, dynamic>>();
      final page = NiconicoParse.recent(body, page: 1);
      expect(page.items.first.ref.roomId, 'user/${(rows.first['programProvider'] as Map)['id']}');
      expect(page.items.first.audience.cumulative, (rows.first['statistics'] as Map)['watchCount']);
      expect(page.items.every((c) => c.state == LiveState.live), isTrue);
      expect(page.next, const PageCursor('2'), reason: '70 < totalCount ${(root['meta'] as Map)['totalCount']}');
      final last = NiconicoParse.recent(Fixture.load('niconico', 'S01-recent-req-p1').body, page: 1);
      expect(last.isLast, isTrue);
    });

    test('S01 face tab: a channel program becomes the channel room', () {
      final body = Fixture.load('niconico', 'S01-recent-face-p1').body;
      final rows = ((jsonDecode(body) as Map)['data'] as List).cast<Map<String, dynamic>>();
      final channel = rows.where((r) => r['providerType'] == 'channel').toList();
      final page = NiconicoParse.recent(body, page: 1);
      for (final row in channel) {
        expect(page.items.map((c) => c.ref.roomId), contains((row['socialGroup'] as Map)['id']));
      }
    });

    test('S02 search: on-air programs of users', () {
      final page = NiconicoParse.search(Fixture.load('niconico', 'S02-search').body, page: 1);
      expect(page.items, isNotEmpty);
      expect(page.items.every((c) => c.ref.roomId.startsWith('user/') || c.ref.roomId.startsWith('lv')), isTrue);
    });
  });

  group('§4 watch pages', () {
    test('S03 a user room shows the live program with the seat socket', () {
      final watch = NiconicoParse.watch(Fixture.load('niconico', 'S03-watch-user-live').body, roomId: 'user/144846457');
      expect(watch.detail.state, LiveState.live);
      expect(watch.programId, 'lv351482868');
      expect(watch.detail.ref.roomId, 'user/144846457');
      expect(watch.detail.danmakuKeys, {'programId': 'lv351482868'});
      expect(watch.denied, isNull);
      expect(watch.webSocket!.host, 'a.live2.nicovideo.jp');
      expect(watch.webSocket!.queryParameters['frontend_id'], '9');
      expect(watch.detail.card.audience.cumulative, isNotNull);
    });

    test('S03 ended user room, channel room (paid with trial), missing program', () {
      final ended = NiconicoParse.watch(
        Fixture.load('niconico', 'S03-watch-user-ended').body,
        roomId: 'user/138383030',
      );
      expect(ended.detail.state, LiveState.offline);
      expect(ended.webSocket, isNull);
      final channel = NiconicoParse.watch(Fixture.load('niconico', 'S03-watch-channel').body, roomId: 'ch2640864');
      expect(channel.detail.ref.roomId, 'ch2640864');
      expect(channel.denied, isNull, reason: 'trial stream: canWatch true');
      expect(Fixture.load('niconico', 'S03-watch-notfound').status, 404);
    });
  });

  group('§6 seat', () {
    test('S04 the recorded seat yields the grant; pings get pong and keepSeat', () async {
      final socket = _ReplaySocket(_serverMessages(withPing: true));
      final seat = await NiconicoSeat.open(Uri.parse('wss://a.live2.nicovideo.jp/x'), connect: (_, _) async => socket);
      await pumpEventQueue();
      final grant = seat.grant;
      expect(grant.master.path, endsWith('/multivariant/variant.m3u8'));
      expect(grant.qualities, contains('abr'));
      expect(socket.sent.first, contains('"startWatching"'));
      expect(socket.sent, containsAll(['{"type":"pong"}', '{"type":"keepSeat"}']));
      expect(seat.messageServer!.host, 'mpn.live.nicovideo.jp');
      expect(seat.viewers, isNotNull);
      await seat.close();
      expect(socket.closed, isTrue);
    });

    test('§6.3 cookies are path-scoped: each request gets only its own', () async {
      final seat = await NiconicoSeat.open(
        Uri.parse('wss://x.test/'),
        connect: (_, _) async => _ReplaySocket(_serverMessages()),
      );
      final grant = seat.grant;
      final playlist = grant.cookieHeader(grant.master);
      final segment = grant.cookieHeader(
        grant.master.replace(path: grant.master.path.replaceFirst('/hls/playlists/', '/hls/segments/')),
      );
      expect(playlist, contains('CloudFront-Policy='));
      expect(playlist.split('; ').where((c) => c.startsWith('CloudFront-Policy=')), hasLength(1));
      expect(playlist, isNot(equals(segment)));
      expect(grant.netscapeCookies().split('\n'), hasLength(grant.cookies.length));
      expect(grant.netscapeCookies(), contains('\t/hls/keys/'));
      await seat.close();
    });

    test('a disconnect before the grant fails the open', () async {
      final socket = _ReplaySocket(['{"type":"disconnect","data":{"reason":"END_PROGRAM"}}']);
      await expectLater(
        NiconicoSeat.open(Uri.parse('wss://x.test/'), connect: (_, _) async => socket),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('§6.4 adapter and the seat lease', () {
    test('streams opens one seat; a renewal reuses it and extends the lease', () async {
      final socket = _ReplaySocket(_serverMessages());
      final urls = <Uri>[];
      final site = _site(['S03-watch-user-live'], sockets: [socket], urls: urls);
      final detail = await site.detail(RoomRef('niconico', 'user/144846457'));
      final first = await site.streams(detail);
      final line = first.lines.single;
      expect(line.format, StreamFormat.hls);
      expect(line.headers['cookie'], contains('CloudFront-Signature='));
      expect(line.lease!.cutsConnection, isFalse);
      expect(line.lease!.expiresAt!.difference(line.lease!.refreshAt), const Duration(seconds: 90));
      final again = await site.streams(detail);
      expect(again.lines.single.url, line.url, reason: 'the held seat is reused');
      expect(urls, hasLength(1));
      expect(site.cookieFile(line), isNotNull);
      await site.close();
      expect(socket.closed, isTrue);
      expect(site.cookieFile(line), isNull);
    });

    test('an unrenewed seat closes after holdFor', () async {
      final socket = _ReplaySocket(_serverMessages());
      final site = NiconicoSite(
        ReplayHttp.fixtures('../../fixtures/niconico', ['S03-watch-user-live']),
        connect: (_, _) async => socket,
        holdFor: const Duration(milliseconds: 50),
        renewEvery: const Duration(milliseconds: 20),
      );
      final detail = await site.detail(RoomRef('niconico', 'user/144846457'));
      await site.streams(detail);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(socket.closed, isTrue);
    });

    test('offline rooms have no stream', () async {
      final site = _site(['S03-watch-user-ended'], sockets: []);
      final detail = await site.detail(RoomRef('niconico', 'user/138383030'));
      await expectLater(site.streams(detail), throwsA(isA<StreamUnavailable>()));
    });

    test('catalog and search', () async {
      final site = _site(['S01-recent-common-p1', 'S02-search'], sockets: []);
      final areas = (await site.categories()).single.areas;
      expect(areas.map((a) => a.id), ['common', 'try', 'live', 'req', 'face', 'totu', 'vtuber']);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('ゲーム')).items, isNotEmpty);
    });

    test('links: user and channel rooms; a program link becomes its user room', () async {
      final site = _site(['S03-watch-program-live'], sockets: []);
      expect(await site.resolve('user/144846457'), RoomRef('niconico', 'user/144846457'));
      expect(
        await site.resolve('https://live.nicovideo.jp/watch/user/144846457'),
        RoomRef('niconico', 'user/144846457'),
      );
      expect(await site.resolve('https://live.nicovideo.jp/watch/ch2640864'), RoomRef('niconico', 'ch2640864'));
      expect(
        await site.resolve('見て https://live.nicovideo.jp/watch/lv351482868?ref=share'),
        RoomRef('niconico', 'user/144846457'),
      );
      expect(await site.resolve('https://www.nicovideo.jp/watch/sm9'), isNull);
    });
  });
}
