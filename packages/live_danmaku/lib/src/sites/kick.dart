import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// Kicks sent without a message (`KicksGifted`): the [LiveMessage.data] of
/// a [LiveMessageType.gift] message, as a [LiveGift] (E05.5) of one worth
/// [amount] Kicks.
@immutable
final class KickGift extends LiveGift {
  /// Creates the gift; [name] is `gift.name`, `Kicks` when it has none.
  const new({required super.name, this.amount = 0})
    : super(unitPrice: amount > 0 ? amount : null, totalValue: amount > 0 ? amount : null, unit: LiveGiftUnit.kicks);

  /// `gift.amount`, in Kicks (100 to a US dollar); 0 when missing.
  final int amount;

  @override
  bool operator ==(Object other) => super == other && other is KickGift && other.amount == amount;

  @override
  int get hashCode => Object.hash(super.hashCode, amount);

  @override
  String toString() => 'KickGift($name, $amount Kicks)';
}

/// Kick's public chat over Pusher (pure_live_TV's `KickDanmaku`,
/// e1cca224; checked against the recordings `fixtures/kick/danmaku`),
/// without I/O.
///
/// - One WebSocket of JSON text frames to Kick's Pusher app. The server
///   opens with `pusher:connection_established`; the client then subscribes
///   to the public channels `chatrooms.<chatroomId>.v2` (chat and moderation),
///   `channel.<channelId>` (the broadcast's own events) and
///   `channel_<channelId>` (Kicks sent to the channel, `KicksGifted`; D07.7:
///   the web client listens there, `useRealtime(channel_${channelId},
///   "KicksGifted")`), without auth.
/// - `pusher_internal:subscription_succeeded` of the chat channel is the
///   join. `pusher:ping` is answered `pusher:pong`; the client pings too.
/// - Events carry their payload as a JSON string in `data`.
abstract final class KickDanmakuProtocol {
  /// Kick's Pusher endpoint (app key, protocol 7, as the web client).
  static final Uri endpoint = Uri.parse(
    'wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679?protocol=7&client=js&version=8.4.0&flash=false',
  );

  /// Handshake headers: the site's origin and the adapter's desktop UA.
  static const Map<String, String> socketHeaders = {'origin': KickApi.origin, 'user-agent': KickApi.userAgent};

  /// Client ping period (pure_live_TV's 30 s; the server's activity timeout
  /// is 120 s).
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// How long the server has to confirm the chat subscription after the
  /// socket opened (pure_live_TV's 10 s).
  static const Duration joinTimeout = Duration(seconds: 10);

  /// The client ping.
  static final String ping = jsonEncode({'event': 'pusher:ping', 'data': <String, Object?>{}});

  /// The answer to the server's ping.
  static final String pong = jsonEncode({'event': 'pusher:pong', 'data': <String, Object?>{}});

  /// The chat channel of [args].
  static String chatChannel(KickDanmakuArgs args) => 'chatrooms.${args.chatroomId}.v2';

  /// The broadcast channel of [args].
  static String broadcastChannel(KickDanmakuArgs args) => 'channel.${args.channelId}';

  /// The channel of [args]'s Kicks (`KicksGifted`, D07.7).
  static String kicksChannel(KickDanmakuArgs args) => 'channel_${args.channelId}';

  /// The subscription to [channel].
  static String subscribe(String channel) => jsonEncode({
    'event': 'pusher:subscribe',
    'data': {'auth': '', 'channel': channel},
  });

  /// [args] if they can be subscribed to: positive ids and a slug.
  static KickDanmakuArgs? checked(KickDanmakuArgs args) {
    final slug = KickApi.normalizeSlug(args.slug);
    return args.chatroomId > 0 && args.channelId > 0 && slug != null
        ? KickDanmakuArgs(chatroomId: args.chatroomId, channelId: args.channelId, slug: slug)
        : null;
  }

