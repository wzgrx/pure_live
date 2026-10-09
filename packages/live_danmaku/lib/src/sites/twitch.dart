import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// A cheer of a [LiveMessageType.gift] message (`LiveMessage.data`): Bits
/// given with a chat line (`PRIVMSG` with a `bits` tag;
/// [TwitchDanmakuProtocol.cheer], D07.6), as a [LiveGift] of kind
/// [LiveGiftKind.tip]: [name] is the currency, the value [bits] in
/// [LiveGiftUnit.bits]. Each cheer is its own line ([comboKey] is its
/// message's), as its words are its own.
@immutable
final class TwitchCheer extends LiveGift {
  /// Creates the cheer of [bits] (at least 1) with combo key [comboKey].
  const new({required this.bits, required super.comboKey})
    : super(
        name: TwitchDanmakuProtocol.bitsName,
        kind: LiveGiftKind.tip,
        unitPrice: bits,
        totalValue: bits,
        unit: LiveGiftUnit.bits,
      );

  /// The `bits` tag.
  final int bits;

  @override
  bool operator ==(Object other) => super == other && other is TwitchCheer && other.bits == bits;

  @override
  int get hashCode => Object.hash(super.hashCode, bits);

  @override
  String toString() => 'TwitchCheer($bits)';
}

/// The community gift a subscription notice belongs to (D07.6): the
/// `msg-param-community-gift-id`, whether it is the gift's announcement
/// (`submysterygift`: `count` subscriptions, `msg-param-mass-gift-count`)
/// or one of the subscriptions it gives (`subgift`).
typedef TwitchCommunityGift = ({String id, bool announcement, int count});

/// What one Twitch frame held ([TwitchDanmakuProtocol.decode]).
@immutable
final class TwitchDanmakuFrame {
  /// Creates the result.
  const new({
    this.messages = const [],
    this.replies = const [],
    this.loginRejected = false,
    this.reconnect = false,
    this.communityGifts = const {},
  });

  /// Chat, notices and retractions, in order.
  final List<LiveMessage> messages;

  /// The subscription notices of [messages] that belong to a community gift
  /// (D07.6), by the notice itself (an identity map): the connection shows
  /// a community gift as its announcement only.
  final Map<LiveMessage, TwitchCommunityGift> communityGifts;

  /// Lines to send back at once: a `PONG` for every server `PING`.
  final List<String> replies;

  /// The server refused the chat login (a `NOTICE *`, such as "Login
  /// authentication failed").
  final bool loginRejected;

  /// The server is about to drop the socket for maintenance (`RECONNECT`)
  /// and asks the client to connect and join again.
  final bool reconnect;
}

/// One IRC line split as IRCv3 does: `@tags :prefix COMMAND params :trailing`.
///
/// Used for the commands 3.x did not read (B-7); chat keeps 3.x's own
/// reading ([TwitchDanmakuProtocol.chat]).
@immutable
final class TwitchIrcLine {
  /// Creates the line.
  const new({required this.command, this.tags = const {}, this.prefix, this.params = const [], this.trailing});

