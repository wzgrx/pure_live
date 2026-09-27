import 'dart:convert';
import 'dart:math';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:meta/meta.dart';

/// One IRC line: `@tags :prefix COMMAND params :trailing` (IRCv3 tags).
@immutable
final class TwitchIrcMessage {
  /// Creates a message.
  const new({required this.command, this.tags = const {}, this.prefix, this.params = const []});

  /// Tags with their escapes resolved.
  final Map<String, String> tags;

  /// `nick!user@host` or `tmi.twitch.tv`; null when absent.
  final String? prefix;

  /// Command or three-digit numeric.
  final String command;

  /// Middle parameters, then the trailing one.
  final List<String> params;

  /// The sender's nick (the prefix before `!`).
  String? get nick {
    final value = prefix;
    if (value == null) return null;
    final bang = value.indexOf('!');
    return bang < 0 ? null : value.substring(0, bang);
  }
}

/// Twitch chat over IRC-on-WebSocket (spec/sites/twitch.md §7), without I/O.
abstract final class TwitchProtocol {
  /// The chat server.
  static final Uri endpoint = Uri.parse('wss://irc-ws.chat.twitch.tv:443');

  /// Client keep-alive (the server also pings about every five minutes).
  static const heartbeatInterval = Duration(seconds: 60);

  /// An anonymous nick: `justinfan` and a number.
  static String anonymousNick(Random random) => 'justinfan${1000 + random.nextInt(89000)}';

  /// The login lines, sent at once on open: capabilities, the anonymous
  /// password and nick, the channel.
  static List<String> login({required String nick, required String channel}) => [
    'CAP REQ :twitch.tv/tags twitch.tv/commands',
    'PASS SCHMOOPIIE',
    'NICK $nick',
    'JOIN #$channel',
  ];

  /// The client keep-alive line.
  static const ping = 'PING :tmi.twitch.tv';

  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final unit = value[i];
      if (unit != r'\' || i + 1 >= value.length) {
        if (unit != r'\') out.write(unit);
        continue;
      }
      final next = value[++i];
      out.write(switch (next) {
        's' => ' ',
        ':' => ';',
        'r' => '\r',
        'n' => '\n',
        _ => next,
      });
    }
    return out.toString();
  }

  /// Parses one line; null for an empty or malformed one.
  static TwitchIrcMessage? parse(String line) {
    var rest = line.trimRight();
    if (rest.isEmpty) return null;
    final tags = <String, String>{};
    if (rest.startsWith('@')) {
      final space = rest.indexOf(' ');
      if (space < 0) return null;
      for (final entry in rest.substring(1, space).split(';')) {
        final equals = entry.indexOf('=');
        if (equals < 0) {
          if (entry.isNotEmpty) tags[entry] = '';
        } else {
          tags[entry.substring(0, equals)] = _unescape(entry.substring(equals + 1));
        }
      }
      rest = rest.substring(space + 1).trimLeft();
    }
    String? prefix;
    if (rest.startsWith(':')) {
      final space = rest.indexOf(' ');
      if (space < 0) return null;
      prefix = rest.substring(1, space);
      rest = rest.substring(space + 1).trimLeft();
    }
    final trailingAt = rest.indexOf(' :');
    final head = trailingAt < 0 ? rest : rest.substring(0, trailingAt);
    final words = head.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return null;
    return TwitchIrcMessage(
      tags: tags,
      prefix: prefix,
      command: words.first,
      params: [...words.skip(1), if (trailingAt >= 0) rest.substring(trailingAt + 2)],
    );
  }

  /// The lines of one WebSocket message.
  static Iterable<TwitchIrcMessage> messages(String data) sync* {
    for (final line in const LineSplitter().convert(data)) {
      final message = parse(line);
      if (message != null) yield message;
    }
  }

  /// §7.3 a `PRIVMSG` to [channel] as a chat line; `/me` text loses its
  /// CTCP wrapper. Another channel's line is not this room's (CONN-5).
  static DanmakuChat? chat(TwitchIrcMessage message, {required String channel, required DecodeContext context}) {
    if (message.command != 'PRIVMSG' || message.params.length < 2) return null;
    if (message.params.first.toLowerCase() != '#$channel') return null;
    var text = message.params[1];
    if (text.startsWith('\u0001ACTION ') && text.endsWith('\u0001')) {
      text = text.substring(8, text.length - 1);
    }
    if (text.trim().isEmpty) return null;
    final tags = message.tags;
    final display = tags['display-name']?.trim() ?? '';
    final colour = tags['color'] ?? '';
    final sent = int.tryParse(tags['tmi-sent-ts'] ?? '');
    final id = tags['id'] ?? '';
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id.isEmpty ? null : 'twitch:$id',
      sentAt: sent == null ? null : DateTime.fromMillisecondsSinceEpoch(sent, isUtc: true),
      userId: tags['user-id'] ?? '',
      userName: display.isNotEmpty ? display : message.nick ?? '',
      text: text,
      color: colour.length == 7 && colour.startsWith('#')
          ? int.tryParse(colour.substring(1), radix: 16) ?? DanmakuColors.white
          : DanmakuColors.white,
    );
  }
}

/// Twitch's chat connection (spec/sites/twitch.md §7): anonymous IRC over a
/// WebSocket with text frames; joined on the channel's `ROOMSTATE` or our
/// own `JOIN`; server `PING`s answered; 60 s client ping.
final class TwitchConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['login']` (or the room
  /// id) is the channel.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy, Random? random})
    : _random = random ?? Random.secure();

  final Random _random;
  var _nick = '';
  var _joined = false;

  String get _channel => (detail.danmakuKeys['login'] ?? room.roomId).toLowerCase();

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    if (!RegExp(r'^[a-z0-9_]{1,25}$').hasMatch(_channel)) {
      throw const DanmakuStartFailure('noRoom', 'twitch login missing');
    }
    return SocketPlan(endpoints: [TwitchProtocol.endpoint], headers: const {'Origin': 'https://www.twitch.tv'});
  }

  @override
  List<List<int>> openFrames() {
    _nick = TwitchProtocol.anonymousNick(_random);
    _joined = false;
    return [for (final line in TwitchProtocol.login(nick: _nick, channel: _channel)) utf8.encode(line)];
  }

  @override
  bool get textFrames => true;

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get authTimeout => const Duration(seconds: 10);

  @override
  Duration get heartbeatInterval => TwitchProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => utf8.encode(TwitchProtocol.ping);

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    final text = switch (data) {
      final String value => value,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final events = <DanmakuEvent>[];
    final replies = <List<int>>[];
    var joinedNow = false;
    var rejected = false;
    for (final message in TwitchProtocol.messages(text)) {
      switch (message.command) {
        case 'PING':
          replies.add(utf8.encode('PONG :${message.params.lastOrNull ?? 'tmi.twitch.tv'}'));
        case 'JOIN' || 'ROOMSTATE':
          final own = message.command == 'ROOMSTATE' || message.nick == _nick;
          if (own && message.params.firstOrNull?.toLowerCase() == '#$_channel' && !_joined) {
            _joined = joinedNow = true;
          }
        case 'NOTICE' when !_joined && (message.params.lastOrNull ?? '').toLowerCase().contains('auth'):
          rejected = true;
        case 'RECONNECT':
          rejected = true;
        case 'PRIVMSG':
          final chat = TwitchProtocol.chat(message, channel: _channel, context: context);
          if (chat != null) events.add(chat);
      }
    }
    return FrameResult(events: events, replies: replies, joined: joinedNow, rejected: rejected);
  }
}
