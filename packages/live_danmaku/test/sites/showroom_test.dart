import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/showroom/danmaku/S06-live';

/// The recording (S06-live): every frame with its line number and direction.
final List<({int line, bool incoming, String text})> _recording = [
  for (final (index, line) in File('$_root/frames.jsonl').readAsLinesSync().indexed)
    if (jsonDecode(line) case {'dir': final String dir, 'text': final String text})
      (line: index + 1, incoming: dir == 'in', text: text),
];

final Map<String, Object?> _meta = jsonDecode(File('$_root/meta.json').readAsStringSync()) as Map<String, Object?>;

/// The archived v4's output for S06-live (danmaku/v4_expected.dart).
final Map<String, Object?> _v4 =
    (jsonDecode(File('$_root/expected.json').readAsStringSync()) as Map<String, Object?>)['value']!
        as Map<String, Object?>;

/// The recorded broadcast's key and server.
const String _key = '6e6c686835796846:23483509';
const String _host = 'online.showroom-live.com';

const _args = ShowroomDanmakuArgs(roomId: '577362', host: _host, key: _key);

/// No heartbeat or watchdog and a short backoff: only what the test does
/// happens.
const DanmakuSocketPolicy _quiet = DanmakuSocketPolicy(
  heartbeatInterval: Duration.zero,
  reconnectBaseDelay: Duration(milliseconds: 5),
);

/// A `MSG` frame of [key] carrying [event].
String _msg(Object? event, {String key = _key}) => 'MSG\t$key\t${jsonEncode(event)}';

/// A comment in the shape the server sent on 2026-09-29 (synthetic values).
Map<String, Object?> _comment({
  Object? t = 1,
  Object? cm = 'こんばんは',
  Object? ac = '观众1',
  Object? u = 1234567,
  Object? cl = 12,
  Object? createdAt = 1790632139,
}) => {
  't': ?t,
  'u': ?u,
  'ac': ?ac,
  'av': 1001,
  'cm': ?cm,
  'd': 0,
  'at': 0,
  'ua': 0,
  'aft': 0,
  'cl': ?cl,
  'cifn': 'class_level_1.png',
  'cbisc': '#929CC3',
  'cbiec': '#929CC3',
  'created_at': ?createdAt,
};

