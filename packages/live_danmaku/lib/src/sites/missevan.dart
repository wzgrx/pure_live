import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from
/// `gift`/`send` ([MissevanDanmakuProtocol.gift]), as a [LiveGift] (E05.5):
/// [price] diamonds each, free at 0, [icon] its picture, and the combo the
/// send belongs to (D07.6).
@immutable
final class MissevanGift extends LiveGift {
  /// Creates the gift.
  ///
  /// [id] is `gift_id`, or empty; [name] `name` (`幻彩礼炮`); [count] `num`,
  /// at least 1; [comboKey] `combo.id` (the order id of the combo's first
  /// send) and [comboTotal] `combo.num`, the combo's count so far, when the
  /// send is part of a combo.
  const new({
    required super.id,
    required super.name,
    required super.count,
    required this.price,
    this.icon,
    this.luckyGift,
    super.comboKey,
    super.comboTotal,
  }) : super(unitPrice: price, totalValue: price * count, unit: LiveGiftUnit.diamond, free: price == 0, iconUrl: icon);

  /// `price` of one, in diamonds (钻石, ten to a yuan); 0 for a free gift.
  final int price;

  /// `icon_url` when it is an https URL.
  final Uri? icon;

  /// The lucky gift sent when this one was drawn from it (`lucky`; the site
  /// writes "送给主播 {lucky} ×n，抽出 {gift} ×n"), or null.
  final MissevanGift? luckyGift;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is MissevanGift &&
      other.price == price &&
      other.icon == icon &&
      other.luckyGift == luckyGift;

  @override
  int get hashCode => Object.hash(super.hashCode, price, icon, luckyGift);

  @override
  String toString() => 'MissevanGift($name ×$count)';
}

/// What one Missevan chat frame held ([MissevanDanmakuProtocol.decode]).
@immutable
final class MissevanDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.joined, this.refusal = ''});

  /// Chat, super chats (paid questions), retractions, notices, gifts and
  /// audience updates, in order.
  final List<LiveMessage> messages;

  /// The answer to this socket's join: true when the room was joined
  /// (`code 0`), false when the join was refused, null when the frame held
  /// no answer to it.
  final bool? joined;

  /// The refused join's code and text (`500030004 无法找到该聊天室`), for
  /// diagnostics.
  final String refusal;
}

/// Missevan's (猫耳 FM) chat (docs/D-弹幕/D01-平台弹幕协议/D01.13-猫耳FM弹幕/record.md), without I/O.
///
/// 3.x had no Missevan danmaku; this follows the archived v4 connector and
/// the site's own IM client (`maoer-static/assets/fm/js/bundle.*.js`):
///
/// - the socket needs a guest session: `api/user/info` sets the `FM_SESS`
///   cookie ([session]), without which the handshake is refused (HTTP 403);
/// - the client joins its room with a JSON text frame ([join]) and the
///   server answers it by the join's `uuid`;
/// - every server message is a binary frame, flag 1 and the UTF-8 length
///   (24 bits, little-endian) before a Brotli stream ([text]), holding a
///   JSON object or an array of them; the heartbeat `❤️` goes out every 30 s
///   as text and comes back as text.
abstract final class MissevanDanmakuProtocol {
  /// Heartbeat period: the site's `IMHeartbeat` (30 000 ms). The server
  /// drops a client that sends nothing for about two minutes.
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// The heartbeat, sent as a text frame; the server echoes it.
  static const String heartbeat = '❤️';

  /// How long the join's answer may take: the site gives up on any IM
  /// request after 5 s (510010002 "IM 请求超时") and reconnects.
  static const Duration joinTimeout = Duration(seconds: 5);

  /// The first byte of a binary frame whose payload is Brotli.
  static const int brotliFlag = 1;

  /// Bytes before a frame's Brotli stream: the flag and the length.
  static const int headerLength = 4;

  /// How long a paid question shows as a super chat. The site has no such
  /// time (a question waits in the room's question panel until the host
  /// answers or cancels it); 60 s is Bilibili's shortest super chat, and a
  /// question costs a few yuan (tens of diamonds), below its lowest tier.
  static const Duration questionDuration = Duration(seconds: 60);

  /// `admin`/`message_clear` `opt`: every chat line (the site's `All`).
  static const int clearAll = 1;

  /// `admin`/`message_clear` `opt`: the lines of `msg_ids` (`Specific`).
  static const int clearSpecific = 2;