  /// What one frame of [args]'s connection means.
  static KickFrame read(Object? data, KickDanmakuArgs args) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null || text.length > 256 * 1024) return const KickFrame();
    final envelope = _object(text);
    if (envelope == null) return const KickFrame();
    final event = envelope['event'];
    final channel = envelope['channel'];
    switch (event) {
      case 'pusher:connection_established':
        return const KickFrame(established: true);
      case 'pusher:ping':
        return const KickFrame(ping: true);
      case 'pusher:error' || 'pusher_internal:subscription_error':
        return KickFrame(error: '$event ${_text(_object(envelope['data'])?['message'] ?? envelope['data'])}'.trim());
      case 'pusher_internal:subscription_succeeded':
        return KickFrame(joined: channel == chatChannel(args));
    }
    if (event is! String) return const KickFrame();
    final payload = _object(envelope['data']);
    if (payload == null) return const KickFrame();
    if (channel == broadcastChannel(args)) {
      return KickFrame(messages: [?broadcastEvent(event, payload, args)]);
    }
    if (channel == kicksChannel(args)) {
      return KickFrame(messages: [if (_name(event) == 'KicksGifted') ?kicks(payload)]);
    }
    if (channel != chatChannel(args)) return const KickFrame();
    return KickFrame(messages: [?chatEvent(event, payload, args)]);
  }

  /// One event of the chat channel, or null for one that shows nothing
  /// (polls, pins removed, chat modes, …).
  static LiveMessage? chatEvent(String event, Map<String, Object?> data, KickDanmakuArgs args) =>
      switch (_name(event)) {
        'ChatMessageEvent' || 'ChatMessageSentEvent' => message(data, args),
        'MessageDeletedEvent' => _retraction(_text(_object(data['message'])?['id'] ?? data['message_id']), null),
        'UserBannedEvent' => _retraction(null, _text(_object(data['user'])?['id'])),
        'ChatroomClearEvent' => _retract(const LiveRetraction.all()),
        'SubscriptionEvent' => _subscription(data, args),
        'GiftedSubscriptionsEvent' => _giftedSubscriptions(data, args),
        'StreamHostEvent' => _host(data, args),
        'PinnedMessageCreatedEvent' => _pinned(data),
        'KicksGifted' => kicks(data),
        _ => null,
      };

  /// The notice of the broadcast's end (the app shows it in the interface
  /// language, Z05.2).
  static const String streamEndedNotice = '直播已结束';

  /// One event of the broadcast channel: the end of the broadcast shows a
  /// notice (as niconico's programme end, B-11); the rest nothing.
  static LiveMessage? broadcastEvent(String event, Map<String, Object?> data, KickDanmakuArgs args) {
    if (_name(event) != 'StopStreamBroadcast') return null;
    final channel = _object(_object(data['livestream'])?['channel']);
    final id = channel == null ? null : jsonInt(channel['id']);
    if (id != null && id != args.channelId) return null;
    return _notice(streamEndedNotice, LiveNoticeKind.system);
  }

  /// A chat line (`ChatMessageEvent`; `type` `message` or `reply`, an empty
  /// one counts as `message`): the content with inline emotes
  /// (`[emote:<id>:<name>]`) shown by name, the sender's name, id and
  /// colour, the line's id and time, and the sender's Kick level (the
  /// `level` badge). A line of another chatroom, without sender or text, or
  /// of another type is null.
  static LiveMessage? message(Map<String, Object?> data, KickDanmakuArgs args) {
    final legacy = _object(data['message']);
    final line = legacy ?? data;
    final room = jsonInt(line['chatroom_id']);
    if (room != null && room != args.chatroomId) return null;
    final type = _text(line['type']);
    if (type.isNotEmpty && type != 'message' && type != 'reply') return null;
    final sender = _object(data['sender']) ?? _object(data['user']);
    final name = _text(sender?['username']);
    final content = _content(legacy == null ? line['content'] : line['message'] ?? line['content']);
    if (name.isEmpty || content.isEmpty || content.length > 16000 || name.length > 256) return null;
    final identity = _object(sender?['identity']);
    final color = int.tryParse(_text(identity?['color']).replaceFirst('#', ''), radix: 16);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name,
      userId: _text(sender?['id']),
      message: content,
      messageId: _text(line['id']),
      sentAt: _time(line['created_at']),
      userLevel: _level(identity?['badges_v2']),
      color: color == null || color < 0 || color > 0xFFFFFF
          ? LiveMessageColor.white
          : LiveMessageColor.numberToColor(color),
    );
  }

  /// Kicks sent to the streamer (`KicksGifted`, Kick's paid gifts): with a
  /// message it is a super chat of `gift.amount` Kicks, kept for the
  /// gift's `pinned_time` seconds (or by amount, as [superChatDuration]);
  /// without one a gift holding a [KickGift], text `Hell Yeah ×1` (E05.5:
  /// was a Chinese sentence with the sender's name, which the line showed
  /// twice). No recording yet: the shape is the one of the public client
  /// libraries (kick-wss).
  static LiveMessage? kicks(Map<String, Object?> data) {
    final sender = _object(data['sender']);
    final gift = _object(data['gift']);
    final name = _text(sender?['username']);
    final amount = max(jsonInt(gift?['amount']) ?? 0, 0);
    if (name.isEmpty || gift == null) return null;
    final text = _content(data['message']);
    final giftName = _text(gift['name']);
    final id = _text(data['gift_transaction_id']);
    final sentAt = _time(data['created_at']);
    if (text.isEmpty) {
      final present = KickGift(name: giftName.isEmpty ? 'Kicks' : giftName, amount: amount);
      return LiveMessage(
        type: LiveMessageType.gift,
        userName: name,
        userId: _text(sender?['id']),
        message: present.plainText,
        messageId: id,
        sentAt: sentAt,
        color: LiveMessageColor.white,
        data: present,
      );
    }
    final start = sentAt ?? DateTime.now();
    final pinned = jsonInt(gift['pinned_time']) ?? 0;
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: 'SUPER_CHAT_MESSAGE',
      message: 'SUPER_CHAT_MESSAGE',
      userId: _text(sender?['id']),
      messageId: id,
      sentAt: sentAt,
      color: LiveMessageColor.white,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: name,
        face: '',
        message: text,
        price: amount,
        priceText: amount > 0 ? '$amount Kicks' : giftName,
        unit: LiveGiftUnit.kicks,
        startTime: start,
        endTime: start.add(pinned > 0 && pinned <= 86400 ? Duration(seconds: pinned) : superChatDuration(amount)),
        backgroundColor: '',
        backgroundBottomColor: '',
      ),
    );
  }

  /// How long a Kicks super chat stays without its own pin time: the first
  /// steps of Bilibili's super chats by amount (100 Kicks is one dollar).
  static Duration superChatDuration(int amount) => switch (amount) {
    >= 10000 => const Duration(minutes: 30),
    >= 5000 => const Duration(minutes: 5),
    >= 1000 => const Duration(minutes: 2),
    _ => const Duration(minutes: 1),
  };

  static LiveMessage? _subscription(Map<String, Object?> data, KickDanmakuArgs args) {
    if (!_inRoom(data, args)) return null;
    final name = _text(data['username']);
    if (name.isEmpty) return null;
    final months = jsonInt(data['months']) ?? 0;
    return _notice(months > 1 ? '$name 订阅了 $months 个月' : '$name 订阅了频道', LiveNoticeKind.subscription, user: name);
  }

  static LiveMessage? _giftedSubscriptions(Map<String, Object?> data, KickDanmakuArgs args) {
    if (!_inRoom(data, args)) return null;
    final gifter = _text(data['gifter_username']);
    final names = [if (data['gifted_usernames'] case final List<Object?> list) ...list];
    final count = names.length;
    if (count == 0) return null;
    final giver = gifter.isEmpty ? '匿名用户' : gifter;
    return _notice(
      count == 1 ? '$giver 向 ${_text(names.first)} 赠送了订阅' : '$giver 赠送了 $count 个订阅',
      LiveNoticeKind.subscription,
      user: gifter,
    );
  }

  static LiveMessage? _host(Map<String, Object?> data, KickDanmakuArgs args) {
    if (!_inRoom(data, args)) return null;
    final host = _text(data['host_username']);
    if (host.isEmpty) return null;
    final viewers = jsonInt(data['number_viewers']) ?? 0;
    final note = _content(data['optional_message']);
    final text = viewers > 0 ? '$host 带着 $viewers 位观众来了' : '$host 转播了本频道';
    return _notice(note.isEmpty ? text : '$text：$note', LiveNoticeKind.raid, user: host);
  }

  static LiveMessage? _pinned(Map<String, Object?> data) {
    final line = _object(data['message']);
    final author = _text(_object(line?['sender'])?['username']);
    final text = _content(line?['content']);
    if (text.isEmpty) return null;
    return _notice(author.isEmpty ? '置顶消息：$text' : '置顶了 $author 的消息：$text', LiveNoticeKind.system, user: author);
  }

  static LiveMessage _notice(String text, LiveNoticeKind kind, {String user = ''}) => LiveMessage(
    type: LiveMessageType.notice,
    userName: user,
    message: text,
    color: LiveMessageColor.white,
    data: kind,
  );

  static LiveMessage? _retraction(String? messageId, String? userId) {
    if (messageId != null && messageId.isNotEmpty) return _retract(LiveRetraction.message(messageId));
    if (userId != null && userId.isNotEmpty) return _retract(LiveRetraction.user(userId));
    return null;
  }

  static LiveMessage _retract(LiveRetraction retraction) => LiveMessage(
    type: LiveMessageType.retraction,
    userName: '',
    message: '',
    color: LiveMessageColor.white,
    data: retraction,
  );

  static bool _inRoom(Map<String, Object?> data, KickDanmakuArgs args) {
    final room = jsonInt(data['chatroom_id']);
    return room == null || room == args.chatroomId;
  }

  /// `App\Events\ChatMessageEvent` → `ChatMessageEvent`.
  static String _name(String event) => event.substring(event.lastIndexOf(r'\') + 1);

  static final RegExp _emote = RegExp(r'\[emote:\d+:([^\]\s]+)\]');

  static String _content(Object? value) =>
      (value is String ? value : '').replaceAllMapped(_emote, (match) => match.group(1)!).trim();

  static String _level(Object? badges) {
    if (badges is! List) return '';
    for (final badge in badges) {
      final item = _object(badge);
      if (item?['name'] != 'level') continue;
      final level = jsonInt(_object(item!['metadata'])?['level']);
      if (level != null && level > 0) return '$level';
    }
    return '';
  }

  static DateTime? _time(Object? value) {
    if (value is int) return value > 0 && value < 8640000000 ? DateTime.fromMillisecondsSinceEpoch(value * 1000) : null;
    return value is String ? DateTime.tryParse(value) : null;
  }

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    _ => '',
  };

  /// A JSON object, or the object a JSON text holds.
  static Map<String, Object?>? _object(Object? value) {
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded.map((key, value) => MapEntry('$key', value)) : null;
    } on FormatException {
      return null;
    }
  }
}