final class _Channel implements SocketChannel {
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  /// Delivers [frame] and lets the connection handle it.
  Future<void> receive(Object frame) async {
    incoming.add(frame);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Hands out fake sockets and records every handshake; the first [failures]
/// handshakes throw.
final class _Connector {
  new({this.failures = 0});

  final int failures;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<ProxyRoute> routes = [];
  final List<_Channel> channels = [];

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    routes.add(route);
    if (endpoints.length <= failures) throw const SocketException('refused');
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

List<LiveMessage> _messages(List<DanmakuEvent> events) => [
  for (final event in events)
    if (event is DanmakuReceived) event.message,
];

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most five seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

/// A message as the v4 projection shows it, without the id (v4 made one up).
Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userId': message.userId,
  'userName': message.userName,
  'text': message.message,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
};

/// A v4 event without its id.
Map<String, Object?> _withoutId(Map<String, Object?> event) => {...event}..remove('id');

void main() {
  group('protocol', () {
    test('the socket, the subscription, the ping and the handshake headers', () {
      expect(ShowroomDanmakuProtocol.endpoint(_host), Uri.parse('wss://online.showroom-live.com/'));
      expect(ShowroomDanmakuProtocol.subscribe(_key), 'SUB\t6e6c686835796846:23483509');
      expect(ShowroomDanmakuProtocol.ping, 'PING\tshowroom');
      expect(ShowroomDanmakuProtocol.ack, 'ACK\tshowroom');
      expect(ShowroomDanmakuProtocol.heartbeatInterval, const Duration(seconds: 60));
      expect(ShowroomDanmakuProtocol.socketHeaders, {
        'origin': 'https://www.showroom-live.com',
        'user-agent': ShowroomApi.userAgent,
      });
    });

    test('arguments are checked as live_core checks them: a showroom-live.com host, a key without spaces', () {
      final checked = ShowroomDanmakuProtocol.checked(
        const ShowroomDanmakuArgs(roomId: '577362', host: 'Online.SHOWROOM-live.com', key: _key),
      )!;
      expect((checked.roomId, checked.host, checked.key), ('577362', _host, _key));
      final longest = 'k' * 256;
      expect(
        ShowroomDanmakuProtocol.checked(ShowroomDanmakuArgs(roomId: 'x', host: 'showroom-live.com', key: longest))?.key,
        longest,
      );
      for (final (host, key) in [
        ('', _key),
        ('evilshowroom-live.com', _key),
        ('online.showroom-live.com.example.com', _key),
        ('online.showroom-live.com:8080', _key),
        ('online.showroom-live.com/', _key),
        ('127.0.0.1', _key),
        (_host, ''),
        (_host, 'a b'),
        (_host, 'a\tb'),
        (_host, 'a\u0000b'),
        (_host, 'k' * 257),
      ]) {
        expect(
          ShowroomDanmakuProtocol.checked(ShowroomDanmakuArgs(roomId: '1', host: host, key: key)),
          isNull,
          reason: '$host $key',
        );
      }
    });

    test('a comment: text, name, user id, class level and time; no id', () {
      final message = ShowroomDanmakuProtocol.comment(_comment(cm: '  こんばんは\n'))!;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'こんばんは');
      expect(message.userName, '观众1');
      expect(message.userId, '1234567');
      expect(message.userLevel, '12');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790632139000));
      expect(message.messageId, isEmpty);
      expect(message.color, LiveMessageColor.white);
      expect(message.fansName, isEmpty);
      expect(message.isLocal, isFalse);
    });

    test('comment boundaries: text, kind, names, ids, levels and times', () {
      LiveMessage? of(Map<String, Object?> event) => ShowroomDanmakuProtocol.comment(event);
      for (final text in [
        '',
        '   ',
        null,
        1.5,
        true,
        const ['x'],
        const {'a': 1},
      ]) {
        expect(of(_comment(cm: text)), isNull, reason: '$text');
      }
      // Counting comments stay, as text or as a number.
      expect(of(_comment(cm: '1'))!.message, '1');
      expect(of(_comment(cm: 2))!.message, '2');
      expect(of(_comment(t: '1'))!.message, 'こんばんは');
      for (final type in [2, 5, 8, 11, 17, 18, 20, 100, 101, 104, 1001, 0, '01', 1.0, null, 'comment']) {
        expect(of(_comment(t: type)), isNull, reason: '$type');
      }
      final bare = of(_comment(ac: null, u: null, cl: null))!;
      expect((bare.userName, bare.userId, bare.userLevel), ('', '', ''));
      expect(of(_comment(ac: '  名前 '))!.userName, '名前');
      expect(of(_comment(ac: 42))!.userName, '42');
      expect(of(_comment(ac: const ['x']))!.userName, '');
      expect(of(_comment(u: ' 99 '))!.userId, '99');
      expect(of(_comment(u: 1.5))!.userId, '');
      for (final level in [0, -1, 1.5, '12', true]) {
        expect(of(_comment(cl: level))!.userLevel, isEmpty, reason: '$level');
      }
      expect(of(_comment(cl: 1))!.userLevel, '1');
      for (final time in [0, -1, 8640000000001, 1.79e9, '1790632139', null]) {
        expect(of(_comment(createdAt: time))!.sentAt, isNull, reason: '$time');
      }
      expect(of(_comment(createdAt: 1))!.sentAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(of(_comment(createdAt: 8640000000000))!.sentAt, DateTime.fromMillisecondsSinceEpoch(8640000000000000));
      expect(of(const {'t': 1, 'cm': 'only text'})!.message, 'only text');
      expect(ShowroomDanmakuProtocol.comment('text'), isNull);
      expect(ShowroomDanmakuProtocol.comment(null), isNull);
    });

    test('frames: only MSG frames of the key whose object is a comment', () {
      List<String> texts(Object? data, {String key = _key}) => [
        for (final message in ShowroomDanmakuProtocol.decode(data, key: key)) message.message,
      ];
      expect(texts(_msg(_comment(cm: 'one'))), ['one']);
      expect(texts(utf8.encode(_msg(_comment(cm: '弾き語り')))), ['弾き語り']);
      expect(texts([0xFF, ...utf8.encode(_msg(_comment()))]), isEmpty);
      // An escaped tab inside the JSON is text; the frame is split at the first two tabs only.
      expect(texts(_msg(_comment(cm: 'a\tb'))), ['a\tb']);
      for (final frame in [
        'ACK\tshowroom',
        'PING\tshowroom',
        '',
        'MSG',
        'MSG\t',
        'MSG\t$_key',
        'MSG\t$_key\t',
        'MSG\t$_key\tnot json',
        'MSG\t$_key\t{"t":1,"cm":"cut',
        'MSG\t$_key\t[${jsonEncode(_comment())}]',
        'MSG\t$_key\tnull',
        'MSG\t$_key\t"text"',
        'msg\t$_key\t${jsonEncode(_comment())}',
        ' MSG\t$_key\t${jsonEncode(_comment())}',
        _msg(_comment(), key: '0000000000000000:23483509'),
        _msg(_comment(), key: '${_key}0'),
        _msg(_comment(), key: _key.substring(1)),
        _msg(_comment(), key: ''),
        // A gift without a gift id (D07.7 reads `t` 2 with one).
        _msg(const {'t': 2, 'g': 0, 'n': 10, 'u': 1, 'ac': 'a'}),
        _msg(const {'t': 8, 'telop': 'caption', 'telops': <Object?>[], 'interval': 6000}),
        _msg(const {'t': 18, 'm': '来場しました', 'me': 'visited', 'u': 1, 'tt': 0, 'c': '#fff'}),
        _msg(const {'t': 101}),
        _msg(const {'t': 104}),
      ]) {
        expect(texts(frame), isEmpty, reason: frame);
      }
      expect(texts(42), isEmpty);
      expect(texts(null), isEmpty);
      expect(texts(_msg(_comment(), key: 'other'), key: 'other'), ['こんばんは']);
    });
  });

