// niconico comments (docs/modules/M5.14-niconico.md): the comment server
// protocol against the archived v4's decoding of the recording
// (fixtures/niconico/danmaku/S07-live, expected.json written by
// danmaku/v4_expected.dart), synthetic entries and messages, and the
// connection over a real NiconicoSite with a fake seat socket (the recorded
// seat conversation seat/S04-seat) and a fake comment server streaming the
// recorded answers; one test streams through IoLiveHttp from a local server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/niconico';

/// The recorded answers of S07-live: line, URL and body.
final List<({int line, Uri url, Uint8List bytes})> _recording = [
  for (final (index, line) in File('$_root/danmaku/S07-live/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': 'in', 'url': final String url, 'b64': final String b64})
      (line: index + 1, url: Uri.parse(url), bytes: base64.decode(b64)),
];

/// The archived v4's output for S07-live, by line.
final Map<int, Map<String, Object?>> _v4 = {
  for (final frame
      in ((jsonDecode(File('$_root/danmaku/S07-live/expected.json').readAsStringSync()) as Map)['value']
              as Map)['frames']
          as List)
    (frame as Map<String, Object?>)['line']! as int: frame,
};

/// When S07-live was recorded: the windows' waits are timed from it.
final DateTime _recordedAt = DateTime.parse(
  (jsonDecode(File('$_root/danmaku/S07-live/meta.json').readAsStringSync()) as Map)['capturedAt'] as String,
);

/// The recorded `view` address (its token scrubbed), without `at`.
final Uri _view = _recording.first.url.replace(query: '');

/// The recorded `view` answers by `at`.
final Map<String, Uint8List> _views = {
  for (final frame in _recording)
    if (frame.url.path.startsWith('/api/view/')) frame.url.queryParameters['at']!: frame.bytes,
};

/// The recorded windows by path, in the order they were read.
final Map<String, Uint8List> _windows = {
  for (final frame in _recording)
    if (frame.url.path.startsWith('/data/segment/')) frame.url.path: frame.bytes,
};

/// The room and program of the recording (its meta.json).
const _args = NiconicoDanmakuArgs(roomId: 'user/15119555', programId: 'lv351482215');

// Protobuf builders ------------------------------------------------------------

Uint8List _pb(void Function(ProtoWriter writer) build) {
  final writer = ProtoWriter();
  build(writer);
  return writer.toBytes();
}

Uint8List _timestamp(int seconds, [int nanos = 0]) => _pb((w) {
  w.integer(1, seconds);
  if (nanos != 0) w.integer(2, nanos);
});

Uint8List _meta({String? id = 'm1', int? seconds = 1790541800, int nanos = 0}) => _pb((w) {
  if (id != null) w.string(1, id);
  if (seconds != null) w.bytes(2, _timestamp(seconds, nanos));
});

Uint8List _chat({String content = 'こんにちは', String? name, int? raw, String? hashed = 'a:hashed', Uint8List? modifier}) =>
    _pb((w) {
      w.string(1, content);
      if (name != null) w.string(2, name);
      w.integer(3, 1234);
      if (raw != null) w.integer(5, raw);
      if (hashed != null) w.string(6, hashed);
      if (modifier != null) w.bytes(7, modifier);
      w.integer(8, 7);
    });

/// A `ChunkedMessage` whose `NicoliveMessage` holds [data] as field [kind].
Uint8List _message(int kind, Uint8List data, {Uint8List? meta}) => _pb((w) {
  w
    ..bytes(1, meta ?? _meta())
    ..bytes(2, _pb((m) => m.bytes(kind, data)));
});

/// A `ChunkedMessage` whose payload is the state [state].
Uint8List _state(Uint8List state) => _pb((w) {
  w
    ..bytes(1, _meta())
    ..bytes(4, state);
});

Uint8List _statistics(int viewers) => _pb(
  (w) => w.bytes(
    1,
    _pb(
      (s) => s
        ..integer(1, viewers)
        ..integer(2, 5),
    ),
  ),
);

/// [messages] length-delimited.
Uint8List _delimit(List<List<int>> messages) {
  final out = BytesBuilder();
  for (final message in messages) {
    var length = message.length;
    while (length >= 0x80) {
      out.addByte(length & 0x7F | 0x80);
      length >>= 7;
    }
    out
      ..addByte(length)
      ..add(message);
  }
  return out.toBytes();
}

Uint8List _window(int from, int until, String uri, {int kind = 1}) => _pb(
  (w) => w.bytes(
    kind,
    _pb((s) {
      s
        ..bytes(1, _timestamp(from))
        ..bytes(2, _timestamp(until))
        ..string(3, uri);
    }),
  ),
);

Uint8List _next(int at) => _pb((w) => w.bytes(4, _pb((n) => n.integer(1, at))));

// Projections --------------------------------------------------------------------

/// A reported message in the archived v4's shape: v4 prefixed the id with
/// `niconico:` and labelled the viewers `online` (differences 1 and 2).
Map<String, Object?> _asV4(LiveMessage message) => switch (message.type) {
  LiveMessageType.chat => {
    'type': 'chat',
    'id': message.messageId.isEmpty ? null : 'niconico:${message.messageId}',
    'userId': message.userId,
    'userName': message.userName,
    'text': message.message,
    'sentAt': message.sentAt?.microsecondsSinceEpoch,
  },
  LiveMessageType.online => {
    'type': 'online',
    'audience': 'online',
    'value': (message.data! as LiveAudienceUpdate).value,
  },
  _ => {'type': message.type.name},
};

/// v4's events of a window without their times (a chat's is its `sentAt`).
List<Map<String, Object?>> _v4Events(int line) => [
  for (final event in (_v4[line]!['events']! as List).cast<Map<String, Object?>>()) {...event}..remove('at'),
];

List<LiveMessage> _decodeWindow(Uint8List bytes) => [
  for (final message in NiconicoDanmakuProtocol.split(bytes)) ?NiconicoDanmakuProtocol.message(message),
];

// Fakes ------------------------------------------------------------------------------

/// The embedded data of a recorded watch page.
Map<String, dynamic> _props(String sample) {
  final body = File('$_root/$sample/body.html').readAsStringSync();
  final raw = RegExp('data-props="([^"]*)"').firstMatch(body)!.group(1)!;
  return jsonDecode(decodeHtmlEntities(raw)) as Map<String, dynamic>;
}

/// A watch page: [sample]'s embedded data for the user [user] and the
/// program [program] (S03-watch-user-live is on air and anonymous viewers
/// may watch it).
LiveResponse _page({
  String sample = 'S03-watch-user-live',
  String user = '15119555',
  String program = 'lv351482215',
  void Function(Map<String, dynamic> props)? edit,
}) {
  final props = _props(sample);
  final data = props['program'] as Map<String, dynamic>;
  data['nicoliveProgramId'] = program;
  (data['supplier'] as Map<String, dynamic>)['programProviderId'] = user;
  edit?.call(props);
  final html = '<script id="embedded-data" data-props="${const HtmlEscape().convert(jsonEncode(props))}"></script>';
  return LiveResponse(status: 200, bytes: utf8.encode(html), url: Uri.parse('https://live.nicovideo.jp/watch/'));
}

