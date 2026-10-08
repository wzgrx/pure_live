// niconico comments (docs/D-弹幕/D01-平台弹幕协议/D01.15-niconico弹幕/record.md): the comment server
// protocol against the archived v4's decoding of the recording
// (fixtures/niconico/danmaku/S07-live, expected.json written by
// danmaku/v4_expected.dart), synthetic entries and messages, and the
// connection over a real NiconicoSite with a fake seat socket (the recorded
// seat conversation seat/S04-seat) and a fake comment server streaming the
// recorded answers; one test streams through IoLiveHttp from a local server.
// M5.F (B-11): notices and gifts against danmaku/S08-marquee, S09-ended and
// S10-gift, and synthetic frames for what was not seen live.
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

/// A recording of the comment server (`fixtures/niconico/danmaku/<name>`):
/// its answers (line, URL, body), its `view` address (without `at`), its
/// `view` answers by `at`, its windows by path, and when it was recorded.
final class _Tape {
  new(String name)
    : answers = [
        for (final (index, line) in File('$_root/danmaku/$name/frames.jsonl').readAsLinesSync().indexed)
          if (jsonDecode(line) case {'dir': 'in', 'url': final String url, 'b64': final String b64})
            (line: index + 1, url: Uri.parse(url), bytes: base64.decode(b64)),
      ],
      recordedAt = DateTime.parse(
        (jsonDecode(File('$_root/danmaku/$name/meta.json').readAsStringSync()) as Map)['capturedAt'] as String,
      );

  final List<({int line, Uri url, Uint8List bytes})> answers;
  final DateTime recordedAt;

  Uri get view => answers.firstWhere((frame) => frame.url.path.startsWith('/api/view/')).url.replace(query: '');

  Map<String, Uint8List> get views => {
    for (final frame in answers)
      if (frame.url.path.startsWith('/api/view/')) frame.url.queryParameters['at']!: frame.bytes,
  };

  Map<String, Uint8List> get windows => {
    for (final frame in answers)
      if (frame.url.path.startsWith('/data/segment/')) frame.url.path: frame.bytes,
  };

  /// Every window's messages, decoded alone, in order.
  List<LiveMessage> get messages => [
    for (final bytes in windows.values)
      for (final message in NiconicoDanmakuProtocol.split(bytes)) ?NiconicoDanmakuProtocol.message(message),
  ];
}

final _s07 = _Tape('S07-live');

/// The recorded answers of S07-live: line, URL and body.
final List<({int line, Uri url, Uint8List bytes})> _recording = _s07.answers;

/// The archived v4's output for S07-live, by line.
final Map<int, Map<String, Object?>> _v4 = {
  for (final frame
      in ((jsonDecode(File('$_root/danmaku/S07-live/expected.json').readAsStringSync()) as Map)['value']
              as Map)['frames']
          as List)
    (frame as Map<String, Object?>)['line']! as int: frame,
};

/// When S07-live was recorded: the windows' waits are timed from it.
final DateTime _recordedAt = _s07.recordedAt;

/// The recorded `view` address (its token scrubbed), without `at`.
final Uri _view = _s07.view;

/// The recorded `view` answers by `at`.
final Map<String, Uint8List> _views = _s07.views;

/// The recorded windows by path, in the order they were read.
final Map<String, Uint8List> _windows = _s07.windows;

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
Uint8List _state(Uint8List state, {Uint8List? meta}) => _pb((w) {
  w
    ..bytes(1, meta ?? _meta())
    ..bytes(4, state);
});

/// A `NicoliveState` of a `CommentLock` (B-11): [status], and a follow
/// restriction of [followSeconds] when given (an empty one for -1).
Uint8List _lock(int status, {int? followSeconds}) => _pb(
  (s) => s.bytes(
    5,
    _pb((l) {
      if (status != 0) l.integer(1, status);
      if (followSeconds == -1) {
        l.bytes(2, Uint8List(0));
      } else if (followSeconds != null) {
        l.bytes(2, _pb((r) => r.bytes(1, _pb((d) => d.integer(1, followSeconds)))));
      }
    }),
  ),
);

/// A `NicoliveState` of a `Marquee` (B-11): a display of an operator comment
/// unless [display] or [comment] is false.
Uint8List _marquee({
  String content = '運営コメント',
  String? name,
  Uint8List? modifier,
  String? link,
  int? duration,
  bool display = true,
  bool comment = true,
}) => _pb(
  (s) => s.bytes(
    4,
    _pb((m) {
      if (!display) return;
      m.bytes(
        1,
        _pb((d) {
          if (comment) {
            d.bytes(
              1,
              _pb((c) {
                c.string(1, content);
                if (name != null) c.string(2, name);
                if (modifier != null) c.bytes(3, modifier);
                if (link != null) c.string(4, link);
              }),
            );
          }
          if (duration != null) d.bytes(3, _pb((t) => t.integer(1, duration)));
        }),
      );
    }),
  ),
);