  /// The site's lines for a `pk` (random or invited PK) event, as a viewer
  /// sees them (`addLocalSystemMsg` with the `PK` type).
  static const Map<String, String> pkLines = {
    'match_start': '主播正在匹配 PK 对手，请耐心等候',
    'match_success': 'PK 已开始，快送礼支持主播吧',
    'invite_refuse': '对方未接受邀请',
    'invite_timeout': '对方未接受邀请',
  };

  /// The site's line for a finished `pk` by `pk.result` (0 lost, 1 won,
  /// 2 drawn), as a viewer sees it.
  static const Map<int, String> pkResults = {1: '恭喜主播获得 PK 胜利，继续支持主播吧', 0: '主播 PK 失败，再接再厉哦', 2: '主播 PK 平局，再接再厉哦'};

  /// The `global_pk` (幻影 PK) events the site reads, and its line for each
  /// when the event carries no `message_tip`.
  static const Map<String, String?> globalPkLines = {
    'match_ready': '幻影 PK 即将开启，准备迎战！',
    'match_skip': '本场幻影 PK 已跳过',
    'match_start': '幻影 PK 匹配中，敬请期待……',
    'match_fail': '本场幻影 PK 未匹配到合适的对手',
    'match_success': '匹配成功！幻影 PK 正式开战！',
    'update': null,
    'finish': '幻影 PK 已结束',
    'match_stop': null,
    'close': null,
    'punish_finish': null,
    'mute': null,
    'forced_mute': null,
    'unmute': null,
    'forced_unmute': null,
    'invite_request': null,
    'rank_invite_request': null,
    'invite_cancel': null,
    'invite_refuse': null,
    'invite_timeout': null,
  };

  /// The site's line for a finished `global_pk` by `pk.result` without a
  /// `message_tip`.
  static const Map<int, String> globalPkResults = {1: '恭喜胜利！', 2: '本场幻影 PK 战成平局', 0: '本场幻影 PK 遗憾落败'};

