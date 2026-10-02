// Baidu Live danmaku (docs/D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/record.md): the message-list
// decoder against fixtures/baidulive/danmaku/web_expected.py (a port of the
// PC room page's reading) for the recorded lists (S03-live-chat,
// S04-live-online, S05-live-gift, S06-ended) and the synthetic cases
// (S07-synthetic); the polling connection replayed over the recordings on a
// virtual clock, and over scripted and local-server lists.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/baidulive/danmaku';

Object? _json(String path) => jsonDecode(File('$_root/$path').readAsStringSync());

Map<String, Object?> _meta(String name) => _json('$name/meta.json')! as Map<String, Object?>;

/// The recorded exchanges of a sample, in order.
List<Map<String, Object?>> _frames(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

/// web_expected.py's output for a sample.
Map<String, Object?> _expected(String name) =>
    (_json('$name/expected.json')! as Map<String, Object?>)['value']! as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) => (value! as List<Object?>).cast<Map<String, Object?>>();

/// The arguments room entry makes of the lists a recorded sample was polled
/// with (the recorder asked them over http, as the room command wrote them;
/// the connection asks over https, as the page does).
BaiduLiveDanmakuArgs _recordedArgs(String name) {
  final keys = _meta(name)['danmakuKeys']! as Map<String, Object?>;
  final args = BaiduLiveApi.danmakuArgs({
    'chat_msg_hls_url': keys['chatList'],
    'reliable_msg_hls_url': keys['reliableList'],
    'host_msg_hls_url': keys['hostList'],
    'msg_hls_pull_internal_in_second': keys['pullIntervalSeconds'],
  }, keys['roomId']! as String)!;
  expect(args.chatList.scheme, 'https');
  return args;
}

/// A segment frame's body as the transport hands it over: inflated when it
/// was served with `Content-Encoding: gzip` (as `IoLiveHttp` does).
List<int> _served(Map<String, Object?> frame) {
  final bytes = base64.decode(frame['b64']! as String);
  return frame['encoding'] == 'gzip' ? gzip.decode(bytes) : bytes;
}

/// A message as expected.json writes it.
Map<String, Object?> _project(LiveMessage message) {
  final sentAt = message.sentAt == null ? null : message.sentAt!.millisecondsSinceEpoch ~/ 1000;
  return switch (message.type) {
    LiveMessageType.online => {'type': 'online', 'online': (message.data! as LiveAudienceUpdate).value},
    LiveMessageType.gift => {
      'type': 'gift',
      'userName': message.userName,
      'userId': message.userId,
      'message': message.message,
      'messageId': message.messageId,
      'sentAt': sentAt,
      'gift': _gift(message.data! as BaiduLiveGift),
    },
    _ => {
      'type': message.type.name,
      'userName': message.userName,
      'userId': message.userId,
      'message': message.message,
      'messageId': message.messageId,
      'sentAt': sentAt,
    },
  };
}

Map<String, Object?> _gift(BaiduLiveGift gift) => {
  'id': gift.id,
  'name': gift.name,
  'count': gift.count,
  'free': gift.free,
  'icon': gift.icon?.toString(),
};

/// A segment decoded as expected.json writes it.
Map<String, Object?> _decoded(List<int> bytes, String roomId) {
  try {
    final segment = BaiduLiveDanmakuProtocol.segment(bytes, roomId: roomId);
    return {
      'messages': [for (final message in segment.messages) _project(message)],
      'ended': segment.ended,
    };
  } on FormatException {
    return {'throws': 'FormatException'};
  }
}

/// A playlist parsed as expected.json writes it.
Map<String, Object?> _parsed(String text, Uri url) {
  try {
    final playlist = BaiduLiveDanmakuProtocol.playlist(text, url);
    return {
      'segments': [for (final segment in playlist.segments) segment.path],
      'mediaSequence': playlist.mediaSequence,
    };
  } on FormatException {
    return {'throws': 'FormatException'};
  }
}

const _room = '11500000001';
const _base = 'http://liveshowstatic.baidu.com/v1/liveshowstatic';
const _auth = 'authorization=bce-auth-v1/0123456789abcdef0123456789abcdef/2026-09-30T12:00:00Z/15768000/host/sig';
final Uri _chatList = Uri.parse('$_base/live_11500000001.m3u8?$_auth');
final Uri _reliableList = Uri.parse('$_base/live_11500000003.m3u8?$_auth');
final Uri _hostList = Uri.parse('$_base/live_11500000002.m3u8?$_auth');

/// Synthetic arguments; the signature runs out 182.5 days after
/// 2026-09-30 12:00 UTC, or at [expiresAt].
BaiduLiveDanmakuArgs _args({
  bool reliable = true,
  bool host = true,
  Duration interval = const Duration(seconds: 5),
  DateTime? expiresAt,
}) => BaiduLiveDanmakuArgs(
  roomId: _room,
  chatList: _chatList,
  reliableList: reliable ? _reliableList : null,
  hostList: host ? _hostList : null,
  pullInterval: interval,
  expiresAt: expiresAt ?? BaiduLiveApi.signatureExpiry(_chatList),
);

/// When the synthetic lists were "recorded".
final DateTime _recordedAt = DateTime.utc(2026, 9, 30, 12);

/// A playlist naming segments [names] (`<name>.ts`), as the lists write it.
String _playlist(List<String> names) => [
  '#EXTM3U',
  '#EXT-X-VERSION:3',
  '#EXT-X-TARGETDURATION:15',
  '#EXT-X-MEDIA-SEQUENCE:0',
  for (final name in names) ...[
    '#EXT-X-PROGRAM-DATE-TIME:2026-09-30T20:00:00.000000000+08:00',
    '#EXTINF:1.000,',
    '/v1/liveshowstatic/$name.ts?authorization=bce-auth-v1/x/2026-09-30T12:00:00Z/604800/host/$name',
  ],
].join('\n');