/// A `NicoliveState` of a `ProgramStatus` of [state] (B-11).
Uint8List _programStatus(int state) => _pb((s) => s.bytes(9, _pb((p) => p.integer(1, state))));

/// A `Gift` (B-11); a null field is left out.
Uint8List _gift({
  String? itemId = 'nicoko',
  int? giverId = 12345,
  String? giver = 'ギフト太郎',
  int? point = 500,
  String? message,
  String? name = 'ニコ子',
  int? rank,
}) => _pb((g) {
  if (itemId != null) g.string(1, itemId);
  if (giverId != null) g.integer(2, giverId);
  if (giver != null) g.string(3, giver);
  if (point != null) g.integer(4, point);
  if (message != null) g.string(5, message);
  if (name != null) g.string(6, name);
  if (rank != null) g.integer(7, rank);
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
  new({List<Object>? pages, this.view, this.window, _Tape? tape})
    : pages = pages ?? [_page()],
      _viewAnswers = tape?.views ?? _views,
      _windowAnswers = tape?.windows ?? _windows;

  final List<Object> pages;
  final Object? Function(LiveRequest request)? view;
  final Object? Function(LiveRequest request)? window;
  final Map<String, Uint8List> _viewAnswers;
  final Map<String, Uint8List> _windowAnswers;

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
        ? (view?.call(request) ?? _viewAnswers[request.url.queryParameters['at']] ?? _hold)
        : (window?.call(request) ?? _windowAnswers[request.url.path] ?? 404);
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
  DateTime? now,
}) {
  final server = http ?? _Http();
  final connector = seats ?? _Connector();
  final site = NiconicoSite(server, connector: connector.call, proxy: proxy);
  final connection = NiconicoDanmakuConnection(
    site: site,
    now: () => now ?? _recordedAt,
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

    test('an overflowed chat is a chat; ads, notices and the rest are not reported', () {
      expect(NiconicoDanmakuProtocol.message(_message(20, _chat(content: 'あふれ')))!.message, 'あふれ');
      // B-11: gifts (8) are reported now (see the B-11 group).
      for (final kind in [7, 9, 13, 17, 18, 19, 22, 23, 24, 25, 26, 99]) {
        final data = kind == 22 ? _pb((w) => w.bytes(1, _chat())) : _pb((w) => w.string(2, 'x'));
        expect(NiconicoDanmakuProtocol.message(_message(kind, data)), isNull, reason: 'NicoliveMessage.$kind');
      }
      // A oneof: the last field wins (B-11: a gift last is a gift).
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
      expect(NiconicoDanmakuProtocol.message(both)!.type, LiveMessageType.gift);
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
      // B-11: the program's end is a notice, and the next program is taken
      // without a reconnection (the connection stays joined).
      expect(setup.events.whereType<DanmakuReconnecting>(), isEmpty);
      final notices = _messages(setup.events).where((message) => message.type == LiveMessageType.notice).toList();
      expect(notices.map((notice) => notice.message), [NiconicoDanmakuProtocol.programEndedNotice]);
      expect(notices.single.messageId, isEmpty, reason: 'from the seat, which gives no id');
      expect(setup.events.whereType<DanmakuReady>(), hasLength(1));
      expect(setup.http.views.skip(4).first, 'now', reason: "the new seat's comment server from now");
      expect(setup.http.sent, hasLength(2), reason: 'the watch page read again');
      expect(setup.connection.isConnected, isTrue);
      await setup.connection.close();
    });

    test('a seat that ends for another reason is a reconnection', () async {
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
      setup.seats.handed.single.server('disconnect', {'reason': 'TAKEOVER'});
      await _until(() => setup.seats.handed.length == 2 && setup.http.views.length >= 6);
      final reconnecting = setup.events.whereType<DanmakuReconnecting>().single;
      expect(reconnecting.reason, DanmakuInterruption.disconnected);
      expect(reconnecting.detail, contains('TAKEOVER'));
      expect(setup.events.whereType<DanmakuReady>(), hasLength(2));
      expect(_messages(setup.events).where((message) => message.type == LiveMessageType.notice), isEmpty);
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
      // B-11: the end is a notice, then the connection ends, without a
      // reconnection in between.
      expect(_outline(setup.events), ['ready', 'message', 'closed:connectionFailed']);
      expect(_messages(setup.events).last.message, NiconicoDanmakuProtocol.programEndedNotice);
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
      // B-11: END_PROGRAM no longer reports a reconnection; another reason does.
      setup.seats.handed.single.server('disconnect', {'reason': 'TAKEOVER'});
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

  // M5.F, appendix B-11: the operator's comments, comment locks and the
  // program's end are system notices; gifts are gift messages. Recorded:
  // S08-marquee (operator comments), S09-ended (the program's end), S10-gift
  // (one gift); comment locks, and a gift's message and rank, were not seen
  // live, so they are synthetic.
  group('B-11: notices and gifts', () {
    final s08 = _Tape('S08-marquee');
    final s09 = _Tape('S09-ended');
    final s10 = _Tape('S10-gift');

    /// A broadcaster whose program ends: live, then offline (S03's page).
    const endingArgs = NiconicoDanmakuArgs(roomId: 'user/138383030', programId: 'lv351501491');
    LiveResponse offlinePage() => LiveResponse(
      status: 200,
      bytes: File('$_root/S03-watch-user-ended/body.html').readAsBytesSync(),
      url: Uri.parse('https://live.nicovideo.jp/watch/user/138383030'),
    );

    /// The operator comments of S08, read straight from the recording.
    List<String> recordedOperatorComments() => [
      for (final bytes in s08.windows.values)
        for (final message in NiconicoDanmakuProtocol.split(bytes))
          ?ProtoMessage.decode(message).message(4)?.message(4)?.message(1)?.message(1)?.string(1),
    ];

    void expectNotice(LiveMessage notice, String text, {String messageId = 'm1'}) {
      expect(notice.type, LiveMessageType.notice);
      expect(notice.data, LiveNoticeKind.system);
      expect(notice.message, text);
      expect(notice.messageId, messageId);
      expect(notice.userId, isEmpty);
      expect(notice.isLocal, isFalse);
    }

    test('S08: the operator comments are system notices, in order, with their ids and times', () {
      final texts = recordedOperatorComments();
      expect(texts, hasLength(4));
      expect(texts.first, startsWith('いつも一緒にいる為か'));
      final messages = s08.messages;
      final notices = [
        for (final message in messages)
          if (message.type == LiveMessageType.notice) message,
      ];
      expect(notices.map((notice) => notice.message), texts);
      for (final notice in notices) {
        expect(notice.data, LiveNoticeKind.system);
        expect(notice.userName, isEmpty, reason: 'no name in the recording');
        expect(notice.color, LiveMessageColor.white, reason: 'no modifier in the recording');
        expect(notice.messageId, isNotEmpty);
        expect(notice.sentAt, isNotNull);
      }
      expect(notices.map((notice) => notice.messageId).toSet(), hasLength(4));
      // Their times fall inside the windows that carried them, in order.
      for (var i = 1; i < notices.length; i++) {
        expect(notices[i].sentAt!.isBefore(notices[i - 1].sentAt!), isFalse);
      }
      expect(notices.first.sentAt!.isAfter(s08.recordedAt), isTrue);
      // The rest reads as before: four chats, viewer figures.
      expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(4));
      expect(messages.where((message) => message.type == LiveMessageType.online), hasLength(7));
      expect(messages.map((message) => message.type).toSet(), {
        LiveMessageType.chat,
        LiveMessageType.online,
        LiveMessageType.notice,
      });
    });

    test("S09: the program's end is one notice with its id and time; the windows after it hold only signals", () {
      final reader = NiconicoMessageReader();
      final read = <(LiveMessage?, bool)>[];
      final windows = s09.windows.values.toList();
      for (final bytes in windows) {
        for (final message in NiconicoDanmakuProtocol.split(bytes)) {
          read.add((reader.read(message), reader.endedProgram));
        }
      }
      final ends = [
        for (final (message, ended) in read)
          if (ended) message!,
      ];
      expect(ends, hasLength(1));
      final end = ends.single;
      expectNotice(end, NiconicoDanmakuProtocol.programEndedNotice, messageId: end.messageId);
      expect(end.messageId, isNotEmpty);
      expect(end.userName, isEmpty);
      expect(end.color, LiveMessageColor.white);
      // The end came 23 s after the recording started (the seat's
      // disconnect frame, 25 ms before it, is in the recording too).
      expect(end.sentAt!.difference(s09.recordedAt).inSeconds, inInclusiveRange(20, 30));
      final disconnect = File('$_root/danmaku/S09-ended/frames.jsonl').readAsLinesSync().where((line) {
        return line.contains('"text"');
      }).single;
      expect(jsonDecode(disconnect), containsPair('text', '{"type":"disconnect","data":{"reason":"END_PROGRAM"}}'));
      // Its window, and every window after it: nothing but the end.
      final endWindow = windows.indexWhere(
        (bytes) =>
            NiconicoDanmakuProtocol.split(bytes)
                .any((m) => NiconicoDanmakuProtocol.message(m)?.type == LiveMessageType.notice),
      );
      for (final bytes in windows.skip(endWindow + 1)) {
        expect(NiconicoDanmakuProtocol.split(bytes).map(NiconicoDanmakuProtocol.message).nonNulls, isEmpty);
      }
      // Before it, a named commenter's chats (raw user id, synthetic).
      final chats = [
        for (final (message, _) in read)
          if (message?.type == LiveMessageType.chat) message!,
      ];
      expect(chats, hasLength(3));
      for (final chat in chats) {
        expect(chat.userId, matches(RegExp(r'^[1-9][0-9]{4,6}$')), reason: 'raw_user_id, there is no hashed id');
        expect(chat.userName, matches(RegExp(r'^[a-z]{8}$')), reason: 'the scrubbed name');
      }
    });

    test(
      'operator comments: name, colour, trimmed text; no link; a cleared marquee or an empty comment is nothing',
      () {
        LiveMessage? read(Uint8List state) => NiconicoDanmakuProtocol.message(_state(state, meta: _meta(id: 'op1')));
        final full = read(
          _marquee(
            content: '  /info 延長しました  ',
            name: ' 放送者 ',
            modifier: _pb((w) => w.integer(3, 1)),
            link: 'https://example.com/x',
            duration: 15,
          ),
        )!;
        expectNotice(full, '/info 延長しました', messageId: 'op1');
        expect(full.userName, '放送者');
        expect(full.color, const LiveMessageColor(0xFF, 0x00, 0x00));
        expect(full.message, isNot(contains('example.com')), reason: 'the link is not kept');
        expect(full.sentAt, DateTime.fromMillisecondsSinceEpoch(1790541800000));
        final coloured = read(
          _marquee(
            modifier: _pb(
              (w) => w.bytes(
                4,
                _pb(
                  (c) => c
                    ..integer(1, 0x12)
                    ..integer(2, 0x34)
                    ..integer(3, 0x56),
                ),
              ),
            ),
          ),
        )!;
        expect('${coloured.color}', '#123456');
        expect(read(_marquee())!.color, LiveMessageColor.white);
        expect(read(_marquee())!.userName, isEmpty);
        for (final (reason, state) in [
          ('cleared (no display)', _marquee(display: false)),
          ('a display without a comment', _marquee(comment: false, duration: 15)),
          ('an empty comment', _marquee(content: '')),
          ('a blank comment', _marquee(content: ' \n ')),
          ('not protobuf', _pb((s) => s.bytes(4, [0xFF]))),
          ('a display that is not protobuf', _pb((s) => s.bytes(4, _pb((m) => m.bytes(1, [0xFF]))))),
        ]) {
          expect(read(state), isNull, reason: reason);
        }
      },
    );

    test('comment locks: only changes are notices, in the web player lines', () {
      final reader = NiconicoMessageReader();
      expect(reader.commentLock, NiconicoCommentLock.none);
      var n = 0;
      LiveMessage? read(Uint8List state) => reader.read(_state(state, meta: _meta(id: 'lock${++n}')));
      final steps = <(Uint8List, String?, NiconicoCommentLock)>[
        (_lock(0), null, NiconicoCommentLock.none),
        (_lock(2), null, NiconicoCommentLock.none),
        (
          _lock(2, followSeconds: 600),
          '【コメント制限】10分フォローを継続したユーザーに限定されます',
          const NiconicoCommentLock.followers(Duration(minutes: 10)),
        ),
        (_lock(2, followSeconds: 600), null, const NiconicoCommentLock.followers(Duration(minutes: 10))),
        (_lock(2, followSeconds: -1), '【コメント制限】フォロワーに限定されます', const NiconicoCommentLock.followers(Duration.zero)),
        (_lock(1), '現在コメントできません', NiconicoCommentLock.locked),
        (_lock(1), null, NiconicoCommentLock.locked),
        (_lock(9), null, NiconicoCommentLock.locked),
        (_lock(0), '评论锁定已解除', NiconicoCommentLock.none),
        (
          _lock(2, followSeconds: 5400),
          '【コメント制限】1時間30分フォローを継続したユーザーに限定されます',
          const NiconicoCommentLock.followers(Duration(minutes: 90)),
        ),
        (_lock(2), 'フォロワー限定コメントが解除されました', NiconicoCommentLock.none),
        (_lock(2, followSeconds: 0), '【コメント制限】フォロワーに限定されます', const NiconicoCommentLock.followers(Duration.zero)),
        (_lock(1), '現在コメントできません', NiconicoCommentLock.locked),
        (_lock(2, followSeconds: -30), '【コメント制限】フォロワーに限定されます', const NiconicoCommentLock.followers(Duration.zero)),
        (_lock(0), 'フォロワー限定コメントが解除されました', NiconicoCommentLock.none),
      ];
      for (final (index, (state, text, after)) in steps.indexed) {
        final notice = read(state);
        if (text == null) {
          expect(notice, isNull, reason: 'step $index');
        } else {
          expectNotice(notice!, text, messageId: 'lock${index + 1}');
          expect(notice.userName, isEmpty);
          expect(notice.color, LiveMessageColor.white);
          expect(notice.sentAt, DateTime.fromMillisecondsSinceEpoch(1790541800000));
        }
        expect(reader.commentLock, after, reason: 'step $index');
      }
      // Alone, a lock is a change from "everyone".
      expect(NiconicoDanmakuProtocol.message(_state(_lock(1)))!.message, '現在コメントできません');
      expect(NiconicoDanmakuProtocol.message(_state(_lock(0))), isNull);
      // A huge restriction is capped; a lock that is not protobuf is absent.
      final huge = NiconicoMessageReader()..read(_state(_lock(2, followSeconds: 1 << 50)));
      expect(huge.commentLock.followersOnly, const Duration(seconds: NiconicoDanmakuProtocol.maxFollowSeconds));
      final bad = NiconicoMessageReader();
      expect(bad.read(_state(_pb((s) => s.bytes(5, [0xFF])))), isNull);
      expect(bad.commentLock, NiconicoCommentLock.none);
      expect(
        bad.read(
          _state(
            _pb(
              (s) => s.bytes(
                5,
                _pb(
                  (l) => l
                    ..integer(1, 2)
                    ..bytes(2, [0xFF]),
                ),
              ),
            ),
          ),
        ),
        isNull,
      );
      expect(bad.commentLock, NiconicoCommentLock.none);
      // The value type.
      expect(
        const NiconicoCommentLock.followers(Duration(seconds: 3)),
        const NiconicoCommentLock.followers(Duration(seconds: 3)),
      );
      expect(const NiconicoCommentLock.followers(Duration.zero), isNot(NiconicoCommentLock.none));
      expect(NiconicoCommentLock.locked.isLocked, isTrue);
      expect('${const NiconicoCommentLock.followers(Duration(seconds: 3))}', 'NiconicoCommentLock.followers(3 s)');
      expect('${NiconicoCommentLock.locked}', 'NiconicoCommentLock.locked');
      expect('${NiconicoCommentLock.none}', 'NiconicoCommentLock.none');
    });

    test('follow durations as the web player writes them', () {
      for (final (seconds, text) in [
        (1, '0分'),
        (59, '0分'),
        (60, '1分'),
        (599, '9分'),
        (3599, '59分'),
        (3600, '1時間'),
        (3659, '1時間'),
        (3660, '1時間1分'),
        (5400, '1時間30分'),
        (86399, '23時間59分'),
        (86400, '1日'),
        (89999, '1日'),
        (90000, '1日と1時間'),
        (7 * 86400 + 5 * 3600 + 59 * 60, '7日と5時間'),
        (NiconicoDanmakuProtocol.maxFollowSeconds, '${NiconicoDanmakuProtocol.maxFollowSeconds ~/ 86400}日と6時間'),
      ]) {
        expect(NiconicoDanmakuProtocol.followDuration(seconds), text, reason: '$seconds s');
      }
    });

    test("the program's end: Ended only; the web player's order when a state holds several fields", () {
      final reader = NiconicoMessageReader();
      final end = reader.read(_state(_programStatus(1), meta: _meta(id: 'end1', nanos: 5000)))!;
      expectNotice(end, 'この番組は終了しました', messageId: 'end1');
      expect(end.sentAt, DateTime.fromMicrosecondsSinceEpoch(1790541800000005));
      expect(reader.endedProgram, isTrue);
      expect(reader.read(_state(_statistics(3))), isNotNull);
      expect(reader.endedProgram, isFalse, reason: 'only the message that said it');
      for (final state in [0, 2, -1]) {
        expect(reader.read(_state(_programStatus(state))), isNull, reason: 'state $state');
        expect(reader.endedProgram, isFalse);
      }
      final bare = NiconicoDanmakuProtocol.programEnded();
      expectNotice(bare, 'この番組は終了しました', messageId: '');
      expect(bare.sentAt, isNull);
      // Several fields: comment_lock, marquee, program_status, statistics.
      Uint8List all({int lock = 1}) =>
          Uint8List.fromList([..._statistics(7), ..._programStatus(1), ..._marquee(content: 'm'), ..._lock(lock)]);
      final several = NiconicoMessageReader();
      expect(several.read(_state(all()))!.message, '現在コメントできません');
      expect(several.read(_state(all()))!.message, 'm', reason: 'the lock did not change');
      expect(several.endedProgram, isFalse);
      expect(
        several
            .read(_state(Uint8List.fromList([..._statistics(7), ..._programStatus(1), ..._marquee(display: false)])))!
            .message,
        'この番組は終了しました',
      );
      final figure = several.read(
        _state(
          Uint8List.fromList([
            ..._statistics(7),
            ..._programStatus(0),
            ..._pb((s) => s.bytes(4, [0xFF])),
          ]),
        ),
      )!;
      expect((figure.data! as LiveAudienceUpdate).value, 7, reason: 'an unreadable marquee does not hide the figure');
    });

    test('S10: a recorded gift is a gift message with the shared text; its gift bar is not kept', () {
      final gifts = [
        for (final message in s10.messages)
          if (message.type == LiveMessageType.gift) message,
      ];
      expect(gifts, hasLength(1));
      final gift = gifts.single;
      expect(gift.data, const NiconicoGift(itemId: 'user15119555_26', name: 'ぶんぶんみゅーと', point: 100));
      expect(gift.userName, matches(RegExp(r'^[a-z]{9}$')), reason: 'the scrubbed giver');
      expect(gift.userId, matches(RegExp(r'^[1-9][0-9]{6,8}$')), reason: 'the scrubbed advertiser_user_id');
      // E05.5: the shared text (was the web player's sentence, which named
      // the giver a second time on the chat line).
      expect(gift.message, 'ぶんぶんみゅーと ×1');
      expect(
        (gift.gift?.id, gift.gift?.unitPrice, gift.gift?.totalValue, gift.gift?.unit, gift.gift?.free),
        ('user15119555_26', 100, 100, LiveGiftUnit.point, false),
      );
      expect(gift.messageId, isNotEmpty);
      expect(gift.sentAt, isNotNull);
      expect(gift.color, LiveMessageColor.white);
      // The recorded gift carries a gift bar update (8), which is not read.
      final raw = [
        for (final bytes in s10.windows.values)
          for (final message in NiconicoDanmakuProtocol.split(bytes))
            ?ProtoMessage.decode(message).message(2)?.message(8),
      ].single;
      expect(raw.message(8), isNotNull);
      expect(raw.integer(7), isNull, reason: 'no contribution rank in the recording');
      // The rest of the window reads as before.
      expect(s10.messages.map((message) => message.type).toSet(), {
        LiveMessageType.chat,
        LiveMessageType.online,
        LiveMessageType.gift,
      });
    });

    test('gifts: the giver, the shared text and the gift; none without an item or with negative points', () {
      final gift = NiconicoDanmakuProtocol.message(
        _message(
          8,
          _gift(message: ' ありがとう ', rank: 3),
          meta: _meta(id: 'g1', nanos: 250000000),
        ),
      )!;
      expect(gift.type, LiveMessageType.gift);
      expect(gift.userName, 'ギフト太郎');
      expect(gift.userId, '12345');
      expect(gift.message, 'ニコ子 ×1');
      expect(gift.messageId, 'g1');
      expect(gift.sentAt, DateTime.fromMillisecondsSinceEpoch(1790541800250));
      expect(gift.color, LiveMessageColor.white);
      expect(
        gift.data,
        const NiconicoGift(itemId: 'nicoko', name: 'ニコ子', point: 500, message: 'ありがとう', contributionRank: 3),
      );
      expect('${gift.data}', 'NiconicoGift(ニコ子, 500pt)');
      LiveMessage? read(Uint8List data) => NiconicoDanmakuProtocol.message(_message(8, data));
      final plain = read(_gift())!;
      expect(plain.message, 'ニコ子 ×1');
      expect((plain.data! as NiconicoGift).contributionRank, isNull);
      expect((plain.data! as NiconicoGift).message, isEmpty);
      expect((read(_gift(rank: 0))!.data! as NiconicoGift).contributionRank, 0);
      for (final point in [0, null]) {
        final free = read(_gift(point: point))!.gift!;
        expect((free.free, free.totalValue, free.tier), (true, 0, LiveGiftTier.normal), reason: '$point');
      }
      // Without a name the item id names it.
      expect(read(_gift(name: null))!.message, 'nicoko ×1');
      expect(read(_gift(name: null))!.gift?.displayName, 'nicoko');
      expect((read(_gift(itemId: null))!.data! as NiconicoGift).itemId, isEmpty);
      for (final (reason, id) in [('absent', null), ('zero', 0), ('negative', -5)]) {
        expect(read(_gift(giverId: id))!.userId, isEmpty, reason: reason);
      }
      expect(read(_gift(giver: null))!.userName, isEmpty);
      expect(read(_gift(point: -1)), isNull, reason: 'the web player drops negative points');
      expect(read(_gift(itemId: null, name: null)), isNull, reason: 'no item');
      expect(
        read(_gift(itemId: ' ', name: ' ')),
        isNull,
        reason: 'blank item',
      );
      expect(() => read(Uint8List.fromList([0x0A, 0x05, 0x01])), throwsFormatException);
      expect(
        const NiconicoGift(itemId: 'a', name: 'b', point: 1),
        isNot(const NiconicoGift(itemId: 'a', name: 'b', point: 2)),
      );
      expect(
        const NiconicoGift(itemId: 'a', name: 'b', point: 1).hashCode,
        const NiconicoGift(itemId: 'a', name: 'b', point: 1).hashCode,
      );
    });

    test('S08 through the connection: the operator comments among the chats; the snapshot is never read', () async {
      final setup = _setup(
        http: _Http(
          tape: s08,
          pages: [_page(program: 'lv351501141')],
        ),
        seats: _Connector([_Channel(_seatFrames(view: s08.view))]),
        now: s08.recordedAt,
      );
      await setup.connection.connect(_args);
      await _until(() => setup.http.views.length == s08.views.length + 1, reason: 'every view, then the held one');
      await _until(() => setup.http.open_ == 1, reason: 'every window read');
      final messages = _messages(setup.events);
      expect(
        messages.where((message) => message.type == LiveMessageType.notice).map((notice) => notice.message),
        recordedOperatorComments(),
      );
      expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(4));
      // In the order of the windows: each notice where the recording has it.
      expect(
        [
          for (final message in messages)
            if (message.type != LiveMessageType.online) message.type,
        ],
        [
          for (final message in s08.messages)
            if (message.type != LiveMessageType.online) message.type,
        ],
      );
      expect(setup.http.opened.where((request) => request.url.path.contains('/snapshot/')), isEmpty);
      expect(_kinds(setup.events).where((kind) => kind != 'message'), ['ready']);
      await setup.connection.close();
      await _until(() => setup.http.open_ == 0);
    });

    test(
      "S09 through the connection: the program's end, once, then the connection ends without a reconnection",
      () async {
        final setup = _setup(
          http: _Http(
            tape: s09,
            pages: [
              _page(user: '138383030', program: 'lv351501491'),
              offlinePage(),
            ],
          ),
          seats: _Connector([_Channel(_seatFrames(view: s09.view))]),
          now: s09.recordedAt,
        );
        await setup.connection.connect(endingArgs);
        await _until(() => setup.events.last is DanmakuClosed);
        expect(_outline(setup.events), ['ready', 'message', 'closed:connectionFailed']);
        expect((setup.events.last as DanmakuClosed).detail, startsWith('StreamUnavailable(niconico'));
        final messages = _messages(setup.events);
        final notices = [
          for (final message in messages)
            if (message.type == LiveMessageType.notice) message,
        ];
        expect(notices, hasLength(1));
        expect(notices.single, same(messages.last), reason: 'nothing after the end');
        expectNotice(notices.single, NiconicoDanmakuProtocol.programEndedNotice, messageId: notices.single.messageId);
        expect(notices.single.messageId, isNotEmpty, reason: "the window's, which came first here");
        expect(messages.where((message) => message.type == LiveMessageType.chat), hasLength(3));
        // Every request of the seat is given up at the end (the replay runs
        // ahead of the recording, so later views may have been asked); the
        // seat is closed.
        expect(setup.http.windows.take(2), s09.windows.keys.take(2));
        await _until(() => setup.http.open_ == 0);
        expect(setup.http.opened.every((request) => request.cancel!.isCancelled), isTrue);
        expect(setup.seats.handed.single.closed, isTrue);
        expect(setup.http.sent, hasLength(2), reason: 'the watch page read again');
        // The seat's own END_PROGRAM, 25 ms later when recorded, adds nothing.
        setup.seats.handed.single.server('disconnect', {'reason': 'END_PROGRAM'});
        await _wait(const Duration(milliseconds: 20));
        expect(_messages(setup.events), hasLength(messages.length));
        await _until(() => setup.http.open_ == 0);
      },
    );

    test("the seat's END_PROGRAM first: one notice, the window's end after it is dropped", () async {
      final late = _Manual();
      final setup = _setup(
        http: _Http(
          tape: s09,
          window: (request) => request.url.path == s09.windows.keys.elementAt(1) ? late : null,
          pages: [
            _page(program: 'lv351501491'),
            _page(program: 'lv351501999'),
          ],
        ),
        seats: _Connector([_Channel(_seatFrames(view: s09.view))]),
        now: s09.recordedAt,
      );
      await setup.connection.connect(_args);
      await _until(() => late.controller.hasListener);
      setup.seats.handed.first.server('disconnect', {'reason': 'END_PROGRAM'});
      await _until(() => setup.seats.handed.length == 2, reason: "the next program's seat");
      late.controller.add(_delimit([NiconicoDanmakuProtocol.split(s09.windows.values.elementAt(1)).first]));
      await _wait(const Duration(milliseconds: 20));
      final notices = _messages(setup.events).where((message) => message.type == LiveMessageType.notice).toList();
      expect(notices.map((notice) => notice.message), [NiconicoDanmakuProtocol.programEndedNotice]);
      expect(notices.single.messageId, isEmpty);
      expect(setup.events.whereType<DanmakuReconnecting>(), isEmpty);
      expect(setup.connection.isConnected, isTrue);
      await setup.connection.close();
      unawaited(late.controller.close());
    });

    test('an end right after an end (the watch page still showed the ended program) is a failure', () async {
      final stale = _Channel([
        for (final frame in _seatFrames(messageServer: false)) frame,
        jsonEncode({
          'type': 'disconnect',
          'data': {'reason': 'END_PROGRAM'},
        }),
      ]);
      final setup = _setup(
        http: _Http(
          pages: [
            _page(user: '138383030'),
            _page(user: '138383030'),
            offlinePage(),
          ],
        ),
        seats: _Connector([_Channel(), stale]),
      );
      await setup.connection.connect(endingArgs);
      await _until(() => setup.http.views.length == 4);
      setup.seats.handed.first.server('disconnect', {'reason': 'END_PROGRAM'});
      await _until(() => setup.events.last is DanmakuClosed);
      expect(_outline(setup.events), ['ready', 'message', 'reconnecting:disconnected', 'closed:connectionFailed']);
      expect(setup.events.whereType<DanmakuReconnecting>().single.detail, contains('END_PROGRAM'));
      expect(_messages(setup.events).where((message) => message.type == LiveMessageType.notice).map((m) => m.message), [
        NiconicoDanmakuProtocol.programEndedNotice,
      ], reason: 'reported once');
      expect(setup.seats.handed, hasLength(2));
      expect(setup.http.sent, hasLength(3));
    });

    test('comment locks through the connection: changes only, across windows and seats', () async {
      final first = _windows.keys.first;
      final second = _windows.keys.elementAt(1);
      Uint8List lock(String id, Uint8List state) => _state(state, meta: _meta(id: id));
      final setup = _setup(
        http: _Http(
          window: (request) => switch (request.url.path) {
            final path when path == first => _delimit([
              lock('l1', _lock(2, followSeconds: 600)),
              lock('l2', _lock(2, followSeconds: 600)),
              _state(_statistics(10)),
              lock('l3', _lock(1)),
            ]),
            final path when path == second => _delimit([
              lock('l4', _lock(1)),
              lock('l5', _lock(0)),
              lock('l6', _lock(0)),
            ]),
            _ => _hold,
          },
          pages: [_page(), _page()],
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => _messages(setup.events).where((m) => m.type == LiveMessageType.notice).length == 3);
      // Another seat (taken over) reads the window under way again, as it
      // does for chats: the same ids come again, and the gate drops them.
      setup.seats.handed.single.server('disconnect', {'reason': 'TAKEOVER'});
      await _until(() => setup.seats.handed.length == 2 && setup.http.windows.length >= 6);
      await _until(() => _messages(setup.events).where((m) => m.type == LiveMessageType.notice).length == 6);
      await _wait(const Duration(milliseconds: 20));
      final notices = [
        for (final message in _messages(setup.events))
          if (message.type == LiveMessageType.notice) message,
      ];
      const once = [('l1', '【コメント制限】10分フォローを継続したユーザーに限定されます'), ('l3', '現在コメントできません'), ('l5', '评论锁定已解除')];
      expect([for (final notice in notices) (notice.messageId, notice.message)], [...once, ...once]);
      final gate = DanmakuMessageGate();
      expect(
        [
          for (final notice in notices)
            if (gate.accepts(notice, now: notice.sentAt)) notice.messageId,
        ],
        ['l1', 'l3', 'l5'],
      );
      for (final notice in notices) {
        expect(notice.data, LiveNoticeKind.system);
      }
      await setup.connection.close();
    });

    test('a gift through the connection is a gift message', () async {
      final setup = _setup(
        http: _Http(
          window: (request) => request.url.path == _windows.keys.first
              ? _delimit([_message(8, _gift(), meta: _meta(id: 'gift1')), _message(1, _chat(content: 'after'))])
              : _hold,
        ),
      );
      await setup.connection.connect(_args);
      await _until(() => _messages(setup.events).length == 2);
      final gift = _messages(setup.events).first;
      expect(gift.type, LiveMessageType.gift);
      expect(gift.messageId, 'gift1');
      expect(gift.data, isA<NiconicoGift>());
      expect(_messages(setup.events).last.message, 'after');
      await setup.connection.close();
    });
  });
}