  /// The events whose `raid.progress.message_tip` (花神赐福) the site shows.
  static const Set<String> raidEvents = {'match_success', 'update', 'finish', 'close'};

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  /// A cookie value: RFC 6265 cookie-octets (no space, quote, comma,
  /// semicolon or backslash); it goes into the handshake's `cookie` header.
  static final RegExp _cookieValue = RegExp(r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$');

  static final RegExp _sessionCookie = RegExp(r'^\s*FM_SESS=([^;]*)');

  /// The chat socket of room [roomId] at [url] (`MissevanDanmakuArgs.url`):
  /// [url] when it is a `wss` URL on `missevan.com` or a subdomain without
  /// user info (the session cookie goes there), for this room. A URL
  /// without `room_id` gets it (the server answers such a handshake with
  /// HTTP 400, and refuses a join of any room but the URL's); anything else
  /// is replaced by `wss://im.missevan.com/ws?room_id={roomId}`, the form
  /// the site uses.
  static Uri endpoint(Uri url, {required String roomId}) {
    final fallback = Uri(scheme: 'wss', host: 'im.missevan.com', path: '/ws', queryParameters: {'room_id': roomId});
    if (url.scheme != 'wss' ||
        url.userInfo.isNotEmpty ||
        (url.host != 'missevan.com' && !url.host.endsWith('.missevan.com'))) {
      return fallback;
    }
    final Map<String, List<String>> query;
    try {
      query = url.queryParametersAll;
    } on FormatException {
      return fallback;
    }
    final named = query['room_id'];
    if (named == null) return url.replace(queryParameters: {...query, 'room_id': roomId});
    return named.length == 1 && named.single == roomId ? url : fallback;
  }

  /// The `FM_SESS` value that [setCookie] (the `Set-Cookie` headers of the
  /// guest session answer) sets, or null. `FM_SESS.sig` is not needed.
  static String? session(Iterable<String> setCookie) {
    for (final header in setCookie) {
      final value = _sessionCookie.firstMatch(header)?.group(1)?.trim();
      if (value != null && _cookieValue.hasMatch(value)) return value;
    }
    return null;
  }

  /// Handshake headers: [headers] (the API's, with the site's `Origin`, as
  /// the site's page sends them) with the session cookie in place of any
  /// cookie they carry. The cookie is what the server requires.
  static Map<String, String> handshakeHeaders(Map<String, String> headers, String session) => {
    for (final entry in headers.entries)
      if (entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
    'cookie': 'FM_SESS=$session',
  };

  /// The join of [roomId] (sent as a number) with [uuid], as the site
  /// writes it; after the room was joined once, the site's rejoins carry
  /// `reconnect: 1` ([reconnect]).
  static String join(String roomId, {required String uuid, bool reconnect = false}) => jsonEncode({
    'action': 'join',
    'uuid': uuid,
    'type': 'room',
    'room_id': int.parse(roomId),
    if (reconnect) 'reconnect': 1,
  });

  /// A random version 4 UUID, the join's `uuid`.
  static String uuid(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// The text of a received frame, as the site's client reads it: a text
  /// frame as it is; a binary one longer than its header with flag 1,
  /// Brotli-decoded, when the result has exactly the length the header
  /// declares (decoding stops once it would exceed it). Anything else is
  /// null: another flag, a short frame, a stream that does not decode.
  static String? text(Object? data) {
    if (data is String) return data;
    if (data is! List<int> || data.length <= headerLength || data[0] != brotliFlag) return null;
    final length = data[1] | data[2] << 8 | data[3] << 16;
    final Uint8List plain;
    try {
      plain = brotliDecode(data.sublist(headerLength), maxOutput: length);
    } on FormatException {
      return null;
    }
    if (plain.length != length) return null;
    return utf8.decode(plain, allowMalformed: true);
  }

  /// Reads one frame of room [roomId]'s socket, whose join was sent with
  /// [uuid].
  ///
  /// The frame's JSON is an object or an array of objects, each named by
  /// `type` and `event`:
  ///
  /// - `room`/`join` with this [uuid]: the answer to the join
  ///   ([MissevanDanmakuFrame.joined]);
  /// - `message`/`new`, and `message`/`danmaku` (a paid danmaku, a chat
  ///   line the site flies in a bubble): chat ([chat]);
  /// - `room`/`statistics`: heat and the listeners in the room now
  ///   ([audience]);
  /// - `question`/`ask`, a paid question: a super chat ([question]), which
  ///   starts at [receivedAt] (default now) when the question has no time;
  /// - `admin`/`message_clear`: retractions ([retractions]);
  /// - `noble` (a noble title bought or renewed), `pk`, `global_pk` (幻影
  ///   PK) and `team_pk`: notices ([noble], [pk], [globalPk], [teamPk]);
  /// - `gift`/`send`: a gift ([gift]).
  ///
  /// An object naming another room (`room_id`) is skipped, as the site's
  /// client skips it; so is everything else (entries, ranks, global
  /// notices, gifts to another room of a team live, the heartbeat's echo),
  /// a frame that is not JSON, and an item that is not an object. A field of
  /// the wrong type costs only that field or that line, never the frame.
  static MissevanDanmakuFrame decode(
    Object? data, {
    required String roomId,
    required String uuid,
    DateTime? receivedAt,
  }) {
    final text = MissevanDanmakuProtocol.text(data);
    if (text == null || text == heartbeat) return const MissevanDanmakuFrame();
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const MissevanDanmakuFrame();
    }
    final messages = <LiveMessage>[];
    bool? joined;
    var refusal = '';
    for (final item in root is List ? root : [root]) {
      if (item is! Map) continue;
      final type = item['type'];
      final event = item['event'];
      if (type == 'room' && event == 'join') {
        if (item['uuid'] != uuid) continue;
        final code = item['code'];
        joined = code == 0;
        if (!joined) refusal = [_scalar(code), if (item['info'] case final String info) info].join(' ').trim();
        continue;
      }
      final room = item['room_id'];
      if (room != null && '$room' != roomId) continue;
      switch ((type, event)) {
        case ('message', 'new' || 'danmaku'):
          if (chat(item) case final message?) messages.add(message);
        case ('room', 'statistics'):
          messages.addAll(audience(item['statistics']));
        case ('question', 'ask'):
          if (question(item, receivedAt: receivedAt ?? DateTime.now()) case final message?) messages.add(message);
        case ('admin', 'message_clear'):
          messages.addAll(retractions(item));
        case ('noble', _):
          if (noble(item) case final message?) messages.add(message);
        case ('pk', _):
          messages.addAll(pk(item, roomId: roomId));
        case ('global_pk', _):
          messages.addAll(globalPk(item));
        case ('team_pk', _):
          if (teamPk(item) case final message?) messages.add(message);
        case ('gift', 'send'):
          if (gift(item) case final message?) messages.add(message);
        default:
          break;
      }
    }
    return MissevanDanmakuFrame(messages: messages, joined: joined, refusal: refusal);
  }

  /// A paid question (`question`/`ask`) as a super chat, or null when its
  /// text is blank or its price is not a whole number of zero or more.
  ///
  /// The server sends the asker as `user` and the question as `question`:
  /// `question_id`, the text `question`, `price` in diamonds (the site
  /// writes "50 钻"), `created_time` in milliseconds (the start; else
  /// [receivedAt]), and the asker again (`user_id`, `username`, `iconurl`)
  /// for a `user` that lacks them. It shows for [questionDuration]; the
  /// platform gives no colours.
  static LiveMessage? question(Map<Object?, Object?> item, {required DateTime receivedAt}) {
    final question = item['question'];
    if (question is! Map) return null;
    final text = _scalar(question['question']).trim();
    final price = _int(question['price']);
    if (text.isEmpty || price == null || price < 0) return null;
    final user = item['user'] is Map ? item['user']! as Map : const <Object?, Object?>{};
    String field(String key) => _scalar(user[key]).isNotEmpty ? _scalar(user[key]) : _scalar(question[key]);
    final id = _scalar(question['question_id']).trim();
    final created = _time(question['created_time']);
    final start = created ?? receivedAt;
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: 'SUPER_CHAT_MESSAGE',
      userId: field('user_id'),
      message: 'SUPER_CHAT_MESSAGE',
      color: LiveMessageColor.white,
      messageId: id,
      sentAt: created,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: field('username'),
        face: _https(user['iconurl']) ?? _https(question['iconurl']) ?? '',
        message: text,
        price: price,
        priceText: '$price 钻',
        startTime: start,
        endTime: start.add(questionDuration),
        backgroundColor: '',
        backgroundBottomColor: '',
      ),
    );
  }

