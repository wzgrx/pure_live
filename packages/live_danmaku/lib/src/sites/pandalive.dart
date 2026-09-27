import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// PandaTV's chat (spec/sites/pandalive.md §7): a Centrifugo server
/// (JSON protocol, commands and replies with ids) with the guest token of
/// `live/play`. Without I/O.
abstract final class PandaliveProtocol {
  /// §7.1 the socket.
  static final Uri endpoint = Uri.parse('wss://chat-ws.neolive.kr/connection/websocket');

  /// §7.1 the token source.
  static final Uri play = Uri.parse('https://api.pandalive.co.kr/v1/live/play');

  /// §7.2 client ping period (centrifuge-js default).
  static const heartbeatInterval = Duration(seconds: 25);

  /// Handshake headers.
  static const Map<String, String> headers = {'origin': 'https://www.pandalive.co.kr', 'user-agent': _userAgent};

  /// §7.1 the `live/play` form for broadcaster [userId].
  static Map<String, String> playForm(String userId) => {
    'action': 'watch',
    'userId': userId,
    'password': '',
    'shareLinkType': '',
  };

  /// §7.1 the chat channel and token of a `live/play` answer, or the
  /// refusal code (`castEnd`, `needAdult`, …) when there is none.
  static ({String channel, String token})? session(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['result'] != true) return null;
      final channel = '${root['channel'] ?? ''}';
      final token = root['token'];
      if (!RegExp(r'^[0-9]+$').hasMatch(channel) || token is! String || token.split('.').length != 3) return null;
      return (channel: channel, token: token);
    } on FormatException {
      return null;
    }
  }

  /// §9 why `live/play` gave no session.
  static String refusal(String body) {
    try {
      final root = jsonDecode(body);
      final error = root is Map ? root['errorData'] : null;
      return error is Map ? '${error['code']}' : 'no token';
    } on FormatException {
      return 'not JSON';
    }
  }

  /// §7.1 the connect command.
  static TextFrame connect(String token) => TextFrame(
    jsonEncode({
      'params': {'token': token, 'name': 'js'},
      'id': 1,
    }),
  );

  /// §7.1 the subscribe command for [channel].
  static TextFrame subscribe(String channel) => TextFrame(
    jsonEncode({
      'method': 1,
      'params': {'channel': channel},
      'id': 2,
    }),
  );

  /// §7.2 a ping command with id [id].
  static TextFrame ping(int id) => TextFrame(jsonEncode({'method': 7, 'id': id}));

  /// Normal chat types (§7.3).
  static const chatTypes = {'bj', 'chatter', 'manager', 'support'};

  static const _giftNames = {'heart': '하트', 'signature': '시그니처하트', 'item': '스페셜하트'};

  /// §7.3 decodes one frame (one or more newline-separated JSON replies
  /// and pushes) for [channel].
  static FrameResult decode(Object? data, {required String channel, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final events = <DanmakuEvent>[];
    var joined = false;
    var rejected = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final Object? reply;
      try {
        reply = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (reply is! Map) continue;
      final id = reply['id'];
      if (id == 1 || id == 2) {
        if (reply['error'] != null) rejected = true;
        if (id == 2 && reply['error'] == null) joined = true;
        continue;
      }
      final result = reply['result'];
      if (result is! Map || result['type'] != null || '${result['channel']}' != channel) continue;
      final publication = result['data'];
      final message = publication is Map ? publication['data'] : null;
      if (message is! Map) continue;
      final offset = publication is Map ? publication['offset'] : null;
      final event = _event(message, offset: offset is int ? '$channel:$offset' : null, context: context);
      if (event != null) events.add(event);
    }
    return FrameResult(events: events, joined: joined, rejected: rejected);
  }

  static DateTime? _time(Object? value) =>
      value is int && value > 0 ? DateTime.fromMillisecondsSinceEpoch(value * 1000) : null;

  static DanmakuEvent? _event(
    Map<dynamic, dynamic> message, {
    required String? offset,
    required DecodeContext context,
  }) {
    final type = '${message['type']}';
    if (chatTypes.contains(type)) {
      var text = '${message['message'] ?? ''}'.trim();
      if (text.isEmpty) text = _emoticon(message['emoticon']) ?? '';
      if (text.isEmpty) return null;
      return DanmakuChat(
        room: context.room,
        session: context.session,
        receivedAt: context.receivedAt,
        id: offset == null ? null : 'pandalive:$offset',
        sentAt: _time(message['created_at']),
        userId: '${message['id'] ?? ''}',
        userName: '${message['nk'] ?? message['id'] ?? ''}',
        text: text,
      );
    }
    if (type != 'SponCoin' && type != 'ItemCoin') return null;
    final raw = message['message'];
    final Object? body;
    try {
      body = raw is String ? jsonDecode(raw) : raw;
    } on FormatException {
      return null;
    }
    if (body is! Map) return null;
    final coins = body['coin'] is int ? body['coin'] as int : int.tryParse('${body['coin']}');
    if (coins == null || coins <= 0) return null;
    final gift = type == 'ItemCoin'
        ? 'item'
        : body.containsKey('heart')
        ? 'signature'
        : 'heart';
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: offset == null ? null : 'pandalive:$offset',
      sentAt: _time(message['created_at']),
      userId: '${body['id'] ?? ''}',
      userName: '${body['nick'] ?? body['id'] ?? ''}',
      giftId: gift,
      giftName: _giftNames[gift]!,
      count: coins,
    );
  }

  /// An emoticon-only message shows the emoticon's name.
  static String? _emoticon(Object? emoticon) {
    if (emoticon is! Map) return null;
    for (final value in emoticon.values) {
      if (value is Map && value['name'] is String && (value['name'] as String).isNotEmpty) return '[${value['name']}]';
    }
    return null;
  }
}

/// PandaTV's chat connection: a fresh guest token from `live/play` for
/// every connection (it expires after 30 minutes and the server then
/// closes the socket), connect and subscribe, ping every 25 s.
final class PandaliveConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['userId']` names the
  /// broadcaster.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _userId => detail.danmakuKeys['userId'] ?? room.roomId;

  String _channel = '';
  String _token = '';
  int _pings = 2;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final LiveResponse response;
    try {
      response = await transport.http.send(
        LiveRequest.form(
          site: 'pandalive',
          url: PandaliveProtocol.play,
          fields: PandaliveProtocol.playForm(_userId),
          headers: {
            ...PandaliveProtocol.headers,
            'accept': 'application/json, text/plain, */*',
            'referer': 'https://www.pandalive.co.kr/play/$_userId',
          },
        ),
      );
    } on Object catch (error) {
      throw DanmakuStartFailure('credentials', '$error');
    }
    final session = PandaliveProtocol.session(response.text);
    if (session == null) {
      throw DanmakuStartFailure('credentials', 'live/play ${PandaliveProtocol.refusal(response.text)}');
    }
    _channel = session.channel;
    _token = session.token;
    _pings = 2;
    return SocketPlan(endpoints: [PandaliveProtocol.endpoint], headers: PandaliveProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => [PandaliveProtocol.connect(_token), PandaliveProtocol.subscribe(_channel)];

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => PandaliveProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => PandaliveProtocol.ping(++_pings);

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      PandaliveProtocol.decode(data, channel: _channel, context: context);
}
