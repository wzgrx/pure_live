// Kick's Pusher chat (M5.34): the recorded frames read frame by frame
// against fixtures/kick/danmaku/*/expected.json (an independent Python
// reading after pure_live_TV), synthetic events for what the recordings do
// not have, and the connection over a fake socket.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kick/danmaku';

List<String> _incoming(String name) => [
  for (final line in File('$_root/$name/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
];

List<Map<String, Object?>> _expected(String name) => [
  for (final item in (jsonDecode(File('$_root/$name/expected.json').readAsStringSync()) as Map)['value'] as List)
    (item as Map).cast<String, Object?>(),
];

KickDanmakuArgs _args(String name) {
  final keys =
      (jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map)['danmakuKeys'] as Map<String, Object?>;
  return KickDanmakuArgs(
    chatroomId: keys['chatroomId']! as int,
    channelId: keys['channelId']! as int,
    slug: keys['slug']! as String,
  );
}

const _room = KickDanmakuArgs(chatroomId: 3852600, channelId: 3862536, slug: 'lonche');

/// [event] of the chat channel (or [channel]) with [data] as Pusher sends it.
String _frame(String event, Object data, {String channel = 'chatrooms.3852600.v2'}) =>
    jsonEncode({'event': event, 'data': data is String ? data : jsonEncode(data), 'channel': channel});

List<LiveMessage> _read(String frame) => KickDanmakuProtocol.read(frame, _room).messages;

Map<String, Object?> _chat({
  Object? content = 'hola [emote:37226:KEKW]',
  Object? type = 'message',
  int room = 3852600,
}) => {
  'id': '07a12fcc-26c5-438a-b0be-dfdb0311d89c',
  'chatroom_id': room,
  'content': content,
  'type': type,
  'created_at': '2026-10-01T05:42:02+00:00',
  'sender': {
    'id': 90542409,
    'username': 'viewer',
    'slug': 'viewer',
    'identity': {
      'color': '#BDFF28',
      'badges': <Object>[],
      'badges_v2': [
        {
          'name': 'level',
          'metadata': {'level': 37},
        },
      ],
    },
  },
};

void main() {
  group('recordings', () {
    for (final name in ['S07-chat', 'S08-stream-end']) {
      test('$name frame by frame', () {
        final args = _args(name);
        final readings = <Map<String, Object?>>[];
        for (final text in _incoming(name)) {
          final frame = KickDanmakuProtocol.read(text, args);
          if (frame.established) readings.add({'kind': 'established'});
          if (frame.ping) readings.add({'kind': 'ping'});
          if (frame.joined) readings.add({'kind': 'joined'});
          expect(frame.error, isNull);
          for (final message in frame.messages) {
            readings.add(switch (message.type) {
              LiveMessageType.chat => {
                'kind': 'chat',
                'userName': message.userName,
                'userId': message.userId,
                'text': message.message,
                'messageId': message.messageId,
                'sentAt': message.sentAt?.millisecondsSinceEpoch,
                'color': '${message.color}',
                'userLevel': message.userLevel,
              },
              LiveMessageType.notice => {'kind': 'notice', 'text': message.message},
              _ => {'kind': message.type.name},
            });
          }
        }
        expect(readings, _expected(name));
      });
    }

    test('the end of the broadcast is a system notice', () {
      final args = _args('S08-stream-end');
      final notices = [for (final text in _incoming('S08-stream-end')) ...KickDanmakuProtocol.read(text, args).messages]
          .where((message) => message.type == LiveMessageType.notice);
      expect(notices.single.message, '直播已结束');
      expect(notices.single.data, LiveNoticeKind.system);
    });
  });

  group('chat', () {
    test('a line: emotes by name, sender, colour, level, id and time', () {
      final message = _read(_frame(r'App\Events\ChatMessageEvent', _chat())).single;
      expect(message.type, LiveMessageType.chat);
      expect(message.message, 'hola KEKW');
      expect(message.userName, 'viewer');
      expect(message.userId, '90542409');
      expect(message.color, const LiveMessageColor(0xBD, 0xFF, 0x28));
      expect(message.userLevel, '37');
      expect(message.messageId, '07a12fcc-26c5-438a-b0be-dfdb0311d89c');
      expect(message.sentAt, DateTime.utc(2026, 10, 1, 5, 42, 2));
    });

    test('replies are chat; other types, other rooms, empty lines nothing', () {
      expect(_read(_frame(r'App\Events\ChatMessageEvent', _chat(type: 'reply'))), hasLength(1));
      expect(_read(_frame(r'App\Events\ChatMessageEvent', _chat(type: 'celebration'))), isEmpty);
      expect(_read(_frame(r'App\Events\ChatMessageEvent', _chat(room: 1))), isEmpty);
      expect(_read(_frame(r'App\Events\ChatMessageEvent', _chat(content: '  '))), isEmpty);
      expect(
        _read(_frame(r'App\Events\ChatMessageEvent', _chat(), channel: 'chatrooms.1.v2')),
        isEmpty,
        reason: 'another chatroom',
      );
    });

    test('the older shape (message inside `message`) as pure_live_TV read it', () {
      final message = _read(
        _frame(r'App\Events\ChatMessageSentEvent', {
          'message': {
            'id': 'm1',
            'chatroom_id': 3852600,
            'message': 'old',
            'type': 'message',
            'created_at': 1790833322,
          },
          'user': {'id': 5, 'username': 'old_user'},
        }),
      ).single;
      expect(message.message, 'old');
      expect(message.userName, 'old_user');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1790833322000));
    });

    test('bad frames read as nothing', () {
      for (final text in ['', 'not json', '[]', '{"event": 1}', _frame(r'App\Events\ChatMessageEvent', '[')]) {
        final frame = KickDanmakuProtocol.read(text, _room);
        expect(frame.messages, isEmpty, reason: text);
        expect(frame.joined || frame.established || frame.ping || frame.error != null, isFalse, reason: text);
      }
      expect(
        KickDanmakuProtocol.read(utf8.encode(_frame(r'App\Events\ChatMessageEvent', _chat())), _room).messages,
        hasLength(1),
      );
    });
  });

  group('moderation and notices (synthetic, shapes of the public clients)', () {
    test('a deleted line, a banned viewer and a cleared chat retract', () {
      expect(
        _read(
          _frame(r'App\Events\MessageDeletedEvent', {
            'id': 'e1',
            'message': {'id': 'm9'},
          }),
        ).single.data,
        const LiveRetraction.message('m9'),
      );
      expect(
        _read(
          _frame(r'App\Events\UserBannedEvent', {
            'id': 'e2',
            'user': {'id': 77, 'username': 'x', 'slug': 'x'},
            'permanent': false,
          }),
        ).single.data,
        const LiveRetraction.user('77'),
      );
      expect(_read(_frame(r'App\Events\ChatroomClearEvent', {'id': 'e3'})).single.data, const LiveRetraction.all());
      expect(_read(_frame(r'App\Events\MessageDeletedEvent', <String, Object?>{})), isEmpty);
    });

    test('subscriptions, gifts of subscriptions and hosts are notices', () {
      final sub = _read(
        _frame(r'App\Events\SubscriptionEvent', {'chatroom_id': 3852600, 'username': 'fan', 'months': 3}),
      );
      expect(sub.single.message, 'fan 订阅了 3 个月');
      expect(sub.single.data, LiveNoticeKind.subscription);
      final gifts = _read(
        _frame(r'App\Events\GiftedSubscriptionsEvent', {
          'chatroom_id': 3852600,
          'gifted_usernames': ['a', 'b', 'c'],
          'gifter_username': 'giver',
          'gifter_total': 10,
        }),
      );
      expect(gifts.single.message, 'giver 赠送了 3 个订阅');
      final one = _read(
        _frame(r'App\Events\GiftedSubscriptionsEvent', {
          'chatroom_id': 3852600,
          'gifted_usernames': ['a'],
          'gifter_username': 'giver',
        }),
      );
      expect(one.single.message, 'giver 向 a 赠送了订阅');
      final host = _read(
        _frame(r'App\Events\StreamHostEvent', {
          'chatroom_id': 3852600,
          'host_username': 'friend',
          'number_viewers': 42,
          'optional_message': '',
        }),
      );
      expect(host.single.message, 'friend 带着 42 位观众来了');
      expect(host.single.data, LiveNoticeKind.raid);
      expect(_read(_frame(r'App\Events\SubscriptionEvent', {'chatroom_id': 1, 'username': 'fan'})), isEmpty);
    });

    test('a pinned line is a notice; polls and removed pins nothing', () {
      final pinned = _read(
        _frame(r'App\Events\PinnedMessageCreatedEvent', {
          'message': _chat(content: 'read the rules'),
          'duration': '20',
        }),
      );
      expect(pinned.single.message, '置顶了 viewer 的消息：read the rules');
      expect(pinned.single.data, LiveNoticeKind.system);
      expect(_read(_frame(r'App\Events\PinnedMessageDeletedEvent', '[]')), isEmpty);
      expect(_read(_frame(r'App\Events\PollUpdateEvent', {'poll': <String, Object?>{}})), isEmpty);
    });

    test('Kicks: a super chat with a message, a gift without', () {
      final superChat = _read(
        _frame('KicksGifted', {
          'gift_transaction_id': 't1',
          'message': 'great stream',
          'sender': {'id': 5, 'username': 'patron', 'username_color': '#FF0000'},
          'gift': {'gift_id': 'rage_quit', 'name': 'Rage Quit', 'amount': 500, 'pinned_time': 120},
          'created_at': '2026-10-01T05:42:02Z',
        }),
      ).single;
      expect(superChat.type, LiveMessageType.superChat);
      final data = superChat.data! as LiveSuperChatMessage;
      expect((data.userName, data.message, data.price, data.priceText), ('patron', 'great stream', 500, '500 Kicks'));
      // D07.2: the unit of the platform table (superChatUnits).
      expect(data.unit, LiveGiftUnit.kicks);
      expect(superChatUnits[SiteIds.kick], data.unit);
      expect(data.endTime.difference(data.startTime), const Duration(minutes: 2));
      final gift = _read(
        _frame('KicksGifted', {
          'sender': {'id': 5, 'username': 'patron'},
          'gift': {'name': 'Hype', 'amount': 100},
        }),
      ).single;
      expect(gift.type, LiveMessageType.gift);
      // E05.5: the shared text, without the sender (the line shows the name)
      // and without Chinese written in the adapter.
      expect(gift.message, 'Hype ×1');
      expect(gift.data, const KickGift(name: 'Hype', amount: 100));
      expect(
        (gift.gift?.unitPrice, gift.gift?.totalValue, gift.gift?.unit, gift.gift?.tier),
        (100, 100, LiveGiftUnit.kicks, LiveGiftTier.normal),
      );
      final unnamed = _read(
        _frame('KicksGifted', {
          'sender': {'id': 5, 'username': 'patron'},
          'gift': {'amount': 0},
        }),
      ).single;
      expect((unnamed.message, unnamed.gift?.totalValue), ('Kicks ×1', null));
    });

    test('Pusher errors and refused subscriptions ask for a reconnect', () {
      expect(
        KickDanmakuProtocol.read(
          '{"event":"pusher:error","data":{"code":4201,"message":"Pong reply not received"}}',
          _room,
        ).error,
        contains('Pong reply not received'),
      );
      expect(
        KickDanmakuProtocol.read(_frame('pusher_internal:subscription_error', {'type': 'AuthError'}), _room).error,
        isNotNull,
      );
    });
  });

  group('connection', () {
    const quiet = DanmakuSocketPolicy(heartbeatInterval: Duration.zero, reconnectBaseDelay: Duration(milliseconds: 5));

    test('subscribes after the session opens, joins on the confirmation, reads chat, answers pings', () async {
      final connector = _Connector();
      const route = HttpProxyRoute('127.0.0.1', 7897);
      final connection = KickDanmakuConnection(connector: connector.call, policy: quiet, proxy: const _Proxy(route));
      final events = _record(connection);
      await connection.connect(_room);
      expect(connector.endpoints.single, KickDanmakuProtocol.endpoint);
      expect(connector.headers.single, KickDanmakuProtocol.socketHeaders);
      expect(connector.routes.single, route);
      final socket = connector.channels.single;
      await socket.receive(r'{"event":"pusher:connection_established","data":"{\"socket_id\":\"1.2\"}"}');
      expect(socket.sent, [
        KickDanmakuProtocol.subscribe('chatrooms.3852600.v2'),
        KickDanmakuProtocol.subscribe('channel.3862536'),
      ]);
      await socket.receive(_frame(r'App\Events\ChatMessageEvent', _chat()));
      expect(_messages(events), isEmpty, reason: 'not joined yet');
      await socket.receive(_frame('pusher_internal:subscription_succeeded', '{}'));
      expect(events.whereType<DanmakuReady>(), hasLength(1));
      await socket.receive(_frame(r'App\Events\ChatMessageEvent', _chat()));
      expect(_messages(events).single.message, 'hola KEKW');
      await socket.receive('{"event":"pusher:ping","data":{}}');
      expect(socket.sent.last, KickDanmakuProtocol.pong);
      expect(connection.isConnected, isTrue);
      await connection.close();
    });

    test('a Pusher error reconnects and subscribes again', () async {
      final connector = _Connector();
      final connection = KickDanmakuConnection(connector: connector.call, policy: quiet);
      final events = _record(connection);
      await connection.connect(_room);
      final first = connector.channels.single;
      await first.receive('{"event":"pusher:connection_established","data":"{}"}');
      await first.receive(_frame('pusher_internal:subscription_succeeded', '{}'));
      await first.receive('{"event":"pusher:error","data":{"code":4200,"message":"Generic reconnect immediately"}}');
      await _until(() => connector.channels.length == 2);
      expect(events.whereType<DanmakuReconnecting>().first.reason, DanmakuInterruption.protocolError);
      final second = connector.channels.last;
      await second.receive('{"event":"pusher:connection_established","data":"{}"}');
      expect(second.sent.first, KickDanmakuProtocol.subscribe('chatrooms.3852600.v2'));
      await second.receive(_frame('pusher_internal:subscription_succeeded', '{}'));
      expect(events.whereType<DanmakuReady>(), hasLength(2));
      await connection.close();
    });

    test('no confirmation within the join timer reconnects', () async {
      final connector = _Connector();
      final connection = KickDanmakuConnection(
        connector: connector.call,
        policy: const DanmakuSocketPolicy(
          heartbeatInterval: Duration.zero,
          joinTimeout: Duration(seconds: 1),
          reconnectBaseDelay: Duration(milliseconds: 5),
        ),
      );
      await connection.connect(_room);
      await connector.channels.single.receive('{"event":"pusher:connection_established","data":"{}"}');
      await _until(() => connector.channels.length == 2);
      await connection.close();
    });

    test('the heartbeat is a Pusher ping', () async {
      final connector = _Connector();
      final connection = KickDanmakuConnection(connector: connector.call, policy: quiet);
      await connection.connect(_room);
      connection.heartbeat();
      expect(connector.channels.single.sent.last, KickDanmakuProtocol.ping);
      expect(KickDanmakuConnection.socketPolicy.heartbeatInterval, const Duration(seconds: 30));
      expect(KickDanmakuConnection.socketPolicy.joinTimeout, const Duration(seconds: 10));
      await connection.close();
    });

    test('arguments without a chatroom end the run; nothing follows a close', () async {
      final connector = _Connector();
      final connection = KickDanmakuConnection(connector: connector.call, policy: quiet);
      final events = _record(connection);
      await connection.connect(const KickDanmakuArgs(chatroomId: 0, channelId: 1, slug: 'x'));
      expect(events.whereType<DanmakuClosed>().single.reason, DanmakuCloseReason.connectionFailed);
      expect(connector.endpoints, isEmpty);
      await connection.connect(_room);
      final socket = connector.channels.single;
      await connection.close();
      final count = events.length;
      await socket.receive(_frame(r'App\Events\ChatMessageEvent', _chat()));
      expect(events, hasLength(count));
      expect(socket.closed, isTrue);
    });

    test('other arguments are refused', () async {
      final connection = KickDanmakuConnection(connector: _Connector().call, policy: quiet);
      await expectLater(connection.connect('lonche'), throwsArgumentError);
    });
  });
}

final class _Proxy implements ProxyPolicy {
  const new(this.route);

  final ProxyRoute route;

  @override
  ProxyRoute routeFor(String site, Uri url) => route;
}

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

  Future<void> receive(Object frame) async {
    if (closed) return;
    incoming.add(frame);
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Connector {
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

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