  /// The retractions of an `admin`/`message_clear`, as the site's chat list
  /// applies it: `opt` [clearAll] takes back every chat line
  /// ([LiveRetraction.all]); [clearSpecific] the lines whose `msg_id` is in
  /// `msg_ids`, once each; any other `opt` nothing.
  static List<LiveMessage> retractions(Map<Object?, Object?> item) {
    LiveMessage retraction(LiveRetraction target) => LiveMessage(
      type: LiveMessageType.retraction,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: target,
    );
    switch (_int(item['opt'])) {
      case clearAll:
        return [retraction(const LiveRetraction.all())];
      case clearSpecific:
        final ids = item['msg_ids'];
        if (ids is! List) return const [];
        final seen = <String>{};
        return [
          for (final id in ids.map(_scalar))
            if (id.trim().isNotEmpty && seen.add(id)) retraction(LiveRetraction.message(id)),
        ];
      default:
        return const [];
    }
  }

  /// A noble title bought (`registration`) or renewed (`renewal`), in this
  /// room or, in a team live, for another host (`cross_…`, naming
  /// `room.creator_username`), as a notice in the words of the site's chat
  /// line ("我开通了神话贵族"): `观众甲 开通了神话贵族`. Null for other events
  /// or without `noble.name`.
  static LiveMessage? noble(Map<Object?, Object?> item) {
    final event = item['event'];
    final action = switch (event) {
      'registration' || 'cross_registration' => '开通',
      'renewal' || 'cross_renewal' => '续费',
      _ => null,
    };
    final noble = item['noble'];
    if (action == null || noble is! Map) return null;
    final name = _scalar(noble['name']).trim();
    if (name.isEmpty) return null;
    final user = item['user'] is Map ? item['user']! as Map : const <Object?, Object?>{};
    final userName = _scalar(user['username']).trim();
    final room = item['room'];
    final host = '$event'.startsWith('cross_') && room is Map ? _scalar(room['creator_username']).trim() : '';
    return _notice(
      '${userName.isEmpty ? '' : '$userName '}$action了${host.isEmpty ? '' : '$host的'}$name贵族',
      userName: userName,
      userId: _scalar(user['user_id']),
      sentAt: _time(item['time']),
    );
  }