  group('recording (S06-live)', () {
    test('the socket, headers, subscription and ping are those of the archived v4 and the recording', () {
      final keys = (_meta['danmakuKeys']! as Map).cast<String, String>();
      expect(keys, {'bcsvrKey': _key, 'bcsvrHost': _host});
      final handshake = (_meta['handshakes']! as List).single as Map<String, Object?>;
      expect(ShowroomDanmakuProtocol.endpoint(_host).toString(), _v4['endpoint']);
      expect(handshake['url'], _v4['endpoint']);
      expect(ShowroomDanmakuProtocol.socketHeaders, _v4['headers']);
      expect(handshake['headers'], _v4['headers']);
      expect(ShowroomDanmakuProtocol.subscribe(_key), _v4['subscribe']);
      expect(ShowroomDanmakuProtocol.ping, _v4['ping']);
      expect(ShowroomDanmakuProtocol.heartbeatInterval.inSeconds, _v4['heartbeatSeconds']);
      final sent = [
        for (final frame in _recording)
          if (!frame.incoming) frame.text,
      ];
      expect(sent, [ShowroomDanmakuProtocol.subscribe(_key), ShowroomDanmakuProtocol.ping]);
      expect(_recording.where((frame) => frame.incoming && frame.text == ShowroomDanmakuProtocol.ack), hasLength(1));
    });

    test('room entry (S04-live-info-live) gives the arguments of the recorded broadcast', () async {
      final info = ShowroomApi.liveInfo(
        File('../../fixtures/showroom/S04-live-info-live/body.json').readAsStringSync(),
        roomId: 577362,
      );
      final args = info.danmaku!;
      expect((args.roomId, args.host, args.key), ('577362', _host, _key));
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      await connection.connect(args);
      expect(connector.endpoints.single.toString(), _v4['endpoint']);
      expect(connector.channels.single.sent, [_recording.first.text]);
      await connection.close();
    });

    test('every received frame decodes as the archived v4 did (without its made-up id)', () {
      final frames = (_v4['frames']! as List).cast<Map<String, Object?>>();
      final received = [
        for (final frame in _recording)
          if (frame.incoming) frame,
      ];
      expect(received, hasLength(frames.length));
      var chats = 0;
      for (final (index, frame) in received.indexed) {
        final expected = frames[index];
        expect(frame.line, expected['line']);
        final messages = ShowroomDanmakuProtocol.decode(frame.text, key: _key);
        final events = (expected['events']! as List).cast<Map<String, Object?>>();
        expect(
          [for (final message in messages) _project(message)],
          [for (final event in events) _withoutId(event)],
          reason: 'line ${frame.line}',
        );
        for (final (i, message) in messages.indexed) {
          // v4: showroom:<u>:<created_at>:<the text's hashCode>.
          final id = events[i]['id']! as String;
          expect(id, startsWith('showroom:${message.userId}:${message.sentAt!.millisecondsSinceEpoch ~/ 1000}:'));
          expect(message.messageId, isEmpty);
          expect(message.userLevel, isEmpty);
        }
        chats += messages.length;
      }
      expect((received.length, chats), (23, 18));
    });

    test('the connection replays the recording: SUB on open, ready, 18 chats in order, PING as recorded', () async {
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      final keys = (_meta['danmakuKeys']! as Map).cast<String, String>();
      await connection.connect(ShowroomDanmakuArgs(roomId: '577362', host: keys['bcsvrHost']!, key: keys['bcsvrKey']!));
      expect(connector.endpoints, [Uri.parse(_v4['endpoint']! as String)]);
      final channel = connector.channels.single;
      for (final frame in _recording) {
        if (frame.incoming) {
          await channel.receive(frame.text);
        } else if (frame.text == ShowroomDanmakuProtocol.ping) {
          connection.heartbeat();
        }
      }
      expect(channel.sent, [
        for (final frame in _recording)
          if (!frame.incoming) frame.text,
      ]);
      expect(events.first, const DanmakuReady());
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      expect(events.whereType<DanmakuReconnecting>(), isEmpty);
      final expected = [
        for (final frame in (_v4['frames']! as List).cast<Map<String, Object?>>())
          for (final event in (frame['events']! as List).cast<Map<String, Object?>>()) _withoutId(event),
      ];
      expect([for (final message in _messages(events)) _project(message)], expected);
      await connection.close();
    });
  });