/// The server's frames of the recorded seat (S04-seat, without its pings),
/// its comment server replaced by [view] (the recording's), or left out.
List<String> _seatFrames({Uri? view, bool messageServer = true}) {
  final frames = <String>[];
  for (final line in File('$_root/seat/S04-seat/frames.jsonl').readAsLinesSync()) {
    if (jsonDecode(line) case {'dir': 'in', 'text': final String text} when !text.contains('"ping"')) {
      if (jsonDecode(text) case {'type': 'messageServer', 'data': final Map<String, dynamic> data}) {
        if (messageServer) {
          frames.add(
            jsonEncode({
              'type': 'messageServer',
              'data': {...data, 'viewUri': '${view ?? _view}'},
            }),
          );
        }
      } else {
        frames.add(text);
      }
    }
  }
  return frames;
}

/// A fake seat WebSocket: the server's frames are queued before the seat
/// listens.
final class _Channel implements SocketChannel {
  new([List<String>? frames]) {
    (frames ?? _seatFrames()).forEach(incoming.add);
  }

  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;

  void server(String type, [Object? data]) => incoming.add(jsonEncode({'type': type, 'data': ?data}));

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('closed');
    sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// Hands out seats: [channels] in order, then new recorded ones.
final class _Connector {
  new([List<_Channel>? channels]) : channels = channels ?? [];

  final List<_Channel> channels;
  final List<_Channel> handed = [];
  final List<({Uri endpoint, Map<String, String> headers, ProxyRoute route})> calls = [];

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    calls.add((endpoint: endpoint, headers: headers, route: route));
    final channel = channels.isEmpty ? _Channel() : channels.removeAt(0);
    handed.add(channel);
    return channel;
  }
}

/// An answer that never comes: the request waits for its cancellation.
const Object _hold = #hold;

/// A body the test writes, which ignores cancellation (a late answer).
final class _Manual {
  final StreamController<List<int>> controller = StreamController<List<int>>();
}

/// The watch pages and the comment server. Watch pages come from [pages] in
/// order (the last one repeats); the comment server from [view] and
/// [window], by default the recording: `view` answers by `at` (held when
/// there is none, the long poll), windows by path, each one only after the
/// one before it was fully sent. An answer is bytes (sent in [chunk]-byte
/// pieces), a status, an exception to throw or [_hold].
final class _Http implements LiveHttp {
  new({List<Object>? pages, this.view, this.window}) : pages = pages ?? [_page()];

  final List<Object> pages;
  final Object Function(LiveRequest request)? view;
  final Object Function(LiveRequest request)? window;

  /// Size of the pieces an answer is sent in.
  static const int chunk = 7;
  final List<LiveRequest> sent = [];
  final List<LiveRequest> opened = [];
  int open_ = 0;
  Future<void> _previousWindow = Future.value();

  List<String> get views => [
    for (final request in opened)
      if (request.url.path.startsWith('/api/view/')) request.url.queryParameters['at']!,
  ];

  List<String> get windows => [
    for (final request in opened)
      if (!request.url.path.startsWith('/api/view/')) request.url.path,
  ];

  static Future<Never> _cancelled(LiveRequest request) async {
    await request.cancel?.whenCancelled;
    throw TransportFailure(request.site, TransportReason.cancelled);
  }

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    sent.add(request);
    final page = pages.length > 1 ? pages.removeAt(0) : pages.single;
    return switch (page) {
      final LiveResponse response => response,
      final Exception error => throw error,
      _ => await _cancelled(request),
    };
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    opened.add(request);
    final isView = request.url.path.startsWith('/api/view/');
    final answer = isView
        ? (view?.call(request) ?? _views[request.url.queryParameters['at']] ?? _hold)
        : (window?.call(request) ?? _windows[request.url.path] ?? 404);
    if (answer case final Exception error) throw error;
    if (answer case final _Manual manual) {
      return LiveStreamedResponse(status: 200, body: manual.controller.stream, url: request.url);
    }
    if (answer case final int status) return _body(request, const [], status: status);
    final hold = answer == _hold;
    final bytes = hold ? const <int>[] : answer as List<int>;
    if (isView) return _body(request, bytes, hold: hold);
    final previous = _previousWindow;
    final sent = Completer<void>();
    _previousWindow = sent.future;
    return _body(request, bytes, hold: hold, after: previous, sent: sent);
  }

  /// A streamed answer of [bytes]; cancelling the request fails it, as
  /// IoLiveHttp does.
  LiveStreamedResponse _body(
    LiveRequest request,
    List<int> bytes, {
    int status = 200,
    bool hold = false,
    Future<void>? after,
    Completer<void>? sent,
  }) {
    final controller = StreamController<List<int>>();
    var counted = false;
    var listening = false;
    void release() {
      if (counted) open_--;
      counted = false;
      listening = false;
      if (sent != null && !sent.isCompleted) sent.complete();
    }

    void fail() {
      if (controller.isClosed) return;
      controller.addError(TransportFailure(request.site, TransportReason.cancelled));
      unawaited(controller.close());
      release();
    }

    controller
      ..onListen = () async {
        open_++;
        counted = true;
        listening = true;
        unawaited(request.cancel?.whenCancelled.then((_) => fail()));
        await after;
        for (var offset = 0; offset < bytes.length; offset += chunk) {
          if (!listening || controller.isClosed) return;
          controller.add(bytes.sublist(offset, min(offset + chunk, bytes.length)));
          await Future<void>.delayed(Duration.zero);
        }
        if (hold || !listening || controller.isClosed) return;
        await controller.close();
        release();
      }
      ..onCancel = release;
    return LiveStreamedResponse(status: status, body: controller.stream, url: request.url);
  }

  @override
  void close() {}
}

typedef _Setup = ({NiconicoDanmakuConnection connection, _Http http, _Connector seats, List<DanmakuEvent> events});