  /// The notices of a `pk` event (a random or invited PK of two hosts), as
  /// a viewer sees them on the site: the 花神赐福 line of `raid` first
  /// ([raid]), then the PK line ([pkLines]; a finished PK by `pk.result`,
  /// [pkResults]; an unanswered invitation only in the inviting room,
  /// `pk.from_room_id`).
  static List<LiveMessage> pk(Map<Object?, Object?> item, {required String roomId}) {
    final pk = item['pk'] is Map ? item['pk']! as Map : const <Object?, Object?>{};
    final event = item['event'];
    final line = switch (event) {
      'finish' || 'close' => pkResults[_int(pk['result'])],
      'invite_timeout' when _scalar(pk['from_room_id']) != roomId => null,
      final String event => pkLines[event],
      _ => null,
    };
    return [?raid(item), if (line != null) _notice(line)];
  }

  /// The notices of a `global_pk` event (幻影 PK, matched by the platform),
  /// as the site's PK assistant writes them: `pk.message_tip` ([plainText])
  /// or else the site's line for the event ([globalPkLines]; a finish by
  /// `pk.result`, [globalPkResults]); an `update` only with a tip, and an
  /// event without either shows no line (the site shows a bare "PK 小助手提示").
  /// The 花神赐福 line of `raid` follows ([raid]).
  static List<LiveMessage> globalPk(Map<Object?, Object?> item) {
    final event = item['event'];
    final pk = item['pk'];
    if (event is! String || !globalPkLines.containsKey(event) || pk is! Map) return const [];
    final tip = plainText(pk['message_tip']);
    final line = tip.isNotEmpty
        ? tip
        : event == 'finish'
        ? globalPkResults[_int(pk['result'])] ?? globalPkLines[event]
        : globalPkLines[event];
    return [if (line != null) _notice(line), ?raid(item)];
  }

  /// A `team_pk` event's `pk.message_tip` ([plainText]) as a notice, as the
  /// site's team PK assistant shows it; null without one.
  static LiveMessage? teamPk(Map<Object?, Object?> item) {
    final pk = item['pk'];
    final tip = pk is Map ? plainText(pk['message_tip']) : '';
    return tip.isEmpty ? null : _notice(tip);
  }

  /// The 花神赐福 line of a PK event ([raidEvents]): `raid.progress.message_tip`
  /// ([plainText]) as a notice, or null.
  static LiveMessage? raid(Map<Object?, Object?> item) {
    if (!raidEvents.contains(item['event'])) return null;
    final raid = item['raid'];
    final progress = raid is Map ? raid['progress'] : null;
    final tip = progress is Map ? plainText(progress['message_tip']) : '';
    return tip.isEmpty ? null : _notice(tip);
  }

  /// The words of a `message_tip`, which the site shows as HTML: the grey
  /// (`#BDBDBD`) parts are the links it adds ("详情", "结算详情", "去祈福")
  /// and are left out, as are images and every other tag (a line break
  /// becomes a space); entities are decoded, runs of white space become one
  /// space. Empty for anything but text.
  static String plainText(Object? html) {
    if (html is! String) return '';
    final text = html
        .replaceAll(_linkHint, '')
        .replaceAll(_lineBreak, ' ')
        .replaceAll(_tag, '')
        .replaceAllMapped(_entity, (match) => _decodeEntity(match) ?? match[0]!);
    return text.replaceAll(_space, ' ').trim();
  }