  group('gifts (D07.7, S07-gifts and the S06 gift table)', () {
    final lines = [
      for (final line in File('../../fixtures/showroom/danmaku/S07-gifts/frames.jsonl').readAsLinesSync())
        (jsonDecode(line) as Map<String, Object?>)['text']! as String,
    ];
    final table = ShowroomApi.giftList(File('../../fixtures/showroom/S06-gift-list/body.json').readAsStringSync());
    String keyOf(String line) => line.split('\t')[1];
    List<LiveMessage> decode({ShowroomGiftCatalog gifts = ShowroomGiftCatalog.empty}) => [
      for (final line in lines) ...ShowroomDanmakuProtocol.decode(line, key: keyOf(line), gifts: gifts),
    ];

    test('S07 with the table: names, free stars, paid gifts in points, the pictures', () {
      final messages = decode(gifts: table);
      expect(messages, hasLength(16));
      final gifts = [for (final m in messages) m.data! as LiveGift];
      expect(
        [for (final (i, g) in gifts.indexed) (messages[i].userName, g.name, g.count, g.free, g.totalValue)],
        [
          ('視聴者1', 'Twinkle star', 10, true, null),
          ('視聴者1', 'Twinkle star', 10, true, null),
          ('視聴者2', 'Twinkle star', 100, true, null),
          for (var i = 0; i < 3; i++) ('視聴者1', 'Twinkle star', 10, true, null),
          ('視聴者3', 'You got this!', 10, false, 50),
          ('視聴者4', 'Napolitan(anime)', 2, false, 200),
          ('視聴者5', 'RainbowStar', 1, true, null),
          ('視聴者6', 'Twinkle Star (anime)', 1, false, 2),
          ('視聴者7', 'seed(purple)', 10, true, null),
          ('視聴者7', 'seed(yellow)', 10, true, null),
          ('視聴者8', 'Penlight(rainbow)', 10, true, null),
          ('視聴者9', 'Twinkle star', 10, true, null),
          ('視聴者9', 'Twinkle star', 10, true, null),
          ('視聴者10', 'Cream soda(anime)', 1, false, 500),
        ],
      );
      expect(gifts.map((g) => g.unit), everyElement(LiveGiftUnit.point));
      final soda = messages.last;
      expect(
        (soda.userId, soda.userLevel, soda.message, soda.sentAt, soda.messageId),
        ('5000010', '30', 'Cream soda(anime) ×1', DateTime.fromMillisecondsSinceEpoch(1791529203000), ''),
      );
      expect(
        soda.data,
        LiveGift(
          id: '3001833',
          name: 'Cream soda(anime)',
          unitPrice: 500,
          totalValue: 500,
          unit: LiveGiftUnit.point,
          iconUrl: Uri.parse('https://static.showroom-live.com/image/gift/3001833_m.png?v=21'),
        ),
      );
      expect(gifts.last.tier, LiveGiftTier.valuable, reason: '500 points, about 24 yuan');
    });

    test('without the table: only the id ("礼物 {id}"), free by gt 2, the picture by id', () {
      final gifts = [for (final m in decode()) m.data! as LiveGift];
      expect(gifts.map((g) => g.name), everyElement(''));
      expect(
        gifts.first,
        LiveGift(
          id: '3000421',
          count: 10,
          name: '',
          unit: LiveGiftUnit.point,
          free: true,
          iconUrl: ShowroomDanmakuProtocol.giftImage('3000421'),
        ),
      );
      expect((gifts[6].free, gifts[6].totalValue), (false, null), reason: 'gt 1, no price without the table');
      expect(
        ShowroomDanmakuProtocol.giftImage('1601'),
        Uri.parse('https://static.showroom-live.com/image/gift/1601_s.png'),
      );
      expect(
        ShowroomDanmakuProtocol.gift({'t': '2', 'g': '5', 'u': 1, 'ac': 'a'})!.message,
        '5 ×1',
        reason: 't and g as text',
      );
      expect(ShowroomDanmakuProtocol.gift({'t': 2, 'u': 1, 'ac': 'a'}), isNull);
      expect(ShowroomDanmakuProtocol.gift({'t': 1, 'g': 5}), isNull);
    });

    test('the connection asks for the table once in the background and names the gifts once it came', () async {
      final connector = _Connector();
      final pending = Completer<ShowroomGiftCatalog>();
      var asked = 0;
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      final key = keyOf(lines.first);
      await connection.connect(
        ShowroomDanmakuArgs(
          roomId: '130997',
          host: _host,
          key: key,
          gifts: () {
            asked++;
            return pending.future;
          },
        ),
      );
      final channel = connector.channels.single;
      await channel.receive(lines.first);
      pending.complete(table);
      await Future<void>.delayed(Duration.zero);
      await channel.receive(lines[1]);
      expect([for (final m in _messages(events)) m.message], ['3000421 ×10', 'Twinkle star ×10']);
      expect(asked, 1);
      await connection.close();
    });
  });