/// A list message whose payload is [inner].
Map<String, Object?> _message(Map<String, Object?> inner, {int msgid = 1790770000000001}) => {
  'category': 4,
  'content': jsonEncode({'text': jsonEncode(inner)}),
  'create_time': 1790770000,
  'from_user': 100000001,
  'msgid': msgid,
  'type': 0,
};

Map<String, Object?> _chat(String text, {String roomId = _room}) => {
  'type': '0',
  'message_type': '0',
  'content': text,
  'message_body': {
    'txt': {'word': text},
  },
  'name': '观众',
  'uid': '2000000001',
  'room_id': roomId,
};

/// A segment body (gzipped unless [plain]) holding [payloads]: chat lines
/// (text) or payload objects.
List<int> _segment(List<Object> payloads, {bool plain = false}) {
  final body = utf8.encode(
    jsonEncode({
      'list': [
        {
          'messages': [
            for (final (index, payload) in payloads.indexed)
              _message(
                payload is String ? _chat(payload) : payload as Map<String, Object?>,
                msgid: 1790770000000100 + index,
              ),
          ],
        },
      ],
    }),
  );
  return plain ? body : gzip.encode(body);
}

LiveResponse _ok(LiveRequest request, Object body) =>
    LiveResponse(status: 200, bytes: body is String ? utf8.encode(body) : body as List<int>, url: request.url);

LiveResponse _status(LiveRequest request, int status) =>
    LiveResponse(status: status, bytes: utf8.encode('{"code":"NoSuchKey"}'), url: request.url);

/// Answers by path, with the virtual time (ms) since `connect`; a request
/// at or after [stopAt] waits for its cancellation and ends the session.
final class _Lists implements LiveHttp {
  new(this.answer, {this.stopAt = 60000});

  final FutureOr<LiveResponse> Function(LiveRequest request, String path, int calls) answer;
  final int stopAt;
  final List<LiveRequest> requests = [];
  final Map<String, int> _calls = {};
  final Completer<void> exhausted = Completer();
  int clock = 0;
  void Function(LiveRequest request)? onRequest;

