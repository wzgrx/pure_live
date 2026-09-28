import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// What one Twitch frame held ([TwitchDanmakuProtocol.decode]).
@immutable
final class TwitchDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.replies = const [], this.loginRejected = false});

  /// Chat, in order.
  final List<LiveMessage> messages;

  /// Lines to send back at once: a `PONG` for every server `PING`.
  final List<String> replies;

  /// The server refused the chat login (a `NOTICE *`, such as "Login
  /// authentication failed").
  final bool loginRejected;
}

/// Twitch chat, IRC over a WebSocket of text frames (the codec of 3.x
/// `TwitchDanmaku`, docs/modules/M5.8-twitch.md), without I/O.
///
/// A frame holds one or more lines separated by `\r\n`. The client joins with
/// `PASS`, `NICK`, `CAP REQ` and `JOIN`; chat is `PRIVMSG` with IRCv3 tags.
abstract final class TwitchDanmakuProtocol {
  /// The chat server (3.x `serverUrl`, without a port).
  static final Uri endpoint = Uri.parse('wss://irc-ws.chat.twitch.tv');

  /// Heartbeat period (3.x `heartbeatTime`, 40 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 40);

  /// The client heartbeat line (3.x `heartbeat()`); the server answers with
  /// a `PONG`.
  static const String heartbeat = 'PING :tmi.twitch.tv';

  /// The capabilities 3.x asked for: tags (names, colours, ids, times),
  /// commands and membership.
  static const String capabilities = 'CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership';

  /// The password of an anonymous nick.
  static const String anonymousPassword = 'PASS SCHMOOPIIE';

  /// An anonymous nick: `justinfan` and 1000–99999 (3.x drew it from
  /// `Random.secure()` at every join).
  static String anonymousNick(Random random) => 'justinfan${1000 + random.nextInt(99000)}';

  /// The lines that join [channel] (3.x `joinRoom`), each sent as its own
  /// text frame: the user's [chat] login when it has both a token and a
  /// login, otherwise an anonymous nick drawn from [random]. The channel is
  /// trimmed and lower-cased, as 3.x did.
  static List<String> join(String channel, {required Random random, TwitchChatLogin? chat}) {
    final token = chat?.token.trim() ?? '';
    final login = chat?.login.trim().toLowerCase() ?? '';
    final authenticated = token.isNotEmpty && login.isNotEmpty;
    return [
      if (authenticated) 'PASS oauth:$token' else anonymousPassword,
      'NICK ${authenticated ? login : anonymousNick(random)}',
      capabilities,
      'JOIN #${channel.trim().toLowerCase()}',
    ];
  }

  static final RegExp _lineBreak = RegExp(r'\r?\n');
  static final RegExp _prefixNick = RegExp(' :?([^! ]+)!');
  static final RegExp _action = RegExp('^\u0001ACTION(?: (.*?))?\u0001?\$');

  /// Reads one frame (3.x `decodeMessage`): every line that starts with
  /// `PING` is answered with the same line as `PONG`; every `PRIVMSG` line
  /// is chat ([chat]); a `NOTICE *` sets [TwitchDanmakuFrame.loginRejected].
  /// A line that fails to decode is skipped without losing the others.
  static TwitchDanmakuFrame decode(String data) {
    final messages = <LiveMessage>[];
    final replies = <String>[];
    var loginRejected = false;
    for (final raw in data.split(_lineBreak)) {
      if (raw.startsWith('PING')) replies.add(raw.replaceFirst('PING', 'PONG').trim());
      final line = raw.trim();
      if (isLoginRejection(line)) loginRejected = true;
      try {
        final message = chat(line);
        if (message != null) messages.add(message);
      } on Object {
        // A timestamp out of DateTime's range: only this line is lost.
      }
    }
    return TwitchDanmakuFrame(messages: messages, replies: replies, loginRejected: loginRejected);
  }