  group('connection', () {
    test('timing and registration', () {
      const policy = ShowroomDanmakuConnection.socketPolicy;
      expect(policy.heartbeatInterval, const Duration(seconds: 60));
      expect(policy.inactivityTimeout, isNull);
      expect(policy.joinTimeout, isNull);
      expect(policy.maxReconnects, 8);
      expect(policy.reconnectBaseDelay, const Duration(seconds: 1));
      expect(policy.connectTimeout, const Duration(seconds: 10));
      final connection = ShowroomDanmakuConnection();
      expect(connection.heartbeatInterval, const Duration(seconds: 60));
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.site, SiteIds.showroom);
      final registry = DanmakuRegistry({SiteIds.showroom: ShowroomDanmakuConnection.new});
      expect(registry.supports('SHOWROOM'), isTrue);
      expect(registry.connectionFor('showroom'), isA<ShowroomDanmakuConnection>());
    });

    test('handshake: the server of the arguments with the headers; SUB on open, then ready', () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = ShowroomDanmakuConnection(
        connector: connector.call,
        proxy: const FixedProxyPolicy(perSite: {SiteIds.showroom: route}),
        policy: _quiet,
      );
      final events = _record(connection);
      await connection.connect(
        const ShowroomDanmakuArgs(roomId: '577362', host: 'ONLINE.showroom-live.com', key: _key),
      );
      expect(connector.endpoints, [Uri.parse('wss://online.showroom-live.com/')]);
      expect(connector.headers.single, ShowroomDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      expect(connector.channels.single.sent, ['SUB\t$_key']);
      expect(events, [const DanmakuReady()]);
      expect(connection.isConnected, isTrue);
      await connector.channels.single.receive(_msg(_comment(cm: 'hi')));
      await connector.channels.single.receive(_msg(_comment(cm: 'other key'), key: 'ffffffffffffffff:1'));
      await connector.channels.single.receive(ShowroomDanmakuProtocol.ack);
      expect([for (final m in _messages(events)) m.message], ['hi']);
      await connection.close();
    });

    test('PING at every heartbeat and on demand; ACKs keep a quiet socket', () async {
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration(milliseconds: 20),
          // Wide enough that a loaded machine never misses an answer.
          inactivityTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      final events = _record(connection);
      await connection.connect(_args);
      final channel = connector.channels.single;
      // Answer every ping as the server does, for 500 ms: the socket stays.
      final deadline = DateTime.now().add(const Duration(milliseconds: 500));
      var answered = 0;
      while (DateTime.now().isBefore(deadline)) {
        final pings = channel.sent.where((frame) => frame == ShowroomDanmakuProtocol.ping).length;
        for (; answered < pings; answered++) {
          await channel.receive(ShowroomDanmakuProtocol.ack);
        }
        await _wait(const Duration(milliseconds: 5));
      }
      expect(connector.channels, hasLength(1));
      expect(events, [const DanmakuReady()]);
      expect(channel.sent.first, 'SUB\t$_key');
      expect(channel.sent.skip(1), everyElement(ShowroomDanmakuProtocol.ping));
      expect(channel.sent.length, greaterThan(2));
      final before = channel.sent.length;
      connection.heartbeat();
      expect(channel.sent, hasLength(before + 1));
      expect(channel.sent.last, ShowroomDanmakuProtocol.ping);
      // Unanswered pings: the socket is replaced and subscribes again.
      await _until(() => connector.channels.length == 2);
      expect(channel.closed, isTrue);
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(events[1], const DanmakuReconnecting(DanmakuInterruption.disconnected));
      expect(connector.channels.last.sent.first, 'SUB\t$_key');
      await connection.close();
    });

    test('a dropped socket reconnects to the same server and subscribes again', () async {
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      await connector.channels.first.incoming.close();
      await _until(() => events.whereType<DanmakuReady>().length == 2);
      expect(connector.endpoints, [Uri.parse('wss://$_host/'), Uri.parse('wss://$_host/')]);
      expect(connector.channels.last.sent, ['SUB\t$_key']);
      expect(events, [
        const DanmakuReady(),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
      ]);
      await connector.channels.last.receive(_msg(_comment(cm: 'after')));
      expect(_messages(events).single.message, 'after');
      await connection.close();
    });

    test('a failed handshake is retried; failures in a row end the connection', () async {
      final retried = _Connector(failures: 1);
      final first = ShowroomDanmakuConnection(connector: retried.call, policy: _quiet);
      final events = _record(first);
      await first.connect(_args);
      await _until(() => first.isConnected);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      expect(retried.channels.single.sent, ['SUB\t$_key']);
      await first.close();

      final refused = _Connector(failures: 100);
      final second = ShowroomDanmakuConnection(
        connector: refused.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          reconnectBaseDelay: Duration(milliseconds: 1),
          maxReconnects: 2,
        ),
      );
      final ended = _record(second);
      await second.connect(_args);
      await _until(() => ended.whereType<DanmakuClosed>().isNotEmpty);
      expect(
        ended.last,
        isA<DanmakuClosed>().having((e) => e.reason, 'reason', DanmakuCloseReason.reconnectsExhausted),
      );
      expect(ended.whereType<DanmakuReconnecting>(), hasLength(1));
      expect(refused.endpoints, hasLength(3));
      expect(second.status, DanmakuStatus.closed);
    });