  /// Splits a trimmed [line]; null when it has no command. Tag values are
  /// unescaped in one pass from left to right (IRCv3: `\:` `;`, `\s` space,
  /// `\\` backslash, `\r`, `\n`, any other escaped character itself, a
  /// lone trailing backslash dropped).
  static TwitchIrcLine? parse(String line) {
    var rest = line;
    final tags = <String, String>{};
    if (rest.startsWith('@')) {
      final space = rest.indexOf(' ');
      if (space < 0) return null;
      for (final entry in rest.substring(1, space).split(';')) {
        if (entry.isEmpty) continue;
        final separator = entry.indexOf('=');
        if (separator < 0) {
          tags[entry] = '';
        } else {
          tags[entry.substring(0, separator)] = unescape(entry.substring(separator + 1));
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
    final trailingStart = rest.startsWith(':') ? 0 : rest.indexOf(' :');
    final head = trailingStart < 0 ? rest : rest.substring(0, trailingStart);
    final trailing = trailingStart < 0 ? null : rest.substring(trailingStart + (trailingStart == 0 ? 1 : 2));
    final words = head.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return null;
    return TwitchIrcLine(
      tags: tags,
      prefix: prefix,
      command: words.first,
      params: words.sublist(1),
      trailing: trailing,
    );
  }

  /// An IRCv3 tag value unescaped in one pass.
  static String unescape(String value) {
    if (!value.contains(r'\')) return value;
    final out = StringBuffer();
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char != r'\') {
        out.write(char);
        continue;
      }
      if (++index == value.length) break;
      out.write(switch (value[index]) {
        ':' => ';',
        's' => ' ',
        'r' => '\r',
        'n' => '\n',
        final other => other,
      });
    }
    return out.toString();
  }

  /// Tags, unescaped; a tag without `=` has an empty value.
  final Map<String, String> tags;

  /// The source (`tmi.twitch.tv`, `nick!user@host`), without the colon.
  final String? prefix;

  /// The command (`USERNOTICE`, `001`).
  final String command;

  /// The middle parameters (the channel).
  final List<String> params;

  /// The last parameter, after ` :`; null when the line has none.
  final String? trailing;
}

/// Twitch chat, IRC over a WebSocket of text frames (the codec of 3.x
/// `TwitchDanmaku`, docs/D-弹幕/D01-平台弹幕协议/D01.9-Twitch弹幕/record.md), without I/O.
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

  /// The `msg-id`s of a `USERNOTICE` shown as [LiveNoticeKind.subscription]:
  /// subscribing, renewing, gifting subscriptions (named, anonymous, to the
  /// community) and continuing or upgrading one (B-7).
  static const Set<String> subscriptionNotices = {
    'sub',
    'resub',
    'extendsub',
    'subgift',
    'anonsubgift',
    'submysterygift',
    'anonsubmysterygift',
    'giftpaidupgrade',
    'anongiftpaidupgrade',
    'primepaidupgrade',
    'communitypayforward',
    'standardpayforward',
  };

  /// The `msg-id`s that announce a community gift (D07.6).
  static const Set<String> communityGiftAnnouncements = {'submysterygift', 'anonsubmysterygift'};

  /// The `msg-id`s of the subscriptions a community gift gives (D07.6).
  static const Set<String> communityGiftMembers = {'subgift', 'anonsubgift'};

  /// How long a subscription of a community gift waits for the gift's
  /// announcement (D07.6): the recordings have it 0.6 s before or after.
  /// One whose announcement does not come in time is shown on its own.
  static const Duration communityGiftWait = Duration(seconds: 2);

  /// How long a community gift's announcement leaves out the subscriptions
  /// it gives that are still to come.
  static const Duration communityGiftLifetime = Duration(minutes: 1);

  /// The currency a cheer gives (`TwitchCheer.name`): Twitch's own name.
  static const String bitsName = 'Bits';

  /// The system notice reported once per `connect` when
  /// Twitch refused the stored chat login and chat went on anonymously (B-7).
  static const LiveMessage cookieExpiredNotice = LiveMessage(
    type: LiveMessageType.notice,
    userName: '',
    message: 'Twitch 的 Cookie 已失效，弹幕已改为匿名接收，请重新填写 Twitch Cookie',
    color: LiveMessageColor.white,
    data: LiveNoticeKind.system,
  );

  /// Reads one frame (3.x `decodeMessage`): every line that starts with
  /// `PING` is answered with the same line as `PONG`; every `PRIVMSG` line
  /// is chat ([chat]), after its cheer when it gives Bits ([cheer], D07.6);
  /// a `NOTICE *` sets [TwitchDanmakuFrame.loginRejected].
  /// `CLEARMSG`, `CLEARCHAT` and `USERNOTICE` become retractions, notices
  /// and chat ([command]); `RECONNECT` sets [TwitchDanmakuFrame.reconnect]
  /// (B-7; 3.x read none of them); a subscription notice of a community
  /// gift is marked ([communityGift], D07.6). A line that fails to decode is
  /// skipped without losing the others.
  static TwitchDanmakuFrame decode(String data) {
    final messages = <LiveMessage>[];
    final community = Map<LiveMessage, TwitchCommunityGift>.identity();
    final replies = <String>[];
    var loginRejected = false;
    var reconnect = false;
    for (final raw in data.split(_lineBreak)) {
      if (raw.startsWith('PING')) replies.add(raw.replaceFirst('PING', 'PONG').trim());
      final line = raw.trim();
      if (isLoginRejection(line)) loginRejected = true;
      try {
        final irc = TwitchIrcLine.parse(line);
        switch (irc?.command) {
          case 'RECONNECT':
            reconnect = true;
          case 'CLEARMSG' || 'CLEARCHAT' || 'USERNOTICE':
            final read = command(irc!);
            if (communityGift(irc) case final gift?) {
              for (final message in read) {
                if (message.type == LiveMessageType.notice) community[message] = gift;
              }
            }
            messages.addAll(read);
          default:
            final message = chat(line);
            if (message != null) {
              if (irc != null) messages.addAll([?cheer(irc, message)]);
              messages.add(message);
            }
        }
      } on Object {
        // A timestamp out of DateTime's range: only this line is lost.
      }
    }
    return TwitchDanmakuFrame(
      messages: messages,
      replies: replies,
      loginRejected: loginRejected,
      reconnect: reconnect,
      communityGifts: community,
    );
  }

  /// The cheer of a `PRIVMSG` [line] whose chat is [chat] (D07.6): its
  /// `bits` tag above 0, as a gift of [chat]'s sender, time and colour,
  /// with the id `<chat's id>:bits` (the chat line keeps its own); the
  /// words stay [chat]'s. Null without Bits.
  static LiveMessage? cheer(TwitchIrcLine line, LiveMessage chat) {
    final bits = int.tryParse(line.tags['bits']?.trim() ?? '');
    if (line.command != 'PRIVMSG' || bits == null || bits <= 0) return null;
    final id = chat.messageId;
    final key = id.isNotEmpty ? 'bits:$id' : 'bits:${chat.userId}:${chat.sentAt?.millisecondsSinceEpoch ?? ''}';
    final gift = TwitchCheer(bits: bits, comboKey: key);
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: chat.userName,
      userId: chat.userId,
      message: gift.plainText,
      color: chat.color,
      messageId: id.isEmpty ? '' : '$id:bits',
      sentAt: chat.sentAt,
      data: gift,
    );
  }

  /// The community gift of a `USERNOTICE` [line] (D07.6): a
  /// [communityGiftAnnouncements] or [communityGiftMembers] notice with a
  /// `msg-param-community-gift-id`; the announcement's count is
  /// `msg-param-mass-gift-count` (1 when missing). Null otherwise.
  static TwitchCommunityGift? communityGift(TwitchIrcLine line) {
    if (line.command != 'USERNOTICE') return null;
    final kind = line.tags['msg-id'] ?? '';
    final announcement = communityGiftAnnouncements.contains(kind);
    if (!announcement && !communityGiftMembers.contains(kind)) return null;
    final id = line.tags['msg-param-community-gift-id']?.trim() ?? '';
    if (id.isEmpty) return null;
    final count = int.tryParse(line.tags['msg-param-mass-gift-count'] ?? '') ?? 1;
    return (id: id, announcement: announcement, count: count > 0 ? count : 1);
  }

  /// The messages of a `CLEARMSG`, `CLEARCHAT` or `USERNOTICE` [line] (B-7),
  /// as Twitch's web chat reads them:
  ///
  /// - `CLEARMSG` (a moderator deleted one message): a retraction of the
  ///   message `target-msg-id`;
  /// - `CLEARCHAT` naming a user (a timeout or a ban): a retraction of every
  ///   message of `target-user-id`; without a user (the chat was cleared):
  ///   a retraction of everything. A user named without an id cannot be
  ///   matched and is skipped, never taken for a clear;
  /// - `USERNOTICE`: the `system-msg` as a notice, a
  ///   [LiveNoticeKind.subscription] for [subscriptionNotices], a
  ///   [LiveNoticeKind.raid] for `raid`, [LiveNoticeKind.system] otherwise
  ///   (none when the text is empty); then the viewer's own words, when
  ///   there are any, as their chat carrying the notice's `id`. An
  ///   `announcement` has no `system-msg`: its words are the system notice.
  ///   A `sharedchatnotice` (an event of a channel sharing the chat) counts
  ///   as its `source-msg-id`.
  ///
  /// Retractions carry no message id of their own (Twitch gives none).
  /// Other commands give nothing.
  static List<LiveMessage> command(TwitchIrcLine line) {
    final tags = line.tags;
    final sentAt = _time(tags['tmi-sent-ts']);
    LiveMessage retraction(LiveRetraction target) => LiveMessage(
      type: LiveMessageType.retraction,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: target,
      sentAt: sentAt,
    );
    switch (line.command) {
      case 'CLEARMSG':
        final target = tags['target-msg-id']?.trim() ?? '';
        return [if (target.isNotEmpty) retraction(LiveRetraction.message(target))];
      case 'CLEARCHAT':
        final user = tags['target-user-id']?.trim() ?? '';
        if (user.isNotEmpty) return [retraction(LiveRetraction.user(user))];
        return [if (line.trailing == null) retraction(const LiveRetraction.all())];
      case 'USERNOTICE':
        final noticeId = tags['msg-id'] ?? '';
        final kind = noticeId == 'sharedchatnotice' ? tags['source-msg-id'] ?? '' : noticeId;
        final displayName = tags['display-name']?.trim() ?? '';
        final userName = displayName.isNotEmpty ? displayName : tags['login']?.trim() ?? '';
        final userId = tags['user-id'] ?? '';
        final words = line.trailing?.trim() ?? '';
        final announcement = kind == 'announcement';
        final text = announcement ? words : tags['system-msg']?.trim() ?? '';
        return [
          if (text.isNotEmpty)
            LiveMessage(
              type: LiveMessageType.notice,
              userName: userName,
              userId: userId,
              message: text,
              color: LiveMessageColor.white,
              data: subscriptionNotices.contains(kind)
                  ? LiveNoticeKind.subscription
                  : kind == 'raid'
                  ? LiveNoticeKind.raid
                  : LiveNoticeKind.system,
              sentAt: sentAt,
            ),
          if (!announcement && words.isNotEmpty)
            LiveMessage(
              type: LiveMessageType.chat,
              userName: userName.isNotEmpty ? userName : 'Twitch',
              userId: userId,
              message: words,
              color: LiveMessageColor.numberToColor(
                int.tryParse((tags['color'] ?? '').replaceFirst('#', ''), radix: 16) ?? 0xFFFFFF,
              ),
              messageId: tags['id'] ?? '',
              sentAt: sentAt,
            ),
        ];
    }
    return const [];
  }

  static DateTime? _time(String? value) {
    final timestamp = int.tryParse(value ?? '');
    return timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp);
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
///   refused token (docs/D-弹幕/D01-平台弹幕协议/D01.9-Twitch弹幕/record.md, issue 1). The user is told
///   once, with [TwitchDanmakuProtocol.cookieExpiredNotice] (B-7).
/// - A `RECONNECT` (the server is going down for maintenance) replaces the
///   socket at once, without a notice and without a second `DanmakuReady`
///   (B-7); 3.x waited for the server to drop it and showed a reconnect.
/// - Deleted messages, timeouts, bans and cleared chats are reported as
///   retractions, subscriptions and raids as notices (B-7).
/// - A community gift (`submysterygift` and the N `subgift`s it gives,
///   one `msg-param-community-gift-id`) is one notice, its announcement
///   (D07.6): a subscription of it waits up to
///   [TwitchDanmakuProtocol.communityGiftWait] for the announcement and is
///   left out once it comes; one whose announcement does not come is shown.
///   Cheers (Bits) are gifts before their chat lines.
///
/// The app registers it as `SiteIds.twitch: () =>
/// TwitchDanmakuConnection(proxy: …)`.
final class TwitchDanmakuConnection extends DanmakuSocketConnection<TwitchDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake, [random] draws anonymous nicks and
  /// [now] reads the clock for [switchInterval] (tests).
  new({super.proxy, super.connector, Random? random, DateTime Function()? now})
    : _random = random ?? Random.secure(),
      _now = now ?? DateTime.now,
      super(site: SiteIds.twitch, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 40 s heartbeat.
  /// No join timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: TwitchDanmakuProtocol.heartbeatInterval,
  );

  /// The least time between two quiet switches for a `RECONNECT`; one
  /// sooner reconnects the ordinary way (backoff, notice), so a server that
  /// keeps asking cannot drive a tight reconnect loop.
  static const Duration switchInterval = Duration(seconds: 10);

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(endpoints: [TwitchDanmakuProtocol.endpoint]);

  final Random _random;
  final DateTime Function() _now;
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
    final switching = join.switching;
    join.switching = false;
    // 3.x: joinRoom, then onReady; no answer is awaited.
    TwitchDanmakuProtocol.join(join.channel, random: _random, chat: join.chat).forEach(session.send);
    // A switch the server asked for keeps the room joined throughout.
    if (!switching || !session.isConnected) session.ready();
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
    final join = _of(session);
    for (final message in frame.messages) {
      final gift = frame.communityGifts[message];
      if (gift == null || join == null) {
        session.message(message);
      } else {
        join.gifts.add(message, gift, session.message);
      }
    }
    if (frame.loginRejected && _loginRejected(session)) return;
    if (frame.reconnect) _switch(session);
  }

