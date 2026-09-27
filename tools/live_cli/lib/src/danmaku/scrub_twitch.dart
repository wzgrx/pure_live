import 'dart:convert';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// Twitch (spec/sites/twitch.md §11): chat senders get pseudonyms (display
/// name, login in the prefix, user id, reply-parent sender) and lose the
/// client nonce; their names are also replaced where chat text mentions
/// them. Lines about other viewers the connector does not read
/// (USERNOTICE, CLEARCHAT, CLEARMSG, whispers) are dropped. The anonymous
/// `justinfanNNNN` nick, the channel and its room state stay.
class TwitchFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _kept = {
    'CAP', 'PASS', 'NICK', 'JOIN', 'PART', 'PING', 'PONG', 'ROOMSTATE', 'USERSTATE', 'GLOBALUSERSTATE', //
    'NOTICE', 'RECONNECT', '001', '002', '003', '004', '353', '366', '372', '375', '376',
  };

  static const _person = {'display-name', 'reply-parent-display-name', 'reply-thread-parent-display-name'};
  static const _login = {'login', 'reply-parent-user-login', 'reply-thread-parent-user-login'};
  static const _id = {'user-id', 'reply-parent-user-id', 'reply-thread-parent-user-id', 'target-user-id'};
  static const _secret = {'client-nonce'};

  /// Names replaced so far (display names and logins), for mentions.
  final Set<String> _people = {};

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\:')
      .replaceAll(' ', r'\s')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');

  static Iterable<TwitchIrcMessage> _chats(CapturedFrame frame) sync* {
    if (frame.direction != 'in') return;
    for (final message in TwitchProtocol.messages(utf8.decode(frame.bytes, allowMalformed: true))) {
      if (message.command == 'PRIVMSG') yield message;
    }
  }

  String _personName(String original) {
    _people.add(original);
    return names.person(original);
  }

  String _loginName(String original) {
    final login = original.toLowerCase();
    _people.add(login);
    return names.person(login);
  }

  @override
  ScrubbedCapture scrub(List<CapturedFrame> frames, List<({Uri url, Map<String, String> headers})> handshakes) {
    // Every sender gets a pseudonym before any text is rewritten, so a
    // mention that comes before the sender's own line is replaced too.
    for (final frame in frames) {
      for (final message in _chats(frame)) {
        for (final MapEntry(:key, :value) in message.tags.entries) {
          if (value.isEmpty) continue;
          if (_person.contains(key)) _personName(value);
          if (_login.contains(key)) _loginName(value);
        }
        final nick = message.nick;
        if (nick != null) _loginName(nick);
      }
    }
    return super.scrub(frames, handshakes);
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    final lines = <String>[];
    final crlf = text.endsWith('\r\n');
    for (final line in text.split('\r\n')) {
      if (line.isEmpty) continue;
      final scrubbed = _line(line);
      if (scrubbed != null) lines.add(scrubbed);
    }
    if (lines.isEmpty) return null;
    return utf8.encode(lines.join('\r\n') + (crlf ? '\r\n' : ''));
  }

  /// [text] with every known name (3+ characters) replaced, whole words,
  /// ignoring case.
  String _mentions(String text) {
    var out = text;
    final known = _people.where((name) => name.runes.length >= 3).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final original in known) {
      final replacement = names.replacementOf(original);
      if (replacement == null) continue;
      final pattern = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(original)}(?![A-Za-z0-9_])', caseSensitive: false);
      if (pattern.hasMatch(out)) {
        out = out.replaceAll(pattern, replacement);
        record('privmsg.mention', 'person');
      }
    }
    return out;
  }

  String? _line(String line) {
    final message = TwitchProtocol.parse(line);
    if (message == null) return null;
    if (message.command != 'PRIVMSG') {
      if (_kept.contains(message.command)) return line;
      record('irc.${message.command}', 'dropped');
      return null;
    }
    final tags = <String>[];
    for (final MapEntry(:key, :value) in message.tags.entries) {
      final replaced = switch (key) {
        _ when value.isEmpty => value,
        _ when _person.contains(key) => _personName(value),
        _ when _login.contains(key) => _loginName(value),
        _ when _id.contains(key) => names.digits(value),
        _ when _secret.contains(key) => names.secret(value),
        _ when key.endsWith('msg-body') => _mentions(value),
        _ => value,
      };
      tags.add('$key=${_escape(replaced)}');
    }
    record('privmsg.sender', 'person');
    final nick = message.nick;
    final login = nick == null ? null : _loginName(nick);
    final prefix = login == null ? message.prefix : '$login!$login@$login.tmi.twitch.tv';
    final params = message.params;
    final middle = params.length > 1 ? params.sublist(0, params.length - 1) : params;
    final trailing = params.length > 1 ? ' :${_mentions(params.last)}' : '';
    return '${tags.isEmpty ? '' : '@${tags.join(';')} '}'
        '${prefix == null ? '' : ':$prefix '}'
        '${[message.command, ...middle].join(' ')}$trailing';
  }
}