  /// One gift of `gift`/`send`, or null without a `gift` that has a name.
  ///
  /// Fields: `gift` (`gift_id`, `name`, `num`, `price` in diamonds each,
  /// `icon_url`), the sender `user`, `time` in milliseconds, `oid` the
  /// order (all zeros for the later sends of a combo; then no message id),
  /// `lucky`, the lucky gift sent when `gift` was drawn from it, and
  /// `combo` (`id`, the first send's order; `num`, the count so far;
  /// `remain_time`, how long the page waits for the next send) when the
  /// send is part of a combo (D07.6). The text is `幻彩礼炮 ×1`.
  static LiveMessage? gift(Map<Object?, Object?> item) {
    final combo = item['combo'] is Map ? item['combo']! as Map : const <Object?, Object?>{};
    final comboKey = _scalar(combo['id']).trim();
    final comboTotal = _int(combo['num']);
    final data = _gift(
      item['gift'],
      luckyGift: _gift(item['lucky']),
      comboKey: comboKey.contains(_nonZero) ? comboKey : '',
      comboTotal: comboTotal != null && comboTotal > 0 ? comboTotal : null,
    );
    if (data == null) return null;
    final user = item['user'] is Map ? item['user']! as Map : const <Object?, Object?>{};
    final order = _scalar(item['oid']).trim();
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: _scalar(user['username']),
      userId: _scalar(user['user_id']),
      message: data.plainText,
      color: LiveMessageColor.white,
      messageId: order.contains(_nonZero) ? order : '',
      sentAt: _time(item['time']),
      data: data,
    );
  }

  static MissevanGift? _gift(Object? gift, {MissevanGift? luckyGift, String comboKey = '', int? comboTotal}) {
    if (gift is! Map) return null;
    final name = _scalar(gift['name']).trim();
    if (name.isEmpty) return null;
    final count = _int(gift['num']);
    final price = _int(gift['price']);
    final icon = _https(gift['icon_url']);
    return MissevanGift(
      id: _scalar(gift['gift_id']).trim(),
      name: name,
      count: count != null && count > 0 ? count : 1,
      price: price != null && price >= 0 ? price : 0,
      icon: icon == null ? null : Uri.parse(icon),
      luckyGift: luckyGift,
      comboKey: comboKey,
      comboTotal: comboTotal,
    );
  }

  static LiveMessage _notice(String text, {String userName = '', String userId = '', DateTime? sentAt}) => LiveMessage(
    type: LiveMessageType.notice,
    userName: userName,
    userId: userId,
    message: text,
    color: LiveMessageColor.white,
    sentAt: sentAt,
    data: LiveNoticeKind.system,
  );

  /// A positive time in milliseconds that [DateTime] can hold, or null.
  static DateTime? _time(Object? value) =>
      value is int && value > 0 && value <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  /// [value] as an https URL (protocol-relative ones get `https:`), or
  /// null.
  static String? _https(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    final url = text.startsWith('//') ? 'https:$text' : text;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? url : null;
  }

  static final RegExp _linkHint = RegExp(
    r'''<font\s+color\s*=\s*['"]?#bdbdbd['"]?\s*>.*?</font\s*>''',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _nonZero = RegExp('[^0]');
  static final RegExp _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _tag = RegExp('<[^>]*>');
  static final RegExp _entity = RegExp('&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]+);');
  static final RegExp _space = RegExp(r'\s+');

  static String? _decodeEntity(Match match) {
    final name = match[1]!;
    final code = name.startsWith('#x') || name.startsWith('#X')
        ? int.tryParse(name.substring(2), radix: 16)
        : name.startsWith('#')
        ? int.tryParse(name.substring(1))
        : null;
    if (code == null) return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '}[name];
    return code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF) ? String.fromCharCode(code) : null;
  }

  /// One chat line, or null when its `message` is blank or neither text nor
  /// a number.
  ///
  /// Fields: `message` the text (trimmed), `user.username` and
  /// `user.user_id`, `msg_id` the message id, `time` the time in
  /// milliseconds (the site's; recorded lines have none). The user's
  /// `titles` carry the level (`type` `level`) and the fan medal (`medal`:
  /// its `name` and `level`). The site gives no text colour: white.
  static LiveMessage? chat(Map<Object?, Object?> item) {
    final text = _scalar(item['message']).trim();
    if (text.isEmpty) return null;
    final user = item['user'];
    final titles = user is Map && user['titles'] is List ? user['titles'] as List<Object?> : const <Object?>[];
    Map<Object?, Object?>? title(String type) =>
        titles.whereType<Map<Object?, Object?>>().where((entry) => entry['type'] == type).firstOrNull;
    final level = _int(title('level')?['level']);
    final medal = title('medal');
    final medalLevel = _int(medal?['level']);
    final medalName = medal?['name'];
    final time = item['time'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: user is Map ? _scalar(user['username']) : '',
      userId: user is Map ? _scalar(user['user_id']) : '',
      message: text,
      color: LiveMessageColor.white,
      userLevel: level == null ? '' : '$level',
      fansName: medalName is String ? medalName : '',
      fansLevel: medalLevel == null ? '' : '$medalLevel',
      messageId: _scalar(item['msg_id']),
      sentAt: time is int && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null,
    );
  }

  /// The figures of a `room`/`statistics` message's [statistics]: `score`,
  /// the heat the site shows, and `online`, the listeners in the room now
  /// (the room lists and the detail carry an `online` that is always 0).
  /// Each is a whole number, not negative, or left out.
  static List<LiveMessage> audience(Object? statistics) {
    if (statistics is! Map) return const [];
    return [
      for (final (key, kind) in const [
        ('score', LiveAudienceMetricKind.popularity),
        ('online', LiveAudienceMetricKind.onlineViewers),
      ])
        if (_int(statistics[key]) case final value? when value >= 0)
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: LiveAudienceUpdate(kind: kind, value: value),
          ),
    ];
  }

  /// A whole number: a JSON integer or its text.
  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  static String _scalar(Object? value) => value is String || value is num ? '$value' : '';
}