  /// Drops the refused login and reopens as an anonymous nick (reading chat
  /// needs no login), without a reconnect notice; tells the user once that
  /// the cookie expired. False for an anonymous nick: nothing to drop.
  bool _loginRejected(DanmakuSocketSession session) {
    final join = _of(session);
    if (join == null || join.chat == null) return false;
    join.chat = null;
    session
      ..message(TwitchDanmakuProtocol.cookieExpiredNotice)
      ..markDisconnected();
    unawaited(session.reopen(_target));
    return true;
  }

  /// Replaces the socket the server is about to drop (`RECONNECT`): the old
  /// one is closed and a new one joins with the same login, the room staying
  /// joined, so neither a reconnect notice nor a second ready is reported.
  /// Within [switchInterval] of the last switch it reconnects the ordinary
  /// way instead.
  void _switch(DanmakuSocketSession session) {
    final join = _of(session);
    if (join == null) return;
    final now = _now();
    final last = join.switchedAt;
    if (last != null && now.difference(last).abs() < switchInterval) {
      session.reconnect();
      return;
    }
    join
      ..switchedAt = now
      ..switching = true;
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

/// The join of one run: the channel, the chat login still in use and the
/// state of a switch the server asked for.
final class _Join {
  new(this.run, this.channel, this.chat);

  final DanmakuRun run;
  final String channel;
  TwitchChatLogin? chat;

  /// When the last `RECONNECT` switch began.
  DateTime? switchedAt;

  /// The next open belongs to a `RECONNECT` switch.
  bool switching = false;

  /// The community gifts of this run (D07.6).
  late final _CommunityGifts gifts = _CommunityGifts(run);
}

/// The community gifts of one run (D07.6): an announcement is shown at
/// once and leaves out the subscriptions it gives, those held and those
/// still to come (until [TwitchDanmakuProtocol.communityGiftLifetime]); a
/// subscription without its announcement waits
/// [TwitchDanmakuProtocol.communityGiftWait] for it, then is shown.
final class _CommunityGifts {
  new(this._run) {
    unawaited(_run.ended.then((_) => _dispose()));
  }

  /// Gifts remembered; the oldest goes first.
  static const int _capacity = 64;

  final DanmakuRun _run;

  /// Announced gifts: when, and how many subscriptions are still to come.
  final Map<String, ({DateTime at, int left})> _announced = {};

  /// Subscriptions waiting for their announcement.
  final List<({String id, Timer timer})> _held = [];

  void add(LiveMessage notice, TwitchCommunityGift gift, void Function(LiveMessage) report) {
    final now = DateTime.now();
    _announced.removeWhere(
      (_, entry) => now.difference(entry.at) > TwitchDanmakuProtocol.communityGiftLifetime || entry.left <= 0,
    );
    if (gift.announcement) {
      report(notice);
      var left = gift.count;
      for (final held in _held.where((held) => held.id == gift.id).toList()) {
        held.timer.cancel();
        _held.remove(held);
        left--;
      }
      _announced[gift.id] = (at: now, left: left);
      while (_announced.length > _capacity) {
        _announced.remove(_announced.keys.first);
      }
      return;
    }
    if (_announced[gift.id] case final entry?) {
      _announced[gift.id] = (at: entry.at, left: entry.left - 1);
      return;
    }
    late final ({String id, Timer timer}) held;
    held = (
      id: gift.id,
      timer: Timer(TwitchDanmakuProtocol.communityGiftWait, () {
        if (_held.remove(held) && _run.isActive) report(notice);
      }),
    );
    _held.add(held);
  }

  void _dispose() {
    for (final held in _held) {
      held.timer.cancel();
    }
    _held.clear();
  }
}
