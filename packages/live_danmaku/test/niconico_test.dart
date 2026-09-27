import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'fixture.dart';

final _start = DateTime.utc(2026, 9, 28);

/// The recorded seat conversation of live_core's samples
/// (fixtures/niconico/seat/S04-seat), replayed after `startWatching`.
final class _Seat implements TextSocket {
  new() {
    _incoming = [
      for (final line in File('../../fixtures/niconico/seat/S04-seat/frames.jsonl').readAsLinesSync())
        if (line.trim().isNotEmpty)
          if (jsonDecode(line) case {'dir': 'in', 'text': final String text} when !text.contains('"ping"')) text,
    ];
  }

  late final List<String> _incoming;
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

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

void main() {
  final fixture = DanmakuFixture.load('niconico', 'S07-live');
  final views = [
    for (final f in fixture.incoming)
      if (f.url!.path.startsWith('/api/view/')) f,
  ];
  final segments = {
    for (final f in fixture.incoming)
      if (f.url!.path.startsWith('/data/segment/')) f.url!.path: f,
  };

  group('protocol (§7)', () {
    test('view answers: next only at first, then windows under way, finished windows and next', () {
      final first = NiconicoChatProtocol.view(views.first.bytes);
      expect(first.segments, isEmpty);
      expect(first.next, isNotNull);
      final second = NiconicoChatProtocol.view(views[1].bytes);
      expect(second.segments, hasLength(2));
      expect(second.previous, hasLength(2));
      expect(second.segments.first.until.difference(second.segments.first.from), const Duration(seconds: 16));
      expect(second.next, greaterThan(first.next!));
      expect(second.segments.every((s) => segments.containsKey(s.uri.path)), isTrue);
    });

    test('window messages: chat lines with ids and times; viewer counts', () {
      final events = [
        for (final frame in segments.values)
          ...NiconicoChatProtocol.messages(frame.bytes, context: fixture.context(frame)).map((e) => e.event),
      ];
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, hasLength(15));
      expect(chats.every((c) => c.id!.startsWith('niconico:') && c.text.isNotEmpty && c.sentAt != null), isTrue);
      expect(events.whereType<DanmakuOnline>().every((e) => e.audience == AudienceKind.online && e.value > 0), isTrue);
    });

    test('length prefixes are checked', () {
      expect(() => NiconicoChatProtocol.delimited([5, 1, 2]), throwsFormatException);
      expect(NiconicoChatProtocol.delimited([1, 7, 0]).map((m) => m.length), [1, 0]);
    });
  });

  group('connector over the recording (fixtures/niconico/danmaku/S07-live)', () {
    test('watch page → own seat → message server; windows under way are read and paced', () {
      fakeAsync((async) {
        final watch = File('../../fixtures/niconico/S03-watch-user-live/body.html').readAsStringSync();
        var view = 0;
        final seen = <String>[];
        final http = FakeHttp((request) {
          final url = request.url;
          seen.add(url.path);
          if (url.host == 'live.nicovideo.jp') {
            return Future.value(LiveResponse(status: 200, bytes: utf8.encode(watch), url: url));
          }
          if (url.path.startsWith('/api/view/')) {
            // After the recording the view never answers (a long poll).
            if (view >= views.length) return Completer<LiveResponse>().future;
            return Future.value(LiveResponse(status: 200, bytes: views[view++].bytes, url: url));
          }
          final frame = segments[url.path];
          return Future.value(
            LiveResponse(status: frame == null ? 404 : 200, bytes: frame?.bytes ?? const [], url: url),
          );
        });
        final seat = _Seat();
        Uri? seatUrl;
        final connector = NiconicoChatConnector(
          detail: RoomDetail(
            card: RoomCard(
              ref: RoomRef('niconico', 'user/144846457'),
              title: '',
              anchorName: '',
              state: LiveState.live,
            ),
            link: Uri.parse('https://live.nicovideo.jp/watch/user/144846457'),
            danmakuKeys: const {'programId': 'lv351482868'},
          ),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
          connect: (url, headers) async {
            seatUrl = url;
            return seat;
          },
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        var joined = false;
        unawaited(connector.connect().then((value) => joined = value));
        async.elapse(const Duration(seconds: 1));
        expect(seatUrl!.path, startsWith('/unama/wsapi/v2/watch/'));
        expect(jsonDecode(seat.sent.first), containsPair('type', 'startWatching'));
        expect(joined, isTrue);
        async.elapse(const Duration(seconds: 40));
        expect(events.whereType<DanmakuChat>(), hasLength(15), reason: 'finished windows are history');
        expect(seen.where((path) => path.startsWith('/data/segment/')), hasLength(4));
        unawaited(connector.close());
        async.flushMicrotasks();
        expect(seat.closed, isTrue);
      });
    });

    test('a program that is not on air ends the start', () {
      fakeAsync((async) {
        final ended = File('../../fixtures/niconico/S03-watch-user-ended/body.html').readAsStringSync();
        final http = FakeHttp(
          (request) async => LiveResponse(status: 200, bytes: utf8.encode(ended), url: request.url),
        );
        final connector = NiconicoChatConnector(
          detail: RoomDetail(
            card: RoomCard(
              ref: RoomRef('niconico', 'user/138383030'),
              title: '',
              anchorName: '',
              state: LiveState.offline,
            ),
            link: Uri.parse('https://live.nicovideo.jp/watch/user/138383030'),
          ),
          transport: FakeTransport(http: http),
          clock: FakeClock(async, _start),
          connect: (url, headers) async => throw StateError('no seat for an ended program'),
        );
        final events = <DanmakuEvent>[];
        connector.events.listen(events.add);
        bool? joined;
        unawaited(connector.connect().then((value) => joined = value));
        async.flushMicrotasks();
        expect(joined, isFalse);
        expect(events.whereType<DanmakuSystem>().last.args.first, 'offline');
      });
    });
  });
}