  /// The paths asked, in order.
  List<String> get paths => [for (final request in requests) request.url.path];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    onRequest?.call(request);
    if (clock >= stopAt) {
      if (!exhausted.isCompleted) exhausted.complete();
      await request.cancel?.whenCancelled;
      throw TransportFailure(request.site, TransportReason.cancelled);
    }
    final path = request.url.path;
    final calls = _calls[path] = (_calls[path] ?? 0) + 1;
    return await answer(request, path, calls);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

/// One session over [http] on a virtual clock: every wait fires at once
/// and moves the clock on. It ends when [http] stops answering, the
/// connection closes or `connect` throws. The trace has `{wait}`, `{get}`
/// and the events.
Future<List<Object?>> _session(
  _Lists http, {
  BaiduLiveDanmakuArgs? args,
  DateTime Function()? now,
  List<DanmakuStatus>? statuses,
}) async {
  final trace = <Object?>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  http.onRequest = (request) => trace.add({'get': request.url.path.split('/').last});
  unawaited(http.exhausted.future.then((_) => finish()));
  final connection = BaiduLiveDanmakuConnection(http: http, now: now ?? () => _recordedAt);
  final subscription = connection.events.listen((event) {
    trace.add(_shown(event));
    statuses?.add(connection.status);
    if (event is DanmakuClosed) finish();
  });
  late final Future<void> connecting;
  await runZoned(
    () async {
      connecting = connection.connect(args ?? _args()).catchError((Object error) {
        trace.add({'threw': '$error'});
        finish();
      });
      await done.future;
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        trace.add({'wait': duration.inMilliseconds});
        http.clock += duration.inMilliseconds;
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
  await connection.close();
  await connecting;
  statuses?.add(connection.status);
  await subscription.cancel();
  return trace;
}

/// An event as the tests compare it: a message projected, others as text.
Object _shown(DanmakuEvent event) => event is DanmakuReceived ? _project(event.message) : '$event';

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// A recorded sample as lists: each playlist request gets the list's last
/// poll at or before the virtual time (from the first chat poll on), each
/// segment its recorded fetch. [served] gets every playlist answered with
/// 200 (list, the segment paths) and every segment answered (path, body).
_Lists _replay(String name, {List<(String, Object)>? served}) {
  final frames = _frames(name);
  final args = _recordedArgs(name);
  final lists = {args.chatList.path: 'chat', args.reliableList!.path: 'reliable', args.hostList!.path: 'host'};
  final polls = <String, List<Map<String, Object?>>>{};
  final segments = <String, Map<String, Object?>>{};
  final texts = <String, String>{};
  for (final frame in frames) {
    final list = frame['list']! as String;
    if (frame['kind'] == 'playlist') {
      if (frame['text'] case final String text when frame['status'] == 200) texts[list] = text;
      polls.putIfAbsent(list, () => []).add({...frame, if (frame['same'] == true) 'text': texts[list]});
    } else {
      segments.putIfAbsent(Uri.parse(frame['url']! as String).path, () => frame);
    }
  }
  final start = polls['chat']!.first['t']! as int;
  final end = frames.map((frame) => frame['t']! as int).reduce((a, b) => a > b ? a : b);
  late final _Lists http;
  return http = _Lists(stopAt: end - start, (request, path, _) {
    final Map<String, Object?> frame;
    if (lists[path] case final list?) {
      final at = start + http.clock;
      frame = polls[list]!.lastWhere((poll) => (poll['t']! as int) <= at, orElse: () => polls[list]!.first);
    } else {
      frame = segments[path] ?? (throw StateError('no recorded segment $path'));
    }
    if (frame['error'] != null) throw TransportFailure(request.site, TransportReason.timeout, 'recorded');
    final status = frame['status']! as int;
    if (status != 200) return LiveResponse(status: status, bytes: utf8.encode('${frame['text']}'), url: request.url);
    if (frame['kind'] == 'playlist') {
      served?.add((lists[path]!, frame['text']!));
      return _ok(request, frame['text']! as String);
    }
    served?.add((path, frame));
    return _ok(request, _served(frame));
  });
}

void main() {
  group('protocol', () {
    test('timing: 10 s requests, 3 tries 2 s apart to join, 1-2-4-8 s backoff, 8 retries, skipped polls', () {
      expect(BaiduLiveDanmakuProtocol.requestTimeout, const Duration(seconds: 10));
      expect(BaiduLiveDanmakuProtocol.startAttempts, 3);
      expect(BaiduLiveDanmakuProtocol.startRetryDelay, const Duration(seconds: 2));
      expect(BaiduLiveDanmakuProtocol.maxFailures, 8);
      expect([for (var i = 1; i <= 9; i++) BaiduLiveDanmakuProtocol.backoff(i).inSeconds], [1, 2, 4, 8, 8, 8, 8, 8, 8]);
      expect([for (var i = 1; i <= 7; i++) BaiduLiveDanmakuProtocol.skippedPolls(i)], [1, 2, 4, 8, 12, 12, 12]);
      expect(BaiduLiveDanmakuProtocol.segmentAttempts, 3);
      expect(BaiduLiveDanmakuProtocol.rememberedSegments, 256);
      expect(BaiduLiveDanmakuProtocol.endedDetail, 'Broadcast ended');
    });

    test("headers: the website's UA, Origin and the room page as Referer", () {
      expect(BaiduLiveDanmakuProtocol.headers('11548522172'), {
        'user-agent': BaiduLiveApi.userAgent,
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://live.baidu.com',
        'referer': 'https://live.baidu.com/m/room/11548522172',
      });
    });

    test('segments are told apart by path; the media sequence stays 0 in every recorded playlist', () {
      final url = Uri.parse('$_base/1_2.ts?authorization=a');
      expect(BaiduLiveDanmakuProtocol.segmentKey(url), '/v1/liveshowstatic/1_2.ts');
      expect(BaiduLiveDanmakuProtocol.segmentKey(url.replace(query: 'authorization=b')), '/v1/liveshowstatic/1_2.ts');
      for (final name in ['S03-live-chat', 'S04-live-online', 'S05-live-gift', 'S06-ended']) {
        final sequences = {for (final playlist in _list(_expected(name)['playlists'])) playlist['mediaSequence']};
        expect(sequences, {0}, reason: name);
      }
    });

    test('the audience message and the gift', () {
      final online = BaiduLiveDanmakuProtocol.audience(147144);
      expect(online.type, LiveMessageType.online);
      expect(
        online.data,
        isA<LiveAudienceUpdate>().having((update) => update.kind, 'kind', LiveAudienceMetricKind.onlineViewers),
      );
      expect((online.data! as LiveAudienceUpdate).value, 147144);
      const gift = BaiduLiveGift(id: '11138', name: '拍拍', count: 2, free: true);
      expect(gift, const BaiduLiveGift(id: '11138', name: '拍拍', count: 2, free: true));
      expect(gift.hashCode, const BaiduLiveGift(id: '11138', name: '拍拍', count: 2, free: true).hashCode);
      expect(gift == const BaiduLiveGift(id: '11138', name: '拍拍', count: 3, free: true), isFalse);
      expect('$gift', 'BaiduLiveGift(拍拍 ×2)');
    });

    test('a chat line: every field (S03); a gift (S05)', () {
      final frame = _frames('S03-live-chat').firstWhere(
        (frame) => frame['kind'] == 'segment' && _decoded(_served(frame), '11548522172').toString().contains('房门对墙角'),
      );
      final line = BaiduLiveDanmakuProtocol.segment(
        _served(frame),
        roomId: '11548522172',
      ).messages.singleWhere((message) => message.message.startsWith('房门'));
      expect(line.type, LiveMessageType.chat);
      expect(line.message, '房门对墙角怎么化解');
      expect(line.userName, 'tpzhrwsww3500');
      expect(line.userId, '6125842360');
      expect(line.messageId, '1790771030447678');
      expect(line.sentAt, DateTime.fromMillisecondsSinceEpoch(1790771030 * 1000));
      expect(line.sentAt!.isUtc, isFalse);
      expect(line.color, LiveMessageColor.white);
      expect([line.userLevel, line.fansName, line.fansLevel], ['', '', '']);
      expect(line.isLocal, isFalse);
      final gifts = [
        for (final frame in _frames('S05-live-gift'))
          if (frame['kind'] == 'segment' && frame['status'] == 200)
            ...BaiduLiveDanmakuProtocol.segment(
              _served(frame),
              roomId: '11542685348',
            ).messages.where((message) => message.type == LiveMessageType.gift),
      ];
      expect(gifts, hasLength(3));
      expect(gifts.first.message, '拍拍 ×1');
      expect(
        gifts.first.data,
        BaiduLiveGift(
          id: '11138',
          name: '拍拍',
          count: 1,
          free: true,
          icon: Uri.parse('https://internal-amis-res.cdn.bcebos.com/images/2019-10/1572240170823/f00d908f8926.png'),
        ),
      );
    });
  });

  group('recorded lists against the page script (web_expected.py)', () {
    for (final (name, room, counts) in [
      ('S03-live-chat', '11548522172', {'chat': 17, 'online': 6}),
      ('S04-live-online', '11588562681', {'online': 105}),
      ('S05-live-gift', '11542685348', {'chat': 3, 'online': 7, 'gift': 3}),
      ('S06-ended', '11583715413', <String, int>{}),
    ]) {
      test('$name: every playlist and segment', () {
        final expected = _expected(name);
        final frames = _frames(name);
        final playlists = _list(expected['playlists']);
        final segments = _list(expected['segments']);
        expect(playlists, isNotEmpty);
        for (final playlist in playlists) {
          final frame = frames[playlist['frame']! as int];
          final parsed = _parsed(frame['text']! as String, Uri.parse(frame['url']! as String));
          expect(parsed, {'segments': playlist['segments'], 'mediaSequence': playlist['mediaSequence']});
        }
        final found = <String, int>{};
        for (final segment in segments) {
          final frame = frames[segment['frame']! as int];
          final decoded = _decoded(_served(frame), room);
          expect(decoded, {'messages': segment['messages'], 'ended': segment['ended']}, reason: '${segment['frame']}');
          for (final message in _list(decoded['messages'])) {
            found.update(message['type']! as String, (count) => count + 1, ifAbsent: () => 1);
          }
          // The segment as served without Content-Encoding (still gzip).
          expect(_decoded(base64.decode(frame['b64']! as String), room), decoded);
        }
        expect(found, counts);
        expect(segments.where((segment) => segment['ended'] == true), isEmpty, reason: 'no 102 was recorded');
      });
    }

    test('S06-ended: an expired segment answers 403; the last notices of an ended room name other rooms', () {
      final frames = _frames('S06-ended');
      final refused = frames.singleWhere((frame) => frame['kind'] == 'segment' && frame['status'] == 403);
      expect(refused['text'], contains('RequestExpired'));
      final notices = [
        for (final frame in frames)
          if (frame['kind'] == 'segment' && frame['status'] == 200) utf8.decode(_served(frame)),
      ];
      expect(notices, hasLength(3));
      for (final notice in notices) {
        expect(notice, contains('mix_room_close'));
        expect(notice, isNot(contains('"room_ids":[11583715413')));
      }
    });
  });

  group('synthetic cases (S07-synthetic) against the page script', () {
    final cases = _json('S07-synthetic/cases.json')! as Map<String, Object?>;
    final expected = _expected('S07-synthetic');
    final segments = expected['segments']! as Map<String, Object?>;
    final playlists = expected['playlists']! as Map<String, Object?>;

    test('every case has an expected output', () {
      expect(segments.keys, [for (final entry in _list(cases['segments'])) entry['name']]);
      expect(playlists.keys, [for (final entry in _list(cases['playlists'])) entry['name']]);
    });

    for (final entry in _list(cases['segments'])) {
      test('segment: ${entry['name']}', () {
        final bytes = base64.decode(entry['b64']! as String);
        expect(_decoded(bytes, entry['roomId']! as String), segments[entry['name']]);
      });
    }

    for (final entry in _list(cases['playlists'])) {
      test('playlist: ${entry['name']}', () {
        expect(_parsed(entry['text']! as String, Uri.parse(entry['url']! as String)), playlists[entry['name']]);
      });
    }

    test('a segment gzipped with Content-Encoding reaches the decoder inflated; one without, still gzipped', () {
      final plain = _segment(['你好'], plain: true);
      expect(_decoded(plain, _room), _decoded(gzip.encode(plain), _room));
      expect(BaiduLiveDanmakuProtocol.inflate(gzip.encode(gzip.encode(plain))), plain);
      expect(BaiduLiveDanmakuProtocol.inflate(plain), same(plain));
      expect(() => BaiduLiveDanmakuProtocol.inflate([0x1f, 0x8b, 1, 2, 3]), throwsFormatException);
    });
  });

  group('sessions over the recordings (virtual clock)', () {
    for (final name in ['S03-live-chat', 'S04-live-online', 'S05-live-gift']) {
      test('$name: joins, skips the history, reports each new segment once, in order', () async {
        final served = <(String, Object)>[];
        final http = _replay(name, served: served);
        final args = _recordedArgs(name);
        final expected = _expected(name);
        final byPath = {
          for (final segment in _list(expected['segments']))
            Uri.parse(_frames(name)[segment['frame']! as int]['url']! as String).path: segment,
        };
        final statuses = <DanmakuStatus>[];
        final trace = await _session(
          http,
          args: args,
          now: () => DateTime.parse(_meta(name)['capturedAt']! as String),
          statuses: statuses,
        );

        // What the served answers make: the first playlist of the chat and
        // reliable lists is history; every path listed after it is fetched
        // once, and its messages come in the order the playlists named them.
        final seen = <String, Set<String>>{};
        final wanted = <Object?>[];
        for (final (list, answer) in served) {
          if (answer is! String) continue;
          final paths = BaiduLiveDanmakuProtocol.playlist(answer, args.chatList).segments.map((url) => url.path);
          final known = seen[list];
          if (known == null) {
            seen[list] = {...paths};
            continue;
          }
          for (final path in paths) {
            if (!known.add(path)) continue;
            final segment = byPath[path];
            if (segment != null) wanted.addAll(_list(segment['messages']));
          }
        }
        final messages = [
          for (final entry in trace)
            if (entry is Map && entry.containsKey('type')) entry,
        ];
        expect(messages, wanted);
        expect(messages, isNotEmpty);
        expect(trace.first, {'get': args.chatList.path.split('/').last});
        expect(trace[1], 'DanmakuReady()');
        // History is never fetched: the first chat answer's segments.
        final history = BaiduLiveDanmakuProtocol.playlist(served.first.$2 as String, args.chatList).segments;
        for (final segment in history) {
          expect(http.paths, isNot(contains(segment.path)));
        }
        // Each segment asked at most three times (a recorded timeout), a
        // served one once.
        final asked = <String, int>{};
        for (final path in http.paths.where((path) => path.endsWith('.ts'))) {
          asked.update(path, (count) => count + 1, ifAbsent: () => 1);
        }
        expect(asked.values.every((count) => count <= BaiduLiveDanmakuProtocol.segmentAttempts), isTrue);
        for (final (path, _) in served.where((entry) => entry.$2 is Map)) {
          expect(asked[path], 1, reason: path);
        }
        // The waits: 5 s between rounds, 1-2-4-8 s after recorded timeouts.
        final waits = {
          for (final entry in trace)
            if (entry is Map && entry['wait'] != null) entry['wait'],
        };
        expect(waits.difference({5000, 1000, 2000, 4000, 8000}), isEmpty);
        // The host list (404 throughout) is asked about once a minute.
        final host = http.paths.where((path) => path == args.hostList!.path).length;
        final rounds = http.paths.where((path) => path == args.chatList.path).length;
        expect(rounds, greaterThan(70));
        expect(host, lessThan(rounds ~/ 5));
        expect(trace.whereType<String>().where((event) => event.startsWith('DanmakuClosed')), isEmpty);
        expect(statuses.last, DanmakuStatus.idle);
        for (final request in http.requests) {
          expect(request.site, 'baidulive');
          expect(request.timeout, const Duration(seconds: 10));
          expect(request.headers, BaiduLiveDanmakuProtocol.headers(args.roomId));
          expect(request.cancel, isNotNull);
        }
      });
    }
  });

  group('connection', () {
    test('no heartbeat; registers in DanmakuRegistry under baidulive; takes BaiduLiveDanmakuArgs only', () async {
      final connection = BaiduLiveDanmakuConnection(http: _Lists((request, path, calls) => _status(request, 404)));
      expect(connection.heartbeatInterval, Duration.zero);
      connection.heartbeat();
      final registry = DanmakuRegistry({SiteIds.baiduLive: () => connection});
      expect(registry.supports('baidulive'), isTrue);
      expect(registry.connectionFor('baidulive'), same(connection));
      await expectLater(connection.connect('11548522172'), throwsArgumentError);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('joins on the first chat answer without fetching its segments; then every new segment once', () async {
      final http = _Lists(stopAt: 15000, (request, path, calls) {
        if (path == _chatList.path) {
          return _ok(request, switch (calls) {
            1 => _playlist(['old1', 'old2', 'old3']),
            2 => _playlist(['old2', 'old3', 'new1']),
            _ => _playlist(['old3', 'new1', 'new2']),
          });
        }
        if (path == _reliableList.path) return _ok(request, _playlist(calls == 1 ? ['r0'] : ['r0', 'r1']));
        if (path == _hostList.path) return _status(request, 404);
        final name = path.split('/').last.replaceAll('.ts', '');
        return _ok(request, _segment(['$name 说']));
      });
      final trace = await _session(http);
      expect(trace, [
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReady()',
        {'wait': 5000},
        {'get': 'live_11500000001.m3u8'},
        {'get': 'new1.ts'},
        _project(BaiduLiveDanmakuProtocol.segment(_segment(['new1 说']), roomId: _room).messages.single),
        {'get': 'live_11500000003.m3u8'},
        {'get': 'live_11500000002.m3u8'},
        {'wait': 5000},
        {'get': 'live_11500000001.m3u8'},
        {'get': 'new2.ts'},
        _project(BaiduLiveDanmakuProtocol.segment(_segment(['new2 说']), roomId: _room).messages.single),
        {'get': 'live_11500000003.m3u8'},
        {'get': 'r1.ts'},
        _project(BaiduLiveDanmakuProtocol.segment(_segment(['r1 说']), roomId: _room).messages.single),
        // The host list skips a poll after its 404.
        {'wait': 5000},
        {'get': 'live_11500000001.m3u8'},
      ]);
    });

    test('a chat list that does not exist yet (404) joins; what it lists later is all new', () async {
      final http = _Lists(stopAt: 10000, (request, path, calls) {
        if (path == _chatList.path) return calls == 1 ? _status(request, 404) : _ok(request, _playlist(['a', 'b']));
        if (path.endsWith('.ts')) return _ok(request, _segment([path.split('/').last]));
        return _status(request, 404);
      });
      final trace = await _session(http, args: _args(reliable: false, host: false));
      expect(trace.take(2), [
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReady()',
      ]);
      expect(http.paths.where((path) => path.endsWith('.ts')), ['/v1/liveshowstatic/a.ts', '/v1/liveshowstatic/b.ts']);
      expect(trace.whereType<Map<Object?, Object?>>().where((entry) => entry['type'] == 'chat'), hasLength(2));
    });

    test('joining fails three times, 2 s apart: connectionFailed with the last failure; no ready', () async {
      final http = _Lists(
        (request, path, calls) =>
            calls == 3 ? _status(request, 403) : throw TransportFailure(request.site, TransportReason.timeout, 'slow'),
      );
      final statuses = <DanmakuStatus>[];
      final trace = await _session(http, statuses: statuses);
      expect(trace, [
        {'get': 'live_11500000001.m3u8'},
        {'wait': 2000},
        {'get': 'live_11500000001.m3u8'},
        {'wait': 2000},
        {'get': 'live_11500000001.m3u8'},
        startsWith('DanmakuClosed(connectionFailed: HttpStatusFailure(baidulive, 403'),
      ]);
      expect(statuses, [DanmakuStatus.closed, DanmakuStatus.idle]);
    });

    test('a playlist that is not one (an error page with 200) is a failure', () async {
      final http = _Lists((request, path, calls) => _ok(request, '<html>busy</html>'));
      final trace = await _session(http);
      expect(trace.last, startsWith('DanmakuClosed(connectionFailed: FormatException'));
      expect(http.requests, hasLength(3));
    });

    test('expired lists (by the clock given) end with credentialsUnavailable before any request', () async {
      final expiry = DateTime.utc(2026, 10);
      final http = _Lists((request, path, calls) => _ok(request, _playlist(const [])));
      final trace = await _session(
        http,
        args: _args(expiresAt: expiry),
        now: () => expiry,
      );
      expect(trace, ['DanmakuClosed(credentialsUnavailable: Chat list signature expired at 2026-10-01T00:00:00.000Z)']);
      expect(http.requests, isEmpty);
      // A second before it runs out, it joins.
      final before = _Lists(stopAt: 1, (request, path, calls) => _ok(request, _playlist(const [])));
      final joined = await _session(
        before,
        args: _args(expiresAt: expiry),
        now: () => expiry.subtract(const Duration(seconds: 1)),
      );
      expect(joined, contains('DanmakuReady()'));
    });

    test('the recorded lists (S02-room-chat) join at their recording and are expired half a year later', () async {
      final args = _recordedArgs('S03-live-chat');
      final recorded = DateTime.parse(_meta('S03-live-chat')['capturedAt']! as String);
      expect(args.expiresAt, DateTime.utc(2027, 4, 1, 0, 23, 3));
      expect(args.isExpiredAt(recorded), isFalse);
      expect(args.isExpiredAt(recorded.add(const Duration(days: 183))), isTrue);
    });

    test('a 403 after the signature ran out ends with credentialsUnavailable; before, it is a failure', () async {
      final expiry = _recordedAt.add(const Duration(seconds: 7));
      var clock = _recordedAt;
      late final _Lists http;
      http = _Lists((request, path, calls) {
        clock = _recordedAt.add(Duration(milliseconds: http.clock));
        return calls == 1 ? _ok(request, _playlist(const [])) : _status(request, 403);
      });
      final trace = await _session(
        http,
        args: _args(reliable: false, host: false, expiresAt: expiry),
        now: () => clock,
      );
      expect(trace, [
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReady()',
        {'wait': 5000},
        {'get': 'live_11500000001.m3u8'},
        startsWith('DanmakuReconnecting(disconnected: HttpStatusFailure(baidulive, 403'),
        {'wait': 1000},
        {'get': 'live_11500000001.m3u8'},
        {'wait': 2000},
        {'get': 'live_11500000001.m3u8'},
        'DanmakuClosed(credentialsUnavailable: Chat list signature expired at 2026-09-30T12:00:07.000Z)',
      ]);
    });

    test('failures: one notice, 1-2-4-8… s apart, the ninth ends; an answer after failures joins again', () async {
      final http = _Lists(stopAt: 600000, (request, path, calls) {
        if (calls == 1 || calls == 4) return _ok(request, _playlist(const []));
        if (calls == 3) return _status(request, 502);
        throw TransportFailure(request.site, TransportReason.connect, 'refused');
      });
      final statuses = <DanmakuStatus>[];
      final trace = await _session(http, args: _args(reliable: false, host: false), statuses: statuses);
      expect(trace, [
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReady()',
        {'wait': 5000},
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReconnecting(disconnected: TransportFailure(baidulive, connect: refused))',
        {'wait': 1000},
        {'get': 'live_11500000001.m3u8'},
        {'wait': 2000},
        {'get': 'live_11500000001.m3u8'},
        'DanmakuReady()',
        {'wait': 5000},
        for (var failure = 1; failure <= 9; failure++) ...[
          {'get': 'live_11500000001.m3u8'},
          if (failure == 1) 'DanmakuReconnecting(disconnected: TransportFailure(baidulive, connect: refused))',
          if (failure <= 8) {'wait': BaiduLiveDanmakuProtocol.backoff(failure).inMilliseconds},
        ],
        'DanmakuClosed(reconnectsExhausted: TransportFailure(baidulive, connect: refused))',
      ]);
      expect(statuses, [
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.connected,
        DanmakuStatus.reconnecting,
        DanmakuStatus.closed,
        DanmakuStatus.idle,
      ]);
    });

    test(
      'reliable and host lists: failures and 404 skip 1, 2, 4, 8, then 12 polls; their history is skipped',
      () async {
        final http = _Lists(stopAt: 5000 * 60, (request, path, calls) {
          if (path == _chatList.path) return _ok(request, _playlist(const []));
          if (path == _reliableList.path) {
            if (calls <= 2) throw TransportFailure(request.site, TransportReason.timeout, 'slow');
            return _ok(request, _playlist(['gift$calls']));
          }
          if (path == _hostList.path) return _status(request, 404);
          return _ok(request, _segment([_giftPayload()]));
        });
        await _session(http);
        final rounds = <int>[];
        final reliable = <int>[];
        var round = -1;
        for (final path in http.paths) {
          if (path == _chatList.path) round++;
          if (path == _hostList.path) rounds.add(round);
          if (path == _reliableList.path) reliable.add(round);
        }
        // Round 0 is the join; the host list is asked in rounds 1, 3, 6, 11,
        // 20, 33, 46 and 59 (skipping 1, 2, 4, 8, 12, 12, 12).
        expect(rounds, [1, 3, 6, 11, 20, 33, 46, 59]);
        // Two timeouts (skip 1, then 2), then every round; its first answer
        // (gift3) is history, the rest are fetched.
        expect(reliable.take(4), [1, 3, 6, 7]);
        expect(http.paths.where((path) => path.endsWith('.ts')).first, '/v1/liveshowstatic/gift4.ts');
        expect(http.paths, isNot(contains('/v1/liveshowstatic/gift3.ts')));
      },
    );

    test('gifts from the reliable list are gift messages', () async {
      final http = _Lists(stopAt: 15000, (request, path, calls) {
        if (path == _chatList.path) return _ok(request, _playlist(const []));
        if (path == _reliableList.path) return _ok(request, _playlist(calls == 1 ? const [] : ['g']));
        if (path == _hostList.path) return _status(request, 404);
        return _ok(request, _segment([_giftPayload()]));
      });
      final trace = await _session(http);
      final gifts = trace.whereType<Map<Object?, Object?>>().where((entry) => entry['type'] == 'gift').toList();
      expect(gifts, hasLength(1));
      expect(gifts.single['message'], '拍拍 ×2');
    });

    test('segments: 4xx skipped at once, no answer or 5xx tried three times, a broken one skipped', () async {
      final http = _Lists(stopAt: 5000 * 5, (request, path, calls) {
        if (path == _chatList.path) {
          return _ok(request, calls == 1 ? _playlist(const []) : _playlist(['gone', 'slow', 'busy', 'broken', 'fine']));
        }
        return switch (path.split('/').last) {
          'gone.ts' => _status(request, 403),
          'slow.ts' => throw TransportFailure(request.site, TransportReason.timeout, 'slow'),
          'busy.ts' => calls < 3 ? _status(request, 503) : _ok(request, _segment(['终于'])),
          'broken.ts' => _ok(request, utf8.encode('<html>')),
          _ => _ok(request, _segment(['好'])),
        };
      });
      final trace = await _session(http, args: _args(reliable: false, host: false));
      int asked(String name) => http.paths.where((path) => path.endsWith('/$name.ts')).length;
      expect([asked('gone'), asked('slow'), asked('busy'), asked('broken'), asked('fine')], [1, 3, 3, 1, 1]);
      expect(
        [
          for (final entry in trace.whereType<Map<Object?, Object?>>())
            if (entry['type'] == 'chat') entry['message'],
        ],
        ['好', '终于'],
      );
      expect(trace.whereType<String>().where((event) => event != 'DanmakuReady()'), isEmpty, reason: 'no notice');
    });

    test('a segment served gzipped without Content-Encoding is read too', () async {
      final http = _Lists(stopAt: 6000, (request, path, calls) {
        if (path == _chatList.path) return _ok(request, calls == 1 ? _playlist(const []) : _playlist(['z']));
        return _ok(request, _segment(['压缩的']));
      });
      final trace = await _session(http, args: _args(reliable: false, host: false));
      expect(trace.whereType<Map<Object?, Object?>>().where((entry) => entry['message'] == '压缩的'), hasLength(1));
    });

    test('the broadcast stopped (102): the segment is reported, then connectionFailed; nothing follows', () async {
      final http = _Lists((request, path, calls) {
        if (path == _chatList.path) return _ok(request, calls == 1 ? _playlist(const []) : _playlist(['end', 'after']));
        return _ok(
          request,
          _segment([
            '再见',
            {'type': 102, 'room_id': _room},
          ]),
        );
      });
      final statuses = <DanmakuStatus>[];
      final trace = await _session(http, statuses: statuses);
      expect(trace.whereType<Map<Object?, Object?>>().where((entry) => entry['message'] == '再见'), hasLength(1));
      expect(trace.last, 'DanmakuClosed(connectionFailed: Broadcast ended)');
      expect(http.paths.last, '/v1/liveshowstatic/end.ts', reason: 'no more requests');
      expect(statuses.sublist(statuses.length - 2), [DanmakuStatus.closed, DanmakuStatus.idle]);
      // mix_room_close naming this room is not the end.
      final mix = _Lists(stopAt: 6000, (request, path, calls) {
        if (path == _chatList.path) return _ok(request, calls == 1 ? _playlist(const []) : _playlist(['mix']));
        return _ok(
          request,
          _segment([
            {
              'type': 107,
              'data': {
                'service_type': '10013',
                'service_info': {
                  'content': {
                    'content_type': 'mix_room_close',
                    'room_ids': [int.parse(_room)],
                  },
                },
              },
            },
          ]),
        );
      });
      final mixed = await _session(mix, args: _args(reliable: false, host: false));
      expect(mixed.whereType<String>().where((event) => event.startsWith('DanmakuClosed')), isEmpty);
    });

    test('the pull interval of the room command is the wait between rounds', () async {
      final http = _Lists(stopAt: 6000, (request, path, calls) => _ok(request, _playlist(const [])));
      final trace = await _session(
        http,
        args: _args(interval: const Duration(seconds: 3), reliable: false, host: false),
      );
      expect(trace.where((entry) => entry is Map && entry['wait'] != null), [
        {'wait': 3000},
        {'wait': 3000},
      ]);
    });

    test('a list naming more than 256 new segments forgets the oldest keys', () async {
      final names = [for (var i = 0; i < 257; i++) 's$i'];
      final http = _Lists(stopAt: 11000, (request, path, calls) {
        if (path == _chatList.path) {
          return _ok(request, switch (calls) {
            1 => _playlist(const []),
            2 => _playlist(names),
            _ => _playlist(['s0', 's256']),
          });
        }
        return _ok(request, _segment(const []));
      });
      await _session(http, args: _args(reliable: false, host: false));
      expect(http.paths.where((path) => path.endsWith('/s0.ts')), hasLength(2));
      expect(http.paths.where((path) => path.endsWith('/s256.ts')), hasLength(1));
    });

    test('close during the first request cancels it; connect completes; nothing follows', () async {
      final pending = Completer<void>();
      final http = _Lists((request, path, calls) async {
        pending.complete();
        await request.cancel!.whenCancelled;
        throw TransportFailure(request.site, TransportReason.cancelled);
      });
      final connection = BaiduLiveDanmakuConnection(http: http, now: () => _recordedAt);
      final events = _record(connection);
      final connecting = connection.connect(_args());
      await pending.future;
      await connection.close();
      await connecting;
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
    });

    test('close while waiting for the next round: no request, event or timer follows', () async {
      final http = _Lists((request, path, calls) => _ok(request, _playlist(const [])));
      final connection = BaiduLiveDanmakuConnection(http: http, now: () => _recordedAt);
      final events = _record(connection);
      await connection.connect(_args());
      expect(events, [const DanmakuReady()]);
      await connection.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(http.requests, hasLength(1));
      expect(events, [const DanmakuReady()]);
    });

    test("connecting to another room: the first one's late answers are dropped", () async {
      final answers = <Completer<LiveResponse>>[];
      final http = _Lists((request, path, calls) {
        final answer = Completer<LiveResponse>();
        answers.add(answer);
        return answer.future;
      });
      final connection = BaiduLiveDanmakuConnection(http: http, now: () => _recordedAt);
      final events = _record(connection);
      final first = connection.connect(_args());
      await _until(() => answers.length == 1);
      final second = connection.connect(
        BaiduLiveDanmakuArgs(roomId: '11500000009', chatList: Uri.parse('$_base/live_11500000009.m3u8')),
      );
      await _until(() => answers.length == 2);
      answers[0].complete(_ok(http.requests[0], _playlist(const [])));
      await first;
      expect(events, isEmpty);
      answers[1].complete(_ok(http.requests[1], _playlist(const [])));
      await second;
      expect(events, [const DanmakuReady()]);
      expect(http.requests[1].headers['referer'], 'https://live.baidu.com/m/room/11500000009');
      await connection.close();
    });

    test('a local HTTP server: the requests on the wire, gzip with and without the header, a 404 host list', () async {
      final served = <String>[];
      final headers = <HttpHeaders>[];
      var polls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        served.add('${request.method} ${request.uri}');
        headers.add(request.headers);
        final response = request.response;
        final path = request.uri.path;
        if (path.endsWith('live_1.m3u8')) {
          polls++;
          response.write(_playlist(polls == 1 ? ['old'] : ['old', 'a', 'b']));
        } else if (path.endsWith('live_3.m3u8')) {
          response
            ..statusCode = 404
            ..write('{"code":"NoSuchKey"}');
        } else if (path.endsWith('/a.ts')) {
          // Compressed on the fly: served with Content-Encoding: gzip.
          response.headers.set('content-encoding', 'gzip');
          response.add(_segment(['有头的']));
        } else if (path.endsWith('/b.ts')) {
          // Gzipped bytes without Content-Encoding.
          response.add(_segment(['没头的']));
        } else {
          response.statusCode = 500;
        }
        await response.close();
      });
      addTearDown(() => server.close(force: true));
      final http = IoLiveHttp();
      addTearDown(http.close);
      final origin = 'http://127.0.0.1:${server.port}/v1/liveshowstatic';
      final connection = BaiduLiveDanmakuConnection(http: http, now: () => _recordedAt);
      final events = _record(connection);
      await runZoned(
        () async {
          await connection.connect(
            BaiduLiveDanmakuArgs(
              roomId: _room,
              chatList: Uri.parse('$origin/live_1.m3u8?$_auth'),
              hostList: Uri.parse('$origin/live_3.m3u8?$_auth'),
            ),
          );
          await _until(() => events.length >= 3 && served.length >= 5);
        },
        zoneSpecification: ZoneSpecification(
          // Only the wait between rounds fires at once, not the client's
          // timeouts.
          createTimer: (self, parent, zone, duration, callback) =>
              parent.createTimer(zone, duration == const Duration(seconds: 5) ? Duration.zero : duration, callback),
        ),
      );
      await connection.close();
      expect(served.take(5), [
        'GET /v1/liveshowstatic/live_1.m3u8?$_auth',
        'GET /v1/liveshowstatic/live_1.m3u8?$_auth',
        'GET /v1/liveshowstatic/a.ts?authorization=bce-auth-v1/x/2026-09-30T12:00:00Z/604800/host/a',
        'GET /v1/liveshowstatic/b.ts?authorization=bce-auth-v1/x/2026-09-30T12:00:00Z/604800/host/b',
        'GET /v1/liveshowstatic/live_3.m3u8?$_auth',
      ]);
      for (final header in headers) {
        expect(header.value('user-agent'), BaiduLiveApi.userAgent);
        expect(header.value('origin'), 'https://live.baidu.com');
        expect(header.value('referer'), 'https://live.baidu.com/m/room/$_room');
      }
      expect(events.take(3).map(_shown), [
        'DanmakuReady()',
        containsPair('message', '有头的'),
        containsPair('message', '没头的'),
      ]);
    });
  });
}

Map<String, Object?> _giftPayload() => {
  'type': 107,
  'data': {
    'service_type': '10024',
    'service_info': {
      'content': jsonEncode({'gift_count': 2, 'gift_id': '11138', 'gift_name': '拍拍', 'is_free': 1}),
      'room_id': int.parse(_room),
      'user_id': 2000000002,
      'user_name': '送礼观众',
    },
  },
};