  /// The chat of one trimmed [line] (3.x `parseMessages`), or null.
  ///
  /// As in 3.x, any line containing ` PRIVMSG ` counts, and the text is what
  /// follows the first ` :` after it. The name is the `display-name` tag
  /// (trimmed), else the nick before the first `!` that follows a space,
  /// else `Twitch`; the colour is the `color` tag (empty or unreadable:
  /// white); the user id, message id (`id`, unprefixed) and time
  /// (`tmi-sent-ts`, ms) come from their tags. A `/me` line loses its CTCP
  /// `ACTION` wrapper (3.x showed it).
  static LiveMessage? chat(String line) {
    if (!line.contains(' PRIVMSG ')) return null;
    final tags = <String, String>{};
    if (line.startsWith('@')) {
      final tagEnd = line.indexOf(' ');
      if (tagEnd > 1) {
        for (final entry in line.substring(1, tagEnd).split(';')) {
          final separator = entry.indexOf('=');
          if (separator < 0) continue;
          tags[entry.substring(0, separator)] = unescapeTag(entry.substring(separator + 1));
        }
      }
    }
    final messageStart = line.indexOf(' :', line.indexOf(' PRIVMSG '));
    if (messageStart < 0) return null;
    final content = line.substring(messageStart + 2);
    final displayName = tags['display-name']?.trim() ?? '';
    final userName = displayName.isNotEmpty ? displayName : (_prefixNick.firstMatch(line)?.group(1) ?? 'Twitch');
    final colorValue = int.tryParse((tags['color'] ?? '').replaceFirst('#', ''), radix: 16) ?? 0xFFFFFF;
    final timestamp = int.tryParse(tags['tmi-sent-ts'] ?? '');
    return LiveMessage(
      type: LiveMessageType.chat,
      message: _withoutAction(content),
      userName: userName,
      userId: tags['user-id'] ?? '',
      messageId: tags['id'] ?? '',
      sentAt: timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp),
      color: LiveMessageColor.numberToColor(colorValue),
    );
  }

  /// A tag value with 3.x's unescaping: `\s`, `\:`, `\r`, `\n`, then `\\`,
  /// each replaced everywhere in that order. (Values holding an escaped
  /// backslash come out differently from IRCv3's single pass; the tags read
  /// here never hold one.)
  static String unescapeTag(String value) => value
      .replaceAll(r'\s', ' ')
      .replaceAll(r'\:', ';')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\\', r'\');

  /// `\x01ACTION text\x01` (a `/me` line) as `text`; the closing `\x01` may
  /// be missing. Other text is returned as it is.
  static String _withoutAction(String text) {
    final match = _action.firstMatch(text);
    return match == null ? text : match.group(1) ?? '';
  }

  /// Whether [line] is a `NOTICE` to `*`: the server's answer to a refused
  /// login ("Login authentication failed", "Improperly formatted auth"),
  /// after which it ignores the join and drops the socket.
  static bool isLoginRejection(String line) {
    var rest = line;
    for (final marker in const ['@', ':']) {
      if (!rest.startsWith(marker)) continue;
      final space = rest.indexOf(' ');
      if (space < 0) return false;
      rest = rest.substring(space + 1).trimLeft();
    }
    return rest.startsWith('NOTICE * ');
  }
}

/// Twitch's danmaku connection (3.x `TwitchDanmaku`): IRC over one WebSocket
/// to [TwitchDanmakuProtocol.endpoint] without extra headers.
///
/// - At every open it sends `PASS`, `NICK`, `CAP REQ` and `JOIN` (with the
///   user's chat login when the arguments carry one, else a fresh anonymous
///   nick) and then counts as joined, as 3.x did.
/// - A `PING :tmi.twitch.tv` goes out every 40 s, so a socket silent for
///   max(3 × 40 s, 90 s) = 120 s is replaced; server `PING`s are answered.
/// - A refused login (the token expired) reopens the socket at once as an
///   anonymous nick for the rest of this [connect]; 3.x kept retrying the
///   refused token (docs/modules/M5.8-twitch.md, issue 1).
///
/// The app registers it as `SiteIds.twitch: () =>
/// TwitchDanmakuConnection(proxy: …)`.
final class TwitchDanmakuConnection extends DanmakuSocketConnection<TwitchDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake and [random] draws anonymous nicks
  /// (tests).
  new({super.proxy, super.connector, Random? random})
    : _random = random ?? Random.secure(),
      super(site: SiteIds.twitch, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 40 s heartbeat.
  /// No join timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: TwitchDanmakuProtocol.heartbeatInterval,
  );

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(endpoints: [TwitchDanmakuProtocol.endpoint]);

  final Random _random;
  _Join? _join;

  @override
  @protected
  Future<DanmakuSocketTarget> target(TwitchDanmakuArgs args, DanmakuRun run) async {
    _join = _Join(run, args.channel, args.chat);
    return _target;
  }

  _Join? _of(DanmakuSocketSession session) {
    final join = _join;
    return join != null && identical(join.run, session.run) ? join : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final join = _of(session);
    if (join == null) return;
    // 3.x: joinRoom, then onReady; no answer is awaited.
    TwitchDanmakuProtocol.join(join.channel, random: _random, chat: join.chat).forEach(session.send);
    session.ready();
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return;
    final frame = TwitchDanmakuProtocol.decode(text);
    frame.replies.forEach(session.send);
    frame.messages.forEach(session.message);
    if (frame.loginRejected) _loginRejected(session);
  }

  /// Drops the refused login and reopens as an anonymous nick, without a
  /// notice (reading chat needs no login).
  void _loginRejected(DanmakuSocketSession session) {
    final join = _of(session);
    if (join == null || join.chat == null) return;
    join.chat = null;
    session.markDisconnected();
    unawaited(session.reopen(_target));
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => TwitchDanmakuProtocol.heartbeat;

  @override
  @protected
  Future<void> stop() async {
    _join = null;
    await super.stop();
  }
}

/// The join of one run: the channel and the chat login still in use.
final class _Join {
  new(this.run, this.channel, this.chat);

  final DanmakuRun run;
  final String channel;
  TwitchChatLogin? chat;
}