/// Missevan's danmaku connection: a guest session over [LiveHttp], then the
/// room's chat socket over the shared WebSocket runtime.
///
/// - A guest session is asked at every [connect], up to three times (0.5 s
///   and 1 s apart); without one the run ends with
///   [DanmakuCloseReason.credentialsUnavailable]. Reconnects reuse it (it
///   lasts three days).
/// - At every open the socket sends the join; the room counts as joined
///   when the server accepts it, and a join not answered within 5 s drops
///   the socket, as the site's client does.
/// - A refused join asks a new guest session and reopens the socket without
///   a notice, at most three times per [connect]; the next refusal ends the
///   run with [DanmakuCloseReason.connectionFailed].
/// - A handshake refused with HTTP 401 or 403 (the session expired, B-1)
///   asks a new guest session, once per streak of failures, and the socket
///   reconnects with it through the backoff; without one the run ends with
///   [DanmakuCloseReason.credentialsUnavailable].
/// - The heartbeat goes out every 30 s and the server echoes it, so a
///   socket silent for max(3 × 30 s, 90 s) = 90 s is replaced.
///
/// The app registers it as `SiteIds.missevan: () =>
/// MissevanDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `MissevanSite` and its proxy policy.
final class MissevanDanmakuConnection extends DanmakuSocketConnection<MissevanDanmakuArgs> {
  /// Creates the connection; `http` asks for the guest sessions and [proxy]
  /// routes the socket. `connector` replaces `dart:io`'s handshake,
  /// `sessionRetryDelay` the step between session attempts, `random` the
  /// source of the join's `uuid` and `now` the clock that dates a question
  /// without a time (tests).
  new({
    required this._http,
    super.proxy,
    super.connector,
    this._sessionRetryDelay = const Duration(milliseconds: 500),
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random.secure(),
       _now = now ?? DateTime.now,
       super(site: SiteIds.missevan, policy: socketPolicy);

  /// Socket timing: the site's 30 s heartbeat and 5 s for the join's answer;
  /// the rest are the shared runtime's defaults.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: MissevanDanmakuProtocol.heartbeatInterval,
    joinTimeout: MissevanDanmakuProtocol.joinTimeout,
  );

  /// Requests per attempt to get a guest session.
  static const int sessionAttempts = 3;

  /// Longest wait for one guest session answer.
  static const Duration sessionTimeout = Duration(seconds: 5);

  /// Refused joins answered with a new session and socket, per [connect].
  static const int maxRejoins = 3;

  /// Handshake statuses that mean the session cookie was not accepted: the
  /// server answers a missing or made-up `FM_SESS` with 403 (2026-09-29);
  /// 401 is taken the same way.
  static const Set<int> sessionRefusals = {401, 403};

  final LiveHttp _http;
  final Duration _sessionRetryDelay;
  final Random _random;
  final DateTime Function() _now;
  _Room? _room;

  @override
  @protected
  Future<DanmakuSocketTarget> target(MissevanDanmakuArgs args, DanmakuRun run) async {
    final roomId = args.roomId.trim();
    if (!MissevanApi.idPattern.hasMatch(roomId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No room');
    }
    final room = _room = _Room(run, roomId, MissevanDanmakuProtocol.endpoint(args.url, roomId: roomId), args.headers);
    final session = await _session(room);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    if (session == null) throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: room.lastFailure);
    return room.target(session);
  }

  /// A guest session for [room]: up to [sessionAttempts] requests, or null
  /// when none set one or the run ended. Redirects are not followed (they
  /// would lose the cookie; the API requests do not follow them either).
  Future<String?> _session(_Room room) async {
    for (var attempt = 0; attempt < sessionAttempts; attempt++) {
      if (attempt > 0 && !await room.run.delay(_sessionRetryDelay * attempt)) return null;
      try {
        final response = await _http.send(
          LiveRequest(
            site: SiteIds.missevan,
            url: MissevanApi.guestSession,
            headers: room.headers,
            followRedirects: false,
            timeout: sessionTimeout,
            cancel: room.cancel,
          ),
        );
        if (!room.run.isActive) return null;
        final session = response.isSuccess
            ? MissevanDanmakuProtocol.session(response.headers['set-cookie'] ?? const [])
            : null;
        if (session != null) return session;
        room.lastFailure = response.isSuccess ? 'No guest session' : 'Guest session: HTTP ${response.status}';
      } on Object catch (error) {
        if (!room.run.isActive) return null;
        room.lastFailure = '$error';
      }
    }
    return null;
  }

  _Room? _of(DanmakuSocketSession session) {
    final room = _room;
    return room != null && identical(room.run, session.run) ? room : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final room = _of(session);
    if (room == null) return;
    // A socket opened: a later refused handshake starts a new streak.
    room.sessionRenewed = false;
    final uuid = room.uuid = MissevanDanmakuProtocol.uuid(_random);
    session.send(MissevanDanmakuProtocol.join(room.roomId, uuid: uuid, reconnect: room.joinedBefore));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final room = _of(session);
    if (room == null) return;
    final frame = MissevanDanmakuProtocol.decode(data, roomId: room.roomId, uuid: room.uuid, receivedAt: _now());
    frame.messages.forEach(session.message);
    switch (frame.joined) {
      case true when !session.isConnected:
        room.joinedBefore = true;
        session.ready();
      case false:
        session
          ..cancelJoinTimeout()
          ..markDisconnected();
        unawaited(_refused(session, room, frame.refusal));
      default:
        break;
    }
  }

  /// Answers a refused join with a new guest session and socket, without a
  /// notice (the archived v4 asked a new session too; the site reconnects).
  Future<void> _refused(DanmakuSocketSession session, _Room room, String refusal) async {
    if (room.refreshing) return;
    if (room.rejoins >= maxRejoins) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: $refusal');
      return;
    }
    room
      ..refreshing = true
      ..rejoins += 1;
    final String? fresh;
    try {
      fresh = await _session(room);
    } finally {
      // The new socket may be refused too; that refusal starts the next
      // round.
      room.refreshing = false;
    }
    if (!session.isActive) return;
    if (fresh == null) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: room.lastFailure);
      return;
    }
    await session.reopen(room.target(fresh));
  }

  /// A handshake refused with a [sessionRefusals] status (the session
  /// expired; B-1): asks a new guest session, once per streak of failures,
  /// and hands its cookie to the next handshake, which the backoff opens as
  /// after any failure. Without a session the run ends with
  /// [DanmakuCloseReason.credentialsUnavailable], as after a refused join.
  @override
  @protected
  Future<Map<String, String>?>? onHandshakeFailure(DanmakuSocketSession session, DanmakuHandshakeFailure failure) {
    final room = _of(session);
    if (room == null || !sessionRefusals.contains(failure.statusCode) || room.sessionRenewed) return null;
    room.sessionRenewed = true;
    return _renew(session, room);
  }

  Future<Map<String, String>?> _renew(DanmakuSocketSession session, _Room room) async {
    final fresh = await _session(room);
    if (!session.isActive) return null;
    if (fresh == null) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: room.lastFailure);
      return null;
    }
    return room.target(fresh).headers;
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => MissevanDanmakuProtocol.heartbeat;

  @override
  @protected
  Future<void> stop() async {
    _room = null;
    await super.stop();
  }
}

/// The chat of one run: its room, socket and session requests.
final class _Room {
  new(this.run, this.roomId, this.endpoint, this.headers) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final String roomId;
  final Uri endpoint;

  /// The API headers, sent with the session request and the handshake.
  final Map<String, String> headers;
  final CancelToken cancel = CancelToken();

  /// The `uuid` of the current socket's join.
  String uuid = '';

  /// Whether this run joined the room before (rejoins carry `reconnect`).
  bool joinedBefore = false;
  String lastFailure = '';
  int rejoins = 0;
  bool refreshing = false;

  /// Whether a refused handshake asked a new session since a socket last
  /// opened (B-1: once per streak of failures).
  bool sessionRenewed = false;

  DanmakuSocketTarget target(String session) =>
      DanmakuSocketTarget(endpoints: [endpoint], headers: MissevanDanmakuProtocol.handshakeHeaders(headers, session));
}