_Setup _setup({
  _Http? http,
  _Connector? seats,
  Duration messageServerTimeout = const Duration(milliseconds: 200),
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) {
  final server = http ?? _Http();
  final connector = seats ?? _Connector();
  final site = NiconicoSite(server, connector: connector.call, proxy: proxy);
  final connection = NiconicoDanmakuConnection(
    site: site,
    now: () => _recordedAt,
    retryDelay: const Duration(milliseconds: 1),
    messageServerTimeout: messageServerTimeout,
  );
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return (connection: connection, http: server, seats: connector, events: events);
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition, {String reason = 'condition'}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('$reason not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event case DanmakuReceived(:final message)) message,
];

List<String> _kinds(List<DanmakuEvent> events) => [
  for (final event in events)
    switch (event) {
      DanmakuReady() => 'ready',
      DanmakuReceived() => 'message',
      DanmakuReconnecting(:final reason) => 'reconnecting:${reason.name}',
      DanmakuClosed(:final reason) => 'closed:${reason.name}',
    },
];

/// [_kinds] with runs of messages collapsed.
List<String> _outline(List<DanmakuEvent> events) {
  final out = <String>[];
  for (final kind in _kinds(events)) {
    if (kind == 'message' && out.isNotEmpty && out.last == 'message') continue;
    out.add(kind);
  }
  return out;
}

void main() {
  group('protocol', () {
    test('headers, timing and backoff', () {
      expect(NiconicoDanmakuProtocol.headers, {
        'referer': 'https://live.nicovideo.jp/',
        'user-agent': 'Mozilla/5.0',
        'origin': 'https://live.nicovideo.jp',
      });
      expect(NiconicoDanmakuProtocol.messageServerTimeout, const Duration(seconds: 10));
      expect(NiconicoDanmakuProtocol.firstViewTimeout, const Duration(seconds: 20));
      expect(NiconicoDanmakuProtocol.viewTimeout, const Duration(seconds: 60));
      expect(NiconicoDanmakuProtocol.windowGrace, const Duration(seconds: 20));
      final until = DateTime.utc(2026, 9, 27, 20, 43, 9);
      Duration wait(Duration before) => NiconicoDanmakuProtocol.windowTimeout(until, until.subtract(before));
      expect(wait(const Duration(seconds: 18)), const Duration(seconds: 38));
      expect(wait(Duration.zero), const Duration(seconds: 20));
      expect(wait(const Duration(seconds: -30)), const Duration(seconds: 20), reason: 'a window already over');
      expect(wait(const Duration(seconds: 60)), const Duration(seconds: 80));
      expect(wait(const Duration(hours: 2)), const Duration(seconds: 80), reason: 'a clock that is off');
      expect(NiconicoDanmakuProtocol.maxFailures, 8);
      expect([for (var n = 1; n <= 9; n++) NiconicoDanmakuProtocol.backoff(n).inSeconds], [1, 2, 4, 8, 8, 8, 8, 8, 8]);
    });

    test('the comment server: https on nicovideo.jp only', () {
      for (final ok in [
        'https://mpn.live.nicovideo.jp/api/view/v4/x',
        'https://nicovideo.jp/data/segment/v4/x',
        '$_view',
      ]) {
        expect(NiconicoDanmakuProtocol.isCommentServer(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in [
        'http://mpn.live.nicovideo.jp/api/view/v4/x',
        'https://mpn.live.nicovideo.jp:8443/api/view/v4/x',
        'https://user@mpn.live.nicovideo.jp/api/view/v4/x',
        'https://mpn.live.nicovideo.jp/api/view/v4/x#f',
        'https://evilnicovideo.jp/x',
        'https://mpn.live.nicovideo.jp.example.com/x',
        'wss://mpn.live.nicovideo.jp/x',
      ]) {
        expect(NiconicoDanmakuProtocol.isCommentServer(Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('the view requests are the recorded ones; requests go as niconico, without redirects', () {
      final views = [
        for (final frame in _recording)
          if (frame.url.path.startsWith('/api/view/')) frame.url,
      ];
      expect([for (final url in views) NiconicoDanmakuProtocol.viewUrl(_view, url.queryParameters['at']!)], views);
      final cancel = CancelToken();
      final request = NiconicoDanmakuProtocol.request(_view, timeout: const Duration(seconds: 3), cancel: cancel);
      expect(request.site, 'niconico');
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.headers, NiconicoDanmakuProtocol.headers);
      expect(request.timeout, const Duration(seconds: 3));
      expect(request.cancel, same(cancel));
    });

    test('length-delimited answers: every split of the recorded ones gives the same messages', () {
      for (final frame in _recording) {
        final whole = NiconicoDanmakuProtocol.split(frame.bytes);
        expect(whole, isNotEmpty);
        for (final size in [1, 2, 3, 5, 7, 64, 1000]) {
          final reader = NiconicoDelimitedReader();
          final pieces = [
            for (var offset = 0; offset < frame.bytes.length; offset += size)
              ...reader.add(frame.bytes.sublist(offset, min(offset + size, frame.bytes.length))),
          ];
          reader.close();
          expect(pieces, whole, reason: 'line ${frame.line} in $size-byte pieces');
        }
      }
    });

    test('length-delimited answers: empty messages, bad prefixes, oversize and truncation', () {
      expect(NiconicoDanmakuProtocol.split([0, 1, 7, 0]).map((m) => m.toList()), [
        <int>[],
        [7],
        <int>[],
      ]);
      expect(NiconicoDanmakuProtocol.split([]), isEmpty);
      // A prefix split across chunks.
      final reader = NiconicoDelimitedReader();
      expect(reader.add([0x81]), isEmpty);
      expect(reader.hasPending, isTrue);
      expect(reader.add([0x01, ...List.filled(128, 9)]), isEmpty);
      expect(reader.add([9]).single, hasLength(129));
      expect(reader.hasPending, isFalse);
      // Ten bytes of prefix are read; the eleventh is refused.
      expect(() => NiconicoDanmakuProtocol.split(List.filled(11, 0x80)), throwsFormatException);
      expect(() => NiconicoDelimitedReader().add(List.filled(10, 0x80)), throwsFormatException);
      expect(
        () => NiconicoDanmakuProtocol.split([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]),
        throwsFormatException,
        reason: 'a negative length',
      );
      expect(() => NiconicoDanmakuProtocol.split([5, 1, 2], maxLength: 4), throwsFormatException);
      expect(NiconicoDanmakuProtocol.split([4, 1, 2, 3, 4], maxLength: 4).single, [1, 2, 3, 4]);
      expect(() => NiconicoDanmakuProtocol.split([5, 1, 2]), throwsFormatException, reason: 'truncated');
      expect(() => NiconicoDanmakuProtocol.split([0x80]), throwsFormatException, reason: 'truncated prefix');
    });

    test('a streamed answer: messages as they complete, an error when it ends inside one', () async {
      final controller = StreamController<List<int>>();
      final got = <List<int>>[];
      final done = NiconicoDanmakuProtocol.delimited(controller.stream).forEach(got.add);
      controller.add([2, 1]);
      await _wait(Duration.zero);
      expect(got, isEmpty);
      controller.add([2, 3]);
      await _wait(Duration.zero);
      expect(got, [
        [1, 2],
      ]);
      controller.add([1]);
      unawaited(controller.close());
      await expectLater(done, throwsFormatException);
      expect(got, hasLength(1));
    });
  });

  group('recording (S07-live) against the archived v4', () {
    test('every view answer: the windows under way, the finished ones and next, as v4 read them', () {
      for (final frame in _recording.where((frame) => frame.url.path.startsWith('/api/view/'))) {
        final entries = [
          for (final bytes in NiconicoDanmakuProtocol.split(frame.bytes)) NiconicoDanmakuProtocol.viewEntry(bytes),
        ];
        final v4 = _v4[frame.line]!;
        Map<String, Object?> window(NiconicoCommentWindow window) => {
          'from': window.from.microsecondsSinceEpoch,
          'until': window.until.microsecondsSinceEpoch,
          'uri': '${window.uri}',
        };
        List<Map<String, Object?>> of(NiconicoViewEntryKind kind) => [
          for (final entry in entries)
            if (entry.kind == kind) window(entry.window!),
        ];
        expect(of(NiconicoViewEntryKind.segment), v4['segments'], reason: 'line ${frame.line}');
        expect(of(NiconicoViewEntryKind.previous), v4['previous'], reason: 'line ${frame.line}');
        expect(
          [
            for (final entry in entries)
              if (entry.kind == NiconicoViewEntryKind.next) entry.next,
          ],
          [v4['next']],
        );
        expect(entries.last.kind, NiconicoViewEntryKind.next, reason: 'next ends the answer');
        expect(
          entries.where((entry) => entry.kind == NiconicoViewEntryKind.backward),
          hasLength(frame.url.queryParameters['at'] == 'now' ? 0 : 1),
        );
      }
      final second = _v4[2]!['segments']! as List;
      expect(second, hasLength(2));
      expect(
        [for (final window in second.cast<Map<String, Object?>>()) Uri.parse(window['uri']! as String).path],
        [for (final frame in _recording.where((f) => f.line == 3 || f.line == 4)) frame.url.path],
        reason: 'the windows read next are the ones the view announced',
      );
    });

    test('every window: chats and viewers as v4 decoded them (ids without its prefix, viewers cumulative)', () {
      var chats = 0;
      var figures = 0;
      for (final frame in _recording.where((frame) => frame.url.path.startsWith('/data/segment/'))) {
        final messages = _decodeWindow(frame.bytes);
        expect([for (final message in messages) _asV4(message)], _v4Events(frame.line), reason: 'line ${frame.line}');
        for (final message in messages) {
          if (message.type == LiveMessageType.chat) {
            chats++;
            expect(message.messageId, isNot(startsWith('niconico:')));
            expect(message.messageId, isNotEmpty);
            expect(message.color, LiveMessageColor.white, reason: 'no modifier in the recording');
            expect(message.userName, isEmpty, reason: 'anonymous commenters');
            expect(message.userId, matches(RegExp(r'^[a-z]:[A-Za-z0-9_-]{16}$')), reason: 'hashed ids');
            expect(message.sentAt!.isUtc, isFalse, reason: 'local time, as the other platforms');
          } else {
            figures++;
            expect(message.type, LiveMessageType.online);
            final update = message.data! as LiveAudienceUpdate;
            expect(update.kind, LiveAudienceMetricKind.totalViewers, reason: 'statistics.viewers is cumulative');
          }
        }
      }
      expect(chats, 15);
      expect(figures, 30);
    });

    test('what is not reported: the ad, the visit notice and the flush signals', () {
      final kinds = <String>[];
      for (final frame in _recording.where((frame) => frame.url.path.startsWith('/data/segment/'))) {
        for (final bytes in NiconicoDanmakuProtocol.split(frame.bytes)) {
          final chunk = ProtoMessage.decode(bytes);
          final message = NiconicoDanmakuProtocol.message(bytes);
          if (chunk.integer(5) != null) {
            kinds.add('signal');
            expect(message, isNull);
          } else if (chunk.message(2) case final data?) {
            final kind = data.fields.last.number;
            if (kind != 1) {
              kinds.add('message $kind');
              expect(message, isNull);
            }
          }
        }
      }
      expect(kinds, ['message 9', 'signal', 'message 23', 'signal', 'signal', 'signal']);
    });

    test('the cumulative viewers of the seat and the comment server are one figure (watchCount)', () {
      // S04-seat's seat statistics and the S03 watch page are the same
      // program: 2292 on the page, then 2308 and 2322 on the seat.
      final seat = [
        for (final text in _seatFrames())
          if (jsonDecode(text) case {'type': 'statistics', 'data': {'viewers': final int viewers}}) viewers,
      ];
      expect(seat, [2308, 2322]);
      expect((_props('S03-watch-user-live')['program'] as Map)['statistics'], containsPair('watchCount', 2292));
      final figures = [
        for (final frame in _recording.where((frame) => frame.url.path.startsWith('/data/segment/')))
          for (final message in _decodeWindow(frame.bytes))
            if (message.data case LiveAudienceUpdate(:final value)) value,
      ];
      for (var i = 1; i < figures.length; i++) {
        expect(figures[i], greaterThanOrEqualTo(figures[i - 1]), reason: 'it never goes down');
      }
    });
  });

  group('synthetic entries and messages', () {
    test('view entries: kinds, the last one wins, unusable windows', () {
      NiconicoViewEntry entry(Uint8List bytes) => NiconicoDanmakuProtocol.viewEntry(bytes);
      final window = entry(_window(1790541773, 1790541789, 'https://mpn.live.nicovideo.jp/data/segment/v4/x'));
      expect(window.kind, NiconicoViewEntryKind.segment);
      expect(window.window!.from, DateTime.fromMillisecondsSinceEpoch(1790541773000));
      expect(window.window!.until.difference(window.window!.from), const Duration(seconds: 16));
      expect('${window.window}', isNot(contains('/v4/')), reason: 'no token in the text');
      expect(entry(_window(1, 2, 'https://mpn.live.nicovideo.jp/x', kind: 3)).kind, NiconicoViewEntryKind.previous);
      expect(entry(_pb((w) => w.bytes(2, _pb((b) => b.bytes(1, _timestamp(5)))))).kind, NiconicoViewEntryKind.backward);
      expect(entry(_next(1790541805)).next, 1790541805);
      for (final bad in [0, -1]) {
        final next = entry(_next(bad));
        expect(next.kind, NiconicoViewEntryKind.next);
        expect(next.next, isNull);
      }
      expect(entry(_pb((w) => w.bytes(9, [1]))).kind, NiconicoViewEntryKind.unknown);
      expect(entry(Uint8List(0)).kind, NiconicoViewEntryKind.unknown);
      expect(
        entry(Uint8List.fromList([..._window(1, 2, 'https://a.nicovideo.jp/x'), ..._next(9)])).kind,
        NiconicoViewEntryKind.next,
      );
      for (final uri in ['http://a.nicovideo.jp/x', 'https://example.com/x', 'not a url', '']) {
        expect(entry(_window(1, 2, uri)).window, isNull, reason: uri);
      }
      final noUntil = _pb(
        (w) => w.bytes(
          1,
          _pb(
            (s) => s
              ..bytes(1, _timestamp(1))
              ..string(3, 'https://a.nicovideo.jp/x'),
          ),
        ),
      );
      expect(entry(noUntil).window, isNull);
      expect(() => entry(Uint8List.fromList([0xFF])), throwsFormatException);
    });

    test('a chat: text, name, ids, time and colour', () {
      final message = NiconicoDanmakuProtocol.message(
        _message(
          1,
          _chat(content: '  ８８８  ', name: ' 名前 ', raw: 12345, hashed: 'a:abc'),
          meta: _meta(nanos: 987654321),
        ),
      )!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, '８８８');
      expect(message.userName, '名前');
      expect(message.userId, 'a:abc', reason: 'hashed first, as v4');
      expect(message.messageId, 'm1');
      expect(message.sentAt, DateTime.fromMicrosecondsSinceEpoch(1790541800987654));
      expect(message.color, LiveMessageColor.white);
      expect(message.isLocal, isFalse);
      expect(message.userLevel, isEmpty);
      expect(NiconicoDanmakuProtocol.message(_message(1, _chat(raw: 12345, hashed: '')))!.userId, '12345');
      expect(NiconicoDanmakuProtocol.message(_message(1, _chat(raw: 12345, hashed: null)))!.userId, '12345');
      expect(NiconicoDanmakuProtocol.message(_message(1, _chat(hashed: null)))!.userId, isEmpty);
      expect(NiconicoDanmakuProtocol.message(_message(1, _chat()))!.userName, isEmpty, reason: 'no name');
      for (final blank in ['', '   ', '\n']) {
        expect(NiconicoDanmakuProtocol.message(_message(1, _chat(content: blank))), isNull, reason: 'blank');
      }
    });

    test('an overflowed chat is a chat; gifts, ads, notices and the rest are not reported', () {
      expect(NiconicoDanmakuProtocol.message(_message(20, _chat(content: 'あふれ')))!.message, 'あふれ');
      for (final kind in [7, 8, 9, 13, 17, 18, 19, 22, 23, 24, 25, 26, 99]) {
        final data = kind == 22 ? _pb((w) => w.bytes(1, _chat())) : _pb((w) => w.string(2, 'x'));
        expect(NiconicoDanmakuProtocol.message(_message(kind, data)), isNull, reason: 'NicoliveMessage.$kind');
      }
      // A oneof: the last field wins.
      final both = _pb((w) {
        w
          ..bytes(1, _meta())
          ..bytes(
            2,
            _pb(
              (m) => m
                ..bytes(1, _chat())
                ..bytes(8, _pb((g) => g.string(1, 'gift'))),
            ),
          );
      });
      expect(NiconicoDanmakuProtocol.message(both), isNull);
      final chatLast = _pb((w) {
        w
          ..bytes(1, _meta())
          ..bytes(
            2,
            _pb(
              (m) => m
                ..bytes(8, _pb((g) => g.string(1, 'gift')))
                ..bytes(1, _chat(content: 'last')),
            ),
          );
      });
      expect(NiconicoDanmakuProtocol.message(chatLast)!.message, 'last');
    });

    test('the viewers: cumulative, zero included; no figure, a negative one or another state is nothing', () {
      LiveAudienceUpdate? figure(Uint8List bytes) =>
          NiconicoDanmakuProtocol.message(bytes)?.data as LiveAudienceUpdate?;
      expect(figure(_state(_statistics(9988)))!.value, 9988);
      expect(figure(_state(_statistics(9988)))!.kind, LiveAudienceMetricKind.totalViewers);
      expect(figure(_state(_statistics(0)))!.value, 0);
      expect(figure(_state(_statistics(1 << 40)))!.value, 1 << 40);
      expect(figure(_state(_statistics(-1))), isNull);
      expect(figure(_state(_pb((w) => w.bytes(1, _pb((s) => s.integer(2, 5)))))), isNull, reason: 'comments only');
      expect(figure(_state(_pb((w) => w.bytes(4, _pb((m) => m.string(1, 'marquee')))))), isNull);
      final message = NiconicoDanmakuProtocol.message(_state(_statistics(3)))!;
      expect(message.type, LiveMessageType.online);
      expect(message.userName, isEmpty);
      expect(message.message, isEmpty);
      // A oneof: the state after a chat wins.
      final last = _pb((w) {
        w
          ..bytes(1, _meta())
          ..bytes(2, _pb((m) => m.bytes(1, _chat())))
          ..bytes(4, _statistics(7));
      });
      expect(figure(last)!.value, 7);
    });

    test('signals, messages without payload or meta, times out of range', () {
      expect(NiconicoDanmakuProtocol.message(_pb((w) => w.integer(5, 0))), isNull, reason: 'Flushed');
      expect(NiconicoDanmakuProtocol.message(_pb((w) => w.bytes(1, _meta()))), isNull);
      expect(NiconicoDanmakuProtocol.message(Uint8List(0)), isNull);
      final bare = NiconicoDanmakuProtocol.message(_pb((w) => w.bytes(2, _pb((m) => m.bytes(1, _chat())))))!;
      expect(bare.messageId, isEmpty);
      expect(bare.sentAt, isNull, reason: 'kept without a time (v4 dropped it)');
      DateTime? at(Uint8List meta) => NiconicoDanmakuProtocol.message(_message(1, _chat(), meta: meta))!.sentAt;
      expect(at(_meta(seconds: null)), isNull);
      expect(at(_meta(nanos: 1000000000)), isNull);
      expect(
        at(
          _pb(
            (w) => w.bytes(
              2,
              _pb(
                (t) => t
                  ..integer(1, 5)
                  ..integer(2, -1),
              ),
            ),
          ),
        ),
        isNull,
      );
      expect(at(_meta(seconds: 8640000000001)), isNull);
      expect(at(_meta(seconds: -8640000000001)), isNull);
      expect(at(_meta(seconds: 8640000000000)), DateTime.fromMillisecondsSinceEpoch(8640000000000000));
      expect(() => NiconicoDanmakuProtocol.message([0xFF]), throwsFormatException);
    });

    test("colours: niconico's twenty names, full colours clamped, the last one wins", () {
      LiveMessageColor colour(Uint8List modifier) =>
          NiconicoDanmakuProtocol.message(_message(1, _chat(modifier: modifier)))!.color;
      final expected = [
        '#ffffff', '#ff0000', '#ff8080', '#ffc000', '#ffff00', '#00ff00', '#00ffff', '#0000ff', '#c000ff', '#000000', //
        '#cccc99', '#cc0033', '#ff33cc', '#ff6600', '#999900', '#00cc66', '#00cccc', '#3399ff', '#6633cc', '#666666',
      ];
      for (var value = 0; value < 20; value++) {
        expect('${colour(_pb((w) => w.integer(3, value)))}', expected[value], reason: 'ColorName $value');
      }
      expect(colour(_pb((w) => w.integer(3, 20))), LiveMessageColor.white, reason: 'a name this table lacks');
      expect(colour(_pb((w) => w.integer(3, -1))), LiveMessageColor.white);
      expect(colour(Uint8List(0)), LiveMessageColor.white);
      expect(
        colour(
          _pb(
            (w) => w
              ..integer(1, 2)
              ..integer(2, 2),
          ),
        ),
        LiveMessageColor.white,
        reason: 'position and size',
      );
      Uint8List full(int r, int g, int b) => _pb(
        (w) => w.bytes(
          4,
          _pb(
            (c) => c
              ..integer(1, r)
              ..integer(2, g)
              ..integer(3, b),
          ),
        ),
      );
      expect('${colour(full(0x12, 0x34, 0x56))}', '#123456');
      expect('${colour(full(-5, 300, 255))}', '#00ffff');
      expect('${colour(_pb((w) => w.bytes(4, Uint8List(0))))}', '#000000', reason: 'an empty full colour is black');
      expect('${colour(Uint8List.fromList([...full(1, 2, 3), ..._pb((w) => w.integer(3, 1))]))}', '#ff0000');
      expect('${colour(Uint8List.fromList([..._pb((w) => w.integer(3, 1)), ...full(1, 2, 3)]))}', '#010203');
    });
  });

  group('connection', () {
    test('registration, arguments and no heartbeat', () async {
      final setup = _setup();
      final registry = DanmakuRegistry({SiteIds.niconico: () => setup.connection});
      expect(registry.supports('niconico'), isTrue);
      expect(registry.connectionFor(' NicoNico '), same(setup.connection));
      expect(setup.connection.heartbeatInterval, Duration.zero);
      expect(setup.connection.retryDelay, const Duration(milliseconds: 1));
      final defaults = NiconicoDanmakuConnection(site: NiconicoSite(_Http()));
      expect(defaults.retryDelay, const Duration(seconds: 1));
      expect(defaults.messageServerTimeout, const Duration(seconds: 10));
      await expectLater(setup.connection.connect('lv351482215'), throwsArgumentError);
      setup.connection.heartbeat();
      expect(setup.http.sent, isEmpty);
      expect(setup.http.opened, isEmpty);
      expect(setup.seats.calls, isEmpty);
    });

    test('the recording through the connection: watch page, own seat, view, every window once; 15 chats', () async {
      final setup = _setup(proxy: const FixedProxyPolicy(global: HttpProxyRoute('127.0.0.1', 7897)));
      await setup.connection.connect(_args);
      expect(setup.events.first, const DanmakuReady());
      expect(setup.connection.isConnected, isTrue);
      await _until(() => setup.http.views.length == 4 && setup.http.open_ == 1, reason: 'the fourth view held');
      // The watch page of the room, with the adapter's headers.
      expect(
        [for (final request in setup.http.sent) '${request.url}'],
        ['https://live.nicovideo.jp/watch/user/15119555'],
      );
      expect(setup.http.sent.single.headers, NiconicoApi.headers);
      // Its seat, through the platform's route, as the adapter opens it.
      final seat = setup.seats.calls.single;
      expect(seat.endpoint.path, '/unama/wsapi/v2/watch/24876040585822');
      expect(seat.endpoint.queryParameters['frontend_id'], '9');
      expect(seat.headers, NiconicoApi.seatHeaders);
      expect(seat.route, const HttpProxyRoute('127.0.0.1', 7897));
      expect(setup.seats.handed.single.sent.first['type'], 'startWatching');
      // The comment server: view from now, then each next; the windows
      // under way, each once; the finished ones never.
      expect(setup.http.views, ['now', '1790541775', '1790541805', '1790541837']);
      expect(setup.http.windows, _windows.keys.toList());
      for (final request in setup.http.opened) {
        expect(request.site, 'niconico');
        expect(request.headers, NiconicoDanmakuProtocol.headers);
        expect(request.followRedirects, isFalse);
        expect(NiconicoDanmakuProtocol.isCommentServer(request.url), isTrue);
      }
      expect(
        [for (final request in setup.http.opened.take(2)) request.timeout],
        [const Duration(seconds: 20), const Duration(seconds: 60)],
      );
      // A window's wait: its time left at the recording, plus 20 s.
      final first = setup.http.opened.firstWhere((request) => request.url.path == _windows.keys.first);
      expect(
        first.timeout,
        DateTime.fromMillisecondsSinceEpoch(1790541789000).difference(_recordedAt) + const Duration(seconds: 20),
      );
      final last = setup.http.opened.lastWhere((request) => request.url.path == _windows.keys.last);
      expect(
        DateTime.fromMillisecondsSinceEpoch(1790541837000).difference(_recordedAt),
        greaterThan(const Duration(seconds: 60)),
        reason: 'the clock stands at the start of the recording',
      );
      expect(last.timeout, const Duration(seconds: 80), reason: 'at most 60 s left, plus 20 s');
      // v4's events, in order, each viewers figure once when it changes.
      final expected = <Map<String, Object?>>[];
      Object? lastFigure;
      for (final frame in _recording.where((frame) => frame.url.path.startsWith('/data/segment/'))) {
        for (final event in _v4Events(frame.line)) {
          if (event['type'] == 'online') {
            if (event['value'] == lastFigure) continue;
            lastFigure = event['value'];
          }
          expected.add(event);
        }
      }
      expect([for (final message in _messages(setup.events)) _asV4(message)], expected);
      expect(_messages(setup.events).where((message) => message.type == LiveMessageType.chat), hasLength(15));
      expect(_kinds(setup.events).where((kind) => kind != 'message'), ['ready'], reason: 'one join, no interruption');
      final count = setup.events.length;
      await setup.connection.close();
      expect(setup.connection.status, DanmakuStatus.idle);
      await _until(() => setup.http.open_ == 0, reason: 'the held view cancelled');
      expect(setup.seats.handed.single.closed, isTrue);
      await _wait(const Duration(milliseconds: 20));
      expect(setup.events, hasLength(count), reason: 'nothing after close');
    });

    test('joined only once the comment server answers', () async {
      final firstView = Completer<void>();
      final setup = _setup(
        http: _Http(
          view: (request) => firstView.isCompleted ? _views[request.url.queryParameters['at']] ?? _hold : _hold,
        ),
      );
      var connected = false;
      unawaited(setup.connection.connect(_args).then((_) => connected = true));
      await _until(() => setup.http.views.isNotEmpty);
      await _wait(const Duration(milliseconds: 20));
      expect(setup.events, isEmpty);
      expect(setup.connection.status, DanmakuStatus.connecting);
      expect(connected, isFalse);
      await setup.connection.close();
      expect(setup.events, isEmpty);
      await _until(() => setup.http.open_ == 0);
      expect(connected, isTrue, reason: 'close ends the start');
    });

    test('a lost window loses only its comments', () async {
      final paths = _windows.keys.toList();
      final setup = _setup(
        http: _Http(
          window: (request) => switch (paths.indexOf(request.url.path)) {
            0 => 404,
            1 => Uint8List.fromList([..._windows[paths[1]]!, 9, 1]),
            2 => const TransportFailure('niconico', TransportReason.timeout),
            _ => _windows[request.url.path]!,
          },
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 4);
      await _until(() => _messages(setup.events).where((m) => m.type == LiveMessageType.chat).length == 3 + 2);
      await _wait(const Duration(milliseconds: 20));
      final chats = [
        for (final message in _messages(setup.events))
          if (message.type == LiveMessageType.chat) message.message,
      ];
      expect(chats, [
        ..._v4Events(4).where((e) => e['type'] == 'chat').map((e) => e['text']),
        ..._v4Events(7).where((e) => e['type'] == 'chat').map((e) => e['text']),
      ], reason: 'the second window up to its bad end, the fourth; not the first and third');
      expect(_outline(setup.events), ['ready', 'message'], reason: 'no reconnection for a window');
      expect(setup.seats.calls, hasLength(1));
      await setup.connection.close();
    });

    test('a failed view is asked again on the same seat, after the first backoff step', () async {
      var failures = 0;
      final setup = _setup(
        http: _Http(
          view: (request) {
            final at = request.url.queryParameters['at']!;
            if (at == '1790541775' && failures < 2) {
              return [503, const TransportFailure('niconico', TransportReason.timeout)][failures++];
            }
            return _views[at] ?? _hold;
          },
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 6);
      expect(setup.http.views, ['now', '1790541775', '1790541775', '1790541775', '1790541805', '1790541837']);
      expect(_outline(setup.events).take(3), ['ready', 'reconnecting:disconnected', 'ready']);
      final reconnecting = setup.events.whereType<DanmakuReconnecting>().single;
      expect(reconnecting.detail, 'the comment server answered HTTP 503');
      expect(setup.seats.calls, hasLength(1), reason: 'the same seat');
      expect(setup.http.sent, hasLength(1), reason: 'one watch page');
      await _until(() => _messages(setup.events).where((m) => m.type == LiveMessageType.chat).length == 15);
      await setup.connection.close();
    });

    test('a join ends a series of failures: the next one is reported again and counted from one', () async {
      final failures = <String, int>{};
      final setup = _setup(
        http: _Http(
          view: (request) {
            final at = request.url.queryParameters['at']!;
            if ((at == '1790541775' || at == '1790541805') && (failures[at] ?? 0) < 5) {
              failures[at] = (failures[at] ?? 0) + 1;
              return 502;
            }
            return _views[at] ?? _hold;
          },
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 1 + 6 + 6 + 1);
      expect(_kinds(setup.events).where((kind) => kind != 'message'), [
        'ready',
        'reconnecting:disconnected',
        'ready',
        'reconnecting:disconnected',
        'ready',
      ], reason: 'ten failures, two series of five: not exhausted');
      expect(setup.connection.isConnected, isTrue);
      expect(setup.seats.calls, hasLength(1));
      await setup.connection.close();
    });

    test('a refused view takes a new seat from a new watch page', () async {
      var refused = false;
      final setup = _setup(
        http: _Http(
          view: (request) {
            final at = request.url.queryParameters['at']!;
            if (at == '1790541775' && !refused) {
              refused = true;
              return 403;
            }
            return _views[at] ?? _hold;
          },
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 6);
      expect(setup.http.views, ['now', '1790541775', 'now', '1790541775', '1790541805', '1790541837']);
      expect(_outline(setup.events).take(3), ['ready', 'reconnecting:disconnected', 'ready']);
      expect(setup.events.whereType<DanmakuReconnecting>().single.detail, 'the comment server answered HTTP 403');
      expect(setup.http.sent, hasLength(2));
      expect(setup.seats.handed, hasLength(2));
      expect(setup.seats.handed.first.closed, isTrue);
      await setup.connection.close();
      expect(setup.seats.handed.last.closed, isTrue);
    });

    test("a seat that ends is replaced: the broadcaster's next program is followed", () async {
      final setup = _setup(
        http: _Http(
          pages: [
            _page(),
            _page(program: 'lv351482999'),
          ],
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 4);
      final first = setup.seats.handed.single..server('disconnect', {'reason': 'END_PROGRAM'});
      await _until(() => setup.seats.handed.length == 2 && setup.http.views.length >= 6);
      expect(first.closed, isTrue);
      final reconnecting = setup.events.whereType<DanmakuReconnecting>().single;
      expect(reconnecting.reason, DanmakuInterruption.disconnected);
      expect(reconnecting.detail, contains('END_PROGRAM'));
      expect(setup.events.whereType<DanmakuReady>(), hasLength(2));
      expect(setup.http.views.skip(4).first, 'now', reason: "the new seat's comment server from now");
      expect(setup.connection.isConnected, isTrue);
      await setup.connection.close();
    });

    test('a room that went offline ends the connection', () async {
      final setup = _setup(
        http: _Http(
          pages: [
            _page(user: '138383030'),
            LiveResponse(
              status: 200,
              bytes: File('$_root/S03-watch-user-ended/body.html').readAsBytesSync(),
              url: Uri.parse('https://live.nicovideo.jp/watch/user/138383030'),
            ),
          ],
        ),
      );
      await setup.connection.connect(const NiconicoDanmakuArgs(roomId: 'user/138383030', programId: 'lv351482215'));
      await _until(() => setup.http.views.length == 4);
      setup.seats.handed.single.server('disconnect', {'reason': 'END_PROGRAM'});
      await _until(() => setup.events.last is DanmakuClosed);
      expect(_outline(setup.events), ['ready', 'message', 'reconnecting:disconnected', 'closed:connectionFailed']);
      expect((setup.events.last as DanmakuClosed).detail, startsWith('StreamUnavailable(niconico'));
      expect(setup.connection.status, DanmakuStatus.closed);
      expect(setup.seats.handed, hasLength(1), reason: 'no seat for an ended program');
      await _until(() => setup.http.open_ == 0);
    });

    test('a room that cannot be watched ends the start: offline, login, restricted, not a room', () async {
      final ended = LiveResponse(
        status: 200,
        bytes: File('$_root/S03-watch-user-ended/body.html').readAsBytesSync(),
        url: Uri.parse('https://live.nicovideo.jp/watch/user/138383030'),
      );
      for (final (args, page, kind) in [
        (const NiconicoDanmakuArgs(roomId: 'user/138383030', programId: 'lv351482791'), ended, 'StreamUnavailable'),
        (
          _args,
          _page(edit: (props) => ((props['programWatch'] as Map)['condition'] as Map)['needLogin'] = true),
          'NeedsLogin',
        ),
        (
          _args,
          _page(edit: (props) => (props['userProgramWatch'] as Map)['isCountryRestrictionTarget'] = true),
          'RegionBlocked',
        ),
        (_args, LiveResponse(status: 404, bytes: const [], url: Uri.parse('https://live.nicovideo.jp/')), 'NotFound'),
        (const NiconicoDanmakuArgs(roomId: 'not a room', programId: 'lv1'), _page(), 'NotFound'),
      ]) {
        final setup = _setup(http: _Http(pages: [page]));
        await setup.connection.connect(args);
        expect(_kinds(setup.events), ['closed:connectionFailed'], reason: kind);
        expect((setup.events.single as DanmakuClosed).detail, startsWith('$kind(niconico'), reason: kind);
        expect(setup.seats.calls, isEmpty, reason: kind);
        expect(setup.http.opened, isEmpty, reason: kind);
        expect(setup.http.sent, hasLength(args.roomId == 'not a room' ? 0 : 1), reason: kind);
      }
    });

    test('failures in a row: reported once, 1, 2, 4, 8… s apart, the ninth ends it', () async {
      final setup = _setup(
        http: _Http(
          pages: [LiveResponse(status: 503, bytes: const [], url: Uri.parse('https://live.nicovideo.jp/'))],
        ),
      );
      final delays = <Duration>[];
      final connection = NiconicoDanmakuConnection(
        site: NiconicoSite(setup.http, connector: setup.seats.call),
        now: () => _recordedAt,
      );
      final events = <DanmakuEvent>[];
      connection.events.listen(events.add);
      await runZoned(
        () async {
          await connection.connect(_args);
          expect(_kinds(events), ['reconnecting:disconnected'], reason: 'connect ends after the first attempt');
          await _until(() => events.last is DanmakuClosed);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration >= const Duration(seconds: 1) && duration <= const Duration(seconds: 8)) {
              delays.add(duration);
              return parent.createTimer(zone, Duration.zero, callback);
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      expect(delays.map((delay) => delay.inSeconds), [1, 2, 4, 8, 8, 8, 8, 8]);
      expect(_kinds(events), ['reconnecting:disconnected', 'closed:reconnectsExhausted']);
      expect((events.last as DanmakuClosed).detail, startsWith('NetworkFailure(niconico'));
      expect(setup.http.sent, hasLength(9));
      expect(setup.seats.calls, isEmpty);
    });

    test('failures on the comment server count too; the details carry no token', () async {
      final setup = _setup(
        http: _Http(view: (request) => request.url.queryParameters['at'] == 'now' ? _views['now']! : 500),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.events.last is DanmakuClosed);
      expect(_outline(setup.events), ['ready', 'reconnecting:disconnected', 'closed:reconnectsExhausted']);
      expect(setup.http.views, ['now', ...List.filled(9, '1790541775')]);
      for (final event in setup.events.whereType<DanmakuReconnecting>()) {
        expect(event.detail, isNot(contains('/v4/')));
      }
      expect((setup.events.last as DanmakuClosed).detail, 'the comment server answered HTTP 500');
      expect(setup.seats.handed.single.closed, isTrue);
    });

    test('a seat that names no comment server, or an unexpected one, is replaced', () async {
      final seats = _Connector([
        _Channel(_seatFrames(messageServer: false)),
        _Channel(_seatFrames(view: Uri.parse('http://mpn.live.nicovideo.jp/api/view/v4/x'))),
        _Channel(_seatFrames(view: Uri.parse('https://example.com/api/view/v4/x'))),
      ]);
      final setup = _setup(seats: seats, messageServerTimeout: const Duration(milliseconds: 30));
      await setup.connection.connect(_args);
      await _until(() => setup.connection.isConnected);
      expect(setup.seats.handed, hasLength(4));
      expect(setup.seats.handed.take(3).every((channel) => channel.closed), isTrue);
      expect(_outline(setup.events).take(2), ['reconnecting:disconnected', 'ready']);
      expect(
        setup.events.whereType<DanmakuReconnecting>().single.detail,
        'FormatException: the seat named no comment server within 30 ms',
      );
      expect(setup.http.opened.every((request) => request.url.host == 'mpn.live.nicovideo.jp'), isTrue);
      expect(setup.http.views.first, 'now');
      await setup.connection.close();
    });

    test('a seat that ends drops what its windows still send', () async {
      final late = _Manual();
      final setup = _setup(http: _Http(window: (request) => request.url.path == _windows.keys.first ? late : _hold));
      await setup.connection.connect(_args);
      await _until(() => late.controller.hasListener);
      late.controller.add(_delimit([_message(1, _chat(content: 'before'))]));
      await _until(() => _messages(setup.events).any((message) => message.message == 'before'));
      setup.seats.handed.single.server('disconnect', {'reason': 'END_PROGRAM'});
      await _until(() => setup.events.any((event) => event is DanmakuReconnecting));
      late.controller.add(_delimit([_message(1, _chat(content: 'after'))]));
      await _until(() => !late.controller.hasListener, reason: 'the late window given up');
      expect(_messages(setup.events).map((message) => message.message), isNot(contains('after')));
      await setup.connection.close();
    });

    test('closing while the watch page is read cancels it: no seat, no event', () async {
      final setup = _setup(http: _Http(pages: [_hold]));
      final connecting = setup.connection.connect(_args);
      await _until(() => setup.http.sent.isNotEmpty);
      await setup.connection.close();
      await connecting;
      expect(setup.http.sent.single.cancel!.isCancelled, isTrue);
      await _wait(const Duration(milliseconds: 20));
      expect(setup.events, isEmpty);
      expect(setup.seats.calls, isEmpty);
      expect(setup.connection.status, DanmakuStatus.idle);
    });

    test('closing while windows stream: every request cancelled, the seat closed, nothing after', () async {
      final setup = _setup(http: _Http(window: (request) => _hold));
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == 4 && setup.http.windows.length == 4 && setup.http.open_ == 5);
      await setup.connection.close();
      await _until(() => setup.http.open_ == 0);
      expect(setup.seats.handed.single.closed, isTrue);
      expect(setup.http.opened.every((request) => request.cancel!.isCancelled), isTrue);
      expect(_outline(setup.events), ['ready']);
    });

    test('another connect replaces the room: the old seat closes and reports nothing', () async {
      final setup = _setup(
        http: _Http(
          pages: [
            _page(),
            _page(user: '144846457', program: 'lv351482868'),
          ],
          window: (request) => _hold,
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.windows.length >= 2);
      final old = setup.seats.handed.single;
      await setup.connection.connect(const NiconicoDanmakuArgs(roomId: 'user/144846457', programId: 'lv351482868'));
      expect(old.closed, isTrue);
      expect(
        [for (final request in setup.http.sent) request.url.path],
        ['/watch/user/15119555', '/watch/user/144846457'],
      );
      expect(_kinds(setup.events), ['ready', 'ready']);
      old.server('disconnect', {'reason': 'END_PROGRAM'});
      await _wait(const Duration(milliseconds: 20));
      expect(_kinds(setup.events), ['ready', 'ready'], reason: 'the old seat is not heard');
      expect(setup.connection.isConnected, isTrue);
      await setup.connection.close();
      await _until(() => setup.http.open_ == 0);
    });

    test('a window streams through IoLiveHttp: each message as it arrives', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bytes = _windows.values.first;
      final halfway = Completer<void>();
      final requests = <HttpRequest>[];
      server.listen((request) async {
        requests.add(request);
        // Unbuffered, so the first part leaves before the rest is written.
        request.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('application', 'octet-stream');
        final messages = NiconicoDanmakuProtocol.split(bytes);
        // The first two messages, then a pause until the client has them.
        final first = _delimit(messages.take(2).toList());
        request.response.add(first);
        await request.response.flush();
        await halfway.future;
        request.response.add(bytes.sublist(first.length));
        await request.response.close();
      });
      final http = IoLiveHttp();
      addTearDown(http.close);
      final response = await http.open(
        LiveRequest(site: 'niconico', url: Uri.parse('http://127.0.0.1:${server.port}/data/segment/v4/x')),
      );
      final got = <LiveMessage?>[];
      await for (final message in NiconicoDanmakuProtocol.delimited(response.body)) {
        got.add(NiconicoDanmakuProtocol.message(message));
        if (got.length == 2 && !halfway.isCompleted) halfway.complete();
      }
      expect([for (final message in got) ?message].map(_asV4).toList(), _v4Events(3));
      expect(requests, hasLength(1));
    });
  });
}
