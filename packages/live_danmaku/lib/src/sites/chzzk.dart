import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// CHZZK's chat protocol (spec/sites/chzzk.md §7), without I/O. Messages
/// are JSON; the client sends them as UTF-8 in binary frames, which the
/// server accepts, and receives text frames.
abstract final class ChzzkProtocol {
  /// Heartbeat period (§7.3).
  static const heartbeatInterval = Duration(seconds: 20);

  /// Recent chat lines asked for after joining (§7.2).
  static const recentCount = 50;

  /// Handshake headers (§7.2).
  static const Map<String, String> headers = {'origin': 'https://chzzk.naver.com', 'user-agent': _userAgent};

  /// §7.2 the chat server of [chatChannelId]: `kr-ss<n>` with `n` the sum of
  /// its character codes modulo 9, plus 1.
  static Uri endpoint(String chatChannelId) {
    final server = chatChannelId.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 9 + 1;
    return Uri.parse('wss://kr-ss$server.chat.naver.com/chat');
  }

  /// §7.1 the access token request.
  static Uri tokenUrl(String chatChannelId) => Uri.https('comm-api.game.naver.com', '/nng_main/v1/chats/access-token', {
    'channelId': chatChannelId,
    'chatType': 'STREAMING',
  });

  /// §7.1 the access token of a token response; null when absent.
  static String? accessToken(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['code'] != 200) return null;
      final content = root['content'];
      final token = content is Map ? content['accessToken'] : null;
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  static List<int> _frame(Map<String, Object?> message) => utf8.encode(jsonEncode(message));

  /// §7.2 the join message (anonymous, read only).
  static List<int> join(String chatChannelId, String token) => _frame({
    'ver': '3',
    'cmd': 100,
    'svcid': 'game',
    'cid': chatChannelId,
    'bdy': {'uid': null, 'devType': 2001, 'accTkn': token, 'auth': 'READ'},
    'tid': 1,
  });

  /// §7.2 the recent chat request after joining with session [sid].
  static List<int> recent(String chatChannelId, String sid) => _frame({
    'ver': '3',
    'cmd': 5101,
    'svcid': 'game',
    'cid': chatChannelId,
    'sid': sid,
    'bdy': {'recentMessageCount': recentCount},
    'tid': 2,
  });

  /// §7.3 the client ping.
  static List<int> ping() => _frame({'ver': '3', 'cmd': 0});

  /// §7.3 the answer to a server ping.
  static List<int> pong() => _frame({'ver': '3', 'cmd': 10000});

  /// §7.2–§7.4 decodes one received message of [chatChannelId]'s chat.
  static FrameResult decode(Object? data, {required String chatChannelId, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return FrameResult.empty;
    }
    if (decoded is! Map) return FrameResult.empty;
    final cmd = decoded['cmd'];
    switch (cmd) {
      case 0:
        return FrameResult(replies: [pong()]);
      case 10100:
        final body = decoded['bdy'];
        final sid = body is Map ? body['sid'] : null;
        if (decoded['retCode'] != 0 || sid is! String) return const FrameResult(rejected: true);
        return FrameResult(joined: true, replies: [recent(chatChannelId, sid)]);
      case 93101 || 93102:
        final items = decoded['bdy'];
        if (items is! List) return FrameResult.empty;
        return FrameResult(events: _messages(items, context, recent: false));
      case 15101:
        final body = decoded['bdy'];
        final items = body is Map ? body['messageList'] : null;
        if (items is! List) return FrameResult.empty;
        return FrameResult(events: _messages(items, context, recent: true));
      default:
        return FrameResult.empty;
    }
  }

  /// §7.4 chat and donation items; the live (93101/93102) and recent
  /// (15101) forms differ only in field names. The last member count of a
  /// live frame becomes one online figure.
  static List<DanmakuEvent> _messages(List<dynamic> items, DecodeContext context, {required bool recent}) {
    final events = <DanmakuEvent>[];
    int? members;
    for (final item in items) {
      if (item is! Map) continue;
      try {
        members = _int(item[recent ? 'memberCount' : 'mbrCnt']) ?? members;
        events.addAll(_message(item, context, recent: recent));
      } on Object {
        // One malformed item must not drop the rest of the frame.
      }
    }
    if (!recent && members != null && members >= 0) {
      events.add(
        DanmakuOnline(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          audience: AudienceKind.online,
          value: members,
        ),
      );
    }
    return events;
  }

  static List<DanmakuEvent> _message(Map<dynamic, dynamic> item, DecodeContext context, {required bool recent}) {
    final status = item[recent ? 'messageStatusType' : 'msgStatusType'];
    if (status != null && status != 'NORMAL') return const [];
    final type = _int(item[recent ? 'messageTypeCode' : 'msgTypeCode']);
    final text = '${item[recent ? 'content' : 'msg'] ?? ''}'.trim();
    final userId = '${item[recent ? 'userId' : 'uid'] ?? ''}';
    final time = _int(item[recent ? 'messageTime' : 'msgTime']);
    final profile = _object(item['profile']);
    final extras = _object(item['extras']);
    final anonymous = extras?['isAnonymous'] == true;
    final name = anonymous ? '匿名' : '${profile?['nickname'] ?? ''}';
    final sentAt = time == null || time <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(time);
    final id = userId.isEmpty || time == null ? null : 'chzzk:$userId:$time';
    final events = <DanmakuEvent>[];
    final amount = _int(extras?['payAmount']);
    if (type == 10 || amount != null) {
      if (amount != null && amount > 0) {
        events.add(
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '$id:gift',
            sentAt: sentAt,
            userId: anonymous ? '' : userId,
            userName: name,
            giftName: '치즈',
            count: amount,
          ),
        );
      }
    } else if (type != null && type != 1) {
      // Images, stickers and system lines carry no chat text.
      return const [];
    }
    if (text.isNotEmpty) {
      events.add(
        DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: anonymous ? '' : userId,
          userName: name,
          text: text,
        ),
      );
    }
    return events;
  }

  static Map<dynamic, dynamic>? _object(Object? value) {
    if (value is Map) return value;
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
}

/// CHZZK's chat connection: an anonymous token per start, one server, a
/// 20 s ping.
final class ChzzkConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['chatChannelId']` is
  /// the chat channel (absent when the live has no public chat).
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String? _token;

  String get _channel => detail.danmakuKeys['chatChannelId'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final channel = _channel;
    if (channel.isEmpty) throw const DanmakuStartFailure('credentials', 'no chatChannelId');
    final LiveResponse response;
    try {
      response = await transport.http.send(
        LiveRequest(site: 'chzzk', url: ChzzkProtocol.tokenUrl(channel), headers: ChzzkProtocol.headers),
      );
    } on Object catch (error) {
      throw DanmakuStartFailure('credentials', '$error');
    }
    final token = response.isSuccess ? ChzzkProtocol.accessToken(response.text) : null;
    if (token == null) throw DanmakuStartFailure('credentials', 'access-token HTTP ${response.status}');
    _token = token;
    return SocketPlan(endpoints: [ChzzkProtocol.endpoint(channel)], headers: ChzzkProtocol.headers);
  }

  @override
  List<List<int>> openFrames() {
    final token = _token;
    return token == null ? const [] : [ChzzkProtocol.join(_channel, token)];
  }

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => ChzzkProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => ChzzkProtocol.ping();

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      ChzzkProtocol.decode(data, chatChannelId: _channel, context: context);
}