/// What one Pusher frame means for the connection.
@immutable
final class KickFrame {
  /// Creates the reading.
  const new({this.established = false, this.joined = false, this.ping = false, this.error, this.messages = const []});

  /// The server opened the session: subscribe now.
  final bool established;

  /// The chat channel's subscription was confirmed.
  final bool joined;

  /// The server pinged: answer [KickDanmakuProtocol.pong].
  final bool ping;

  /// A Pusher error (or a refused subscription): reconnect.
  final String? error;

  /// Messages to report.
  final List<LiveMessage> messages;
}

/// Kick's chat connection (new in v4: 3.x retired Kick in 3.2.11, upstream
/// pure_live_TV brought it back), on the WebSocket runtime.
///
/// - After `pusher:connection_established` it subscribes to the chat and
///   broadcast channels of `KickDanmakuArgs`; the chat subscription's
///   confirmation is the join, which must come within 10 s.
/// - Pings every 30 s and answers the server's pings; a Pusher error
///   reconnects.
/// - Reports chat, retractions (deleted lines, banned viewers, a cleared
///   chat), notices (subscriptions, gifted subscriptions, hosts, pins, the
///   end of the broadcast), and Kicks as super chats or gifts.
///
/// The app registers it as `SiteIds.kick: () =>
/// KickDanmakuConnection(proxy: …)`.
final class KickDanmakuConnection extends DanmakuSocketConnection<KickDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake and [policy] the timing (tests).
  new({super.proxy, super.connector, super.policy = socketPolicy}) : super(site: SiteIds.kick);

  /// Socket timing: the runtime's defaults with the 30 s ping and the 10 s
  /// join timer.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: KickDanmakuProtocol.heartbeatInterval,
    joinTimeout: KickDanmakuProtocol.joinTimeout,
  );

  _Room? _room;

  @override
  @protected
  Future<DanmakuSocketTarget> target(KickDanmakuArgs args, DanmakuRun run) async {
    final checked = KickDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No chatroom to subscribe to');
    }
    _room = _Room(run, checked);
    return DanmakuSocketTarget(endpoints: [KickDanmakuProtocol.endpoint], headers: KickDanmakuProtocol.socketHeaders);
  }

  _Room? _of(DanmakuSocketSession session) {
    final room = _room;
    return room != null && identical(room.run, session.run) ? room : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {}

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final room = _of(session);
    if (room == null) return;
    final frame = KickDanmakuProtocol.read(data, room.args);
    if (frame.established) {
      session
        ..send(KickDanmakuProtocol.subscribe(KickDanmakuProtocol.chatChannel(room.args)))
        ..send(KickDanmakuProtocol.subscribe(KickDanmakuProtocol.broadcastChannel(room.args)))
        ..send(KickDanmakuProtocol.subscribe(KickDanmakuProtocol.kicksChannel(room.args)));
    }
    if (frame.ping) session.send(KickDanmakuProtocol.pong);
    if (frame.error != null) {
      session.reconnect(notice: DanmakuInterruption.protocolError, detail: frame.error!);
      return;
    }
    if (frame.joined) session.ready();
    if (!session.isConnected) return;
    frame.messages.forEach(session.message);
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => KickDanmakuProtocol.ping;

  @override
  @protected
  Future<void> stop() async {
    _room = null;
    await super.stop();
  }
}

/// The room one run reads.
final class _Room {
  const new(this.run, this.args);

  final DanmakuRun run;
  final KickDanmakuArgs args;
}