    test('unusable arguments end at once, without a handshake', () async {
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      for (final args in const [
        ShowroomDanmakuArgs(roomId: '1', host: 'example.com', key: _key),
        ShowroomDanmakuArgs(roomId: '1', host: _host, key: 'a b'),
        ShowroomDanmakuArgs(roomId: '1', host: _host, key: ''),
      ]) {
        events.clear();
        await connection.connect(args);
        expect(events, [
          const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No usable comment server or key'),
        ]);
      }
      expect(connector.endpoints, isEmpty);
      await expectLater(connection.connect('not showroom args'), throwsArgumentError);
    });

    test('after close nothing is reported; another connect replaces the broadcast', () async {
      final connector = _Connector();
      final connection = ShowroomDanmakuConnection(connector: connector.call, policy: _quiet);
      final events = _record(connection);
      await connection.connect(_args);
      const next = ShowroomDanmakuArgs(roomId: '61576', host: 'online2.showroom-live.com', key: 'abcdef0123456789:1');
      await connection.connect(next);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.endpoints.last, Uri.parse('wss://online2.showroom-live.com/'));
      expect(connector.channels.last.sent, ['SUB\tabcdef0123456789:1']);
      await connector.channels.first.receive(_msg(_comment(cm: 'old socket')));
      await connector.channels.last.receive(_msg(_comment(cm: 'old key')));
      await connector.channels.last.receive(_msg(_comment(cm: 'new room'), key: next.key));
      expect([for (final m in _messages(events)) m.message], ['new room']);
      await connection.close();
      final count = events.length;
      await connector.channels.last.receive(_msg(_comment(cm: 'late'), key: next.key));
      connection.heartbeat();
      await connector.channels.last.incoming.close();
      await _wait(const Duration(milliseconds: 30));
      expect(events, hasLength(count));
      expect(connector.channels.last.closed, isTrue);
      expect(connector.channels.last.sent, ['SUB\tabcdef0123456789:1']);
      expect(connector.channels, hasLength(2));
    });

    test('a real local server: the handshake headers, SUB, PING and ACK, chat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // An upgraded WebSocket is detached from the server, so force-closing
      // the server leaves it open; close each one or the VM never exits.
      final sockets = <WebSocket>[];
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      final handshake = <String, String?>{};
      final received = <Object?>[];
      server.listen((request) async {
        handshake['path'] = request.uri.path;
        handshake['origin'] = request.headers.value('origin');
        handshake['user-agent'] = request.headers.value('user-agent');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          received.add(frame);
          if (frame == 'SUB\t$_key') {
            socket
              ..add(_msg(const {'t': 8, 'telop': null, 'telops': <Object?>[], 'interval': 6000}))
              ..add(_msg(_comment(cm: '弾き語り')));
          } else if (frame == ShowroomDanmakuProtocol.ping) {
            socket.add(ShowroomDanmakuProtocol.ack);
          }
        });
      });
      final connection = ShowroomDanmakuConnection(
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) {
          expect(endpoint, Uri.parse('wss://$_host/'));
          return connectIoSocket(
            endpoint.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        },
      );
      final events = _record(connection);
      await connection.connect(_args);
      await _until(() => _messages(events).isNotEmpty);
      connection.heartbeat();
      await _until(() => received.length == 2);
      await _wait(const Duration(milliseconds: 20));
      expect(handshake['path'], '/');
      expect(handshake['origin'], 'https://www.showroom-live.com');
      expect(handshake['user-agent'], endsWith(ShowroomApi.userAgent));
      expect(received, ['SUB\t$_key', 'PING\tshowroom']);
      expect(events.first, const DanmakuReady());
      expect(_messages(events).single.message, '弾き語り');
      expect(connection.isConnected, isTrue);
      await connection.close();
    });
  });
}
