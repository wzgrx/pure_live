import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// What one FC2 control message held besides events.
typedef Fc2LiveFrame = ({List<DanmakuEvent> events, bool joined, bool rejected});

/// FC2 Live's chat over the control socket (spec/sites/fc2live.md §7),
/// without I/O.
abstract final class Fc2LiveProtocol {
  /// Heartbeat period (§7.2).
  static const heartbeatInterval = Duration(seconds: 30);

  /// Comment colours by name (§7.3); `black` is the page's default and
  /// draws as the overlay default.
  static const Map<String, int> colors = {
    'black': DanmakuColors.white,
    'white': DanmakuColors.white,
    'red': 0xFF0000,
    'pink': 0xFF8080,
    'orange': 0xFFA500,
    'yellow': 0xFFFF00,
    'green': 0x00FF00,
    'cyan': 0x00FFFF,
    'blue': 0x0000FF,
    'purple': 0xC000FF,
  };

  /// A control command as a binary frame (the server reads the JSON text of
  /// binary frames too, §7.2).
  static List<int> command(String name, int id) =>
      utf8.encode(jsonEncode({'name': name, 'arguments': <String, Object?>{}, 'id': id}));

  /// §7.1 the handshake headers for [grant].
  static Map<String, String> headers(Fc2Grant grant) => {
    'Origin': 'https://live.fc2.com',
    'Cookie': 'l_ortkn=${grant.orz}',
  };

  static int? _count(Object? value) => value is int && value >= 0 ? value : null;

  /// §7.3 decodes one message. Comments replayed on join (`history: 1`)
  /// are dropped; `user_count` updates are partial, so [counts] carries the
  /// last PC and mobile figures between messages.
  static Fc2LiveFrame decode(String text, {required DecodeContext context, required Map<String, int> counts}) {
    final message = jsonDecode(text);
    if (message is! Map) return (events: const [], joined: false, rejected: false);
    final arguments = message['arguments'];
    switch (message['name']) {
      case 'connect_complete':
        return (events: const [], joined: true, rejected: false);
      case 'control_disconnection':
        // 4500: a stale control token; a fresh grant is needed (§7.1).
        return (events: const [], joined: false, rejected: true);
      case 'comment' when arguments is Map && arguments['comments'] is List:
        final events = <DanmakuEvent>[
          for (final comment in (arguments['comments'] as List).whereType<Map<Object?, Object?>>())
            if (_chat(comment, context) case final DanmakuChat chat) chat,
        ];
        return (events: events, joined: false, rejected: false);
      case 'user_count' when arguments is Map:
        final before = {...counts};
        for (final key in const ['pc_user_count', 'mobile_user_count', 'pc_total_count', 'mobile_total_count']) {
          if (_count(arguments[key]) case final int value) counts[key] = value;
        }
        final events = <DanmakuEvent>[];
        final online = _sumOf(counts, 'pc_user_count', 'mobile_user_count');
        final total = _sumOf(counts, 'pc_total_count', 'mobile_total_count');
        if (online != null && online != _sumOf(before, 'pc_user_count', 'mobile_user_count')) {
          events.add(_online(AudienceKind.online, online, context));
        }
        if (total != null && total != _sumOf(before, 'pc_total_count', 'mobile_total_count')) {
          events.add(_online(AudienceKind.cumulative, total, context));
        }
        return (events: events, joined: false, rejected: false);
    }
    return (events: const [], joined: false, rejected: false);
  }

  static int? _sumOf(Map<String, int> counts, String a, String b) =>
      counts[a] == null && counts[b] == null ? null : (counts[a] ?? 0) + (counts[b] ?? 0);

  static DanmakuOnline _online(AudienceKind kind, int value, DecodeContext context) => DanmakuOnline(
    room: context.room,
    session: context.session,
    receivedAt: context.receivedAt,
    audience: kind,
    value: value,
  );

  static DanmakuChat? _chat(Map<Object?, Object?> comment, DecodeContext context) {
    if (comment['history'] == 1) return null;
    final text = '${comment['comment'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final hash = comment['hash'];
    final timestamp = comment['timestamp'];
    final color = '${comment['color'] ?? ''}'.toLowerCase();
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: hash is String && hash.isNotEmpty ? 'fc2live:$hash' : null,
      sentAt: timestamp is int ? DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true) : null,
      userId: '${comment['encrypted_user_id'] ?? ''}',
      userName: '${comment['user_name'] ?? ''}'.trim(),
      text: text,
      color: colors[color] ?? DanmakuColors.parse(color) ?? DanmakuColors.white,
    );
  }
}

/// FC2 Live's chat connection: a control socket of its own (fresh grant per
/// start and after a stale-token rejection), joined on `connect_complete`,
/// a 30 s heartbeat command.
final class Fc2LiveConnector extends SocketConnector {
  /// Creates the connector for [detail]'s channel.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  final Map<String, int> _counts = {};
  var _id = 0;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final Fc2Grant grant;
    try {
      grant = await Fc2LiveSite(transport.http).controlGrant(room.roomId);
    } on NotFound catch (error) {
      throw DanmakuStartFailure('noRoom', error.detail);
    } on StreamUnavailable catch (error) {
      throw DanmakuStartFailure('offline', error.detail);
    } on NeedsLogin catch (error) {
      throw DanmakuStartFailure('credentials', error.detail);
    } on SiteError catch (error) {
      throw DanmakuStartFailure('grant', error.toString());
    }
    return SocketPlan(endpoints: [Fc2LiveParse.controlUrl(grant)], headers: Fc2LiveProtocol.headers(grant));
  }

  @override
  List<List<int>> openFrames() => const [];

  @override
  bool get joinedOnOpen => false;

  // A reconnect a minute later meets a stale token (4500) and asks for a
  // new grant; that is routine here, not a credential problem.
  @override
  int get maxRejections => 50;

  @override
  Duration get heartbeatInterval => Fc2LiveProtocol.heartbeatInterval;

  @override
  List<int> heartbeat() => Fc2LiveProtocol.command('heartbeat', ++_id);

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final frame = Fc2LiveProtocol.decode(text, context: context, counts: _counts);
    return FrameResult(events: frame.events, joined: frame.joined, rejected: frame.rejected);
  }
}
