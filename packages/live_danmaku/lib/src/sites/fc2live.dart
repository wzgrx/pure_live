import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One message of an FC2 control socket: its `name`, the `id` of an answer
/// (`_response_`) and its `arguments` (empty when missing).
typedef Fc2LiveControlMessage = ({String name, Object? id, Map<String, Object?> arguments});

/// FC2 Live's comments on a control socket of their own (the archived v4's
/// spec/sites/fc2live.md §7, checked against the recording
/// `fixtures/fc2live/danmaku/S06-live` and the site's `liveView.bundle.js`;
/// docs/T06/T06a/T06a.23/record.md), without I/O.
///
/// - The socket is the media control socket of M4.26: a fresh grant
///   (`Fc2LiveSite.controlGrant`) names it and its session cookie.
/// - The server pushes JSON text frames `{"name", "arguments"}`; the room is
///   joined at `connect_complete`. The client sends only the page's
///   heartbeat command every 30 s, answered by `_response_` with the same id.
/// - `comment` carries a list of comments. The 30 most recent ones come
///   again on joining, marked `history: 1`; they are not chat.
/// - `user_count` carries only the fields that changed: viewers now are
///   PC plus mobile (`pc_user_count`, `mobile_user_count`), this
///   broadcast's viewers the same for `*_total_count` ([Fc2LiveAudience]).
abstract final class Fc2LiveDanmakuProtocol {
  /// The page's heartbeat period (`setInterval(…, 3e4)` from the socket's
  /// open).
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// How long an open socket may take to say `connect_complete` (the
  /// archived v4's join timeout; the recording had it 5 ms after the open).
  static const Duration joinTimeout = Duration(seconds: 8);

  /// The name the server gives anonymous comments; also the name of a
  /// comment marked `anonymous`, whatever name it carries (the page hides
  /// that name).
  static const String anonymousName = '[anonymous]';

  /// The comment colours by name: the page's chat list (`.com.red` …);
  /// `black`, its default, and unknown names are white, the danmaku default.
  static const Map<String, LiveMessageColor> colors = {
    'red': LiveMessageColor(0xE6, 0x3D, 0x37),
    'pink': LiveMessageColor(0xE1, 0x33, 0x96),
    'orange': LiveMessageColor(0xDC, 0x76, 0x11),
    'yellow': LiveMessageColor(0xE1, 0xAC, 0x00),
    'green': LiveMessageColor(0x33, 0xBD, 0x4A),
    'cyan': LiveMessageColor(0x1B, 0x94, 0xC7),
    'blue': LiveMessageColor(0x44, 0x72, 0xF3),
    'purple': LiveMessageColor(0xB8, 0x4A, 0xC5),
  };

  static const int _maxEpochMilliseconds = 8640000000000000;
  static final RegExp _tag = RegExp('<[/!?a-zA-Z][^<>]*>');
  static final RegExp _secrets = RegExp(r'''((?<=[?&])control_token|l_ortkn)=[^&#;\s'"]*''');

  /// The page's heartbeat command with [id].
  static String heartbeat(int id) => '{"name":"heartbeat","arguments":{},"id":$id}';

  /// The address a [Fc2LiveDanmakuConnection]'s socket is given for
  /// [channelId]: the grant request, `getControlServer.php?channel_id=…`.
  /// Every handshake turns it into a fresh grant's socket.
  static Uri endpoint(String channelId) =>
      Uri.https('live.fc2.com', '/api/getControlServer.php', {'channel_id': channelId});

  /// The channel of an [endpoint] address, or null for any other address.
  static String? channelOf(Uri address) {
    if (address.scheme != 'https' ||
        address.host != 'live.fc2.com' ||
        address.path != '/api/getControlServer.php' ||
        address.queryParameters.keys.length != 1) {
      return null;
    }
    final channel = address.queryParameters['channel_id'] ?? '';
    return Fc2LiveApi.isChannelId(channel) ? channel : null;
  }

  /// [text] without the values of the grant's secrets: `dart:io` names the
  /// whole socket URL, `control_token` included, in a failed handshake.
  static String redact(String text) => text.replaceAllMapped(_secrets, (match) => '${match[1]}=…');

  /// One frame (text, or UTF-8 bytes) as a control message; null for a frame
  /// that is larger than the control accepts (2 MiB), not JSON, not an
  /// object or without a name.
  static Fc2LiveControlMessage? decode(Object? data) {
    final String text;
    switch (data) {
      case final String value:
        text = value;
      case final List<int> bytes when bytes.length <= Fc2LiveControl.messageLimit:
        text = utf8.decode(bytes, allowMalformed: true);
      default:
        return null;
    }
    if (text.length > Fc2LiveControl.messageLimit) return null;
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (root is! Map<String, Object?>) return null;
    final name = root['name'];
    if (name is! String) return null;
    final arguments = root['arguments'];
    return (name: name, id: root['id'], arguments: arguments is Map<String, Object?> ? arguments : const {});
  }

  /// The chat of a `comment` message's [arguments], in order ([comment]),
  /// without the comments [ng] hides.
  static List<LiveMessage> comments(Map<String, Object?> arguments, {Fc2LiveNgList? ng}) {
    final list = arguments['comments'];
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map && !(ng?.hides(item) ?? false))
          if (comment(item) case final LiveMessage message) message,
    ];
  }

  /// One comment as chat, or null:
  ///
  /// - a comment replayed on joining (`history` 1) is not chat, nor is a
  ///   system comment (tips, gifts, entries: `system_comment` instead of
  ///   `comment`);
  /// - the text is `comment` as the page shows it ([plainText]); blank or
  ///   not a string: null;
  /// - the name is `user_name` as the page shows it, [anonymousName] when
  ///   the comment is `anonymous` or the name is blank;
  /// - the user id is the page's key of `encrypted_user_id` ([userId]);
  /// - the time is `timestamp` (ms); a time that is not positive or out of
  ///   `DateTime`'s range is left out;
  /// - the colour is `color` by name ([colors]).
  ///
  /// There is no message id: `hash` names the sender, not the comment.
  static LiveMessage? comment(Object? item) {
    if (item is! Map || _isSet(item['history'])) return null;
    final raw = item['comment'];
    if (raw is! String) return null;
    final text = plainText(raw);
    if (text.isEmpty) return null;
    final name = item['user_name'];
    final userName = name is String ? plainText(name) : '';
    final time = item['timestamp'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _isSet(item['anonymous']) || userName.isEmpty ? anonymousName : userName,
      userId: userId(item['encrypted_user_id']),
      message: text,
      sentAt: time is int && time > 0 && time <= _maxEpochMilliseconds
          ? DateTime.fromMillisecondsSinceEpoch(time)
          : null,
      color: color(item['color']),
    );
  }

  /// JavaScript's `1 == value`, the page's test of `history`.
  static bool _isSet(Object? value) => value == 1 || value == true || value == '1';

  /// Text the server sends as HTML, as the page shows it: tags removed,
  /// character references decoded, trimmed.
  static String plainText(String html) => _text(html).trim();

  static String _text(String html) => decodeHtmlEntities(html.replaceAll(_tag, ''));

  /// Text the server sends as HTML as the page compares it with its NG
  /// lists (`_removeTag`): the text of [html] with `&` and `<` escaped
  /// again, untrimmed.
  static String escapedText(String html) => _text(html).replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  /// The page's user key of an `encrypted_user_id` (`decryptUserId`): an id
  /// of at most 12 characters that starts with `a` and a digit is an FC2
  /// user id encoded with that digit as the offset, a different one on
  /// every comment, so it is decoded (`id-<n>-<n>…`); any other value is a
  /// viewer's stable id (`id_<value>`). Empty when there is none.
  static String userId(Object? encrypted) {
    if (encrypted is! String || encrypted.isEmpty) return '';
    if (encrypted.length >= 2 && encrypted.length <= 12 && encrypted.startsWith('a')) {
      final offset = encrypted.codeUnitAt(1) - 0x30;
      if (offset >= 0 && offset <= 9) {
        return 'id${[for (var i = 2; i < encrypted.length; i++) '-${encrypted.codeUnitAt(i) - offset + 3 * i}'].join()}';
      }
    }
    return 'id_$encrypted';
  }

  /// A comment colour by name ([colors]); white otherwise.
  static LiveMessageColor color(Object? name) =>
      (name is String ? colors[name.trim().toLowerCase()] : null) ?? LiveMessageColor.white;
}

/// The NG lists the page applies to other viewers' comments, from
/// `ng_comment` messages (the streamer's and FC2's lists; the page's
/// `setNgCommentList` and `_hasNg`, for a viewer who is not the streamer
/// and keeps no lists of their own).
///
/// - A list entry has a `type`: keywords (`channel_keyword`,
///   `admin_keyword`, `keyword`) or senders (`channel_user`, `admin_user`,
///   `share_low`, `share_high`, `share_hyper`, `user`). `mode` `add` (or
///   none) adds it under its `ng_comment_id`, any other mode removes that
///   id, or an equal entry without one.
/// - `admin_ng` turns FC2's lists (`admin_*`) on or off; `shared_ng_level`
///   1 adds the shared list `share_low`, 2 also `share_high`; `share_hyper`,
///   the channel's lists and `keyword`/`user` always apply.
/// - A comment is hidden when its name (not for anonymous comments) or its
///   text contains a keyword (lower case, compared as the page escapes
///   them, [Fc2LiveDanmakuProtocol.escapedText]), or its sender is listed:
///   an FC2 user by the decoded id ([Fc2LiveDanmakuProtocol.userId]),
///   anyone else by `orz_token`. The streamer's own comments (`owner` 1)
///   are only checked against `keyword`.
final class Fc2LiveNgList {
  static const Set<String> _keywordTypes = {'keyword', 'channel_keyword', 'admin_keyword'};
  static const Set<String> _userTypes = {
    'user',
    'channel_user',
    'admin_user',
    'share_low',
    'share_high',
    'share_hyper',
  };

  bool _admin = false;
  int _sharedLevel = 0;
  final Map<String, _NgEntry> _byId = {};
  final List<_NgEntry> _unnamed = [];

  /// Entries held.
  int get length => _byId.length + _unnamed.length;

  /// Whether FC2's lists apply (`admin_ng`).
  bool get usesAdminLists => _admin;

  /// Which shared lists apply (`shared_ng_level`, 0 to 2).
  int get sharedLevel => _sharedLevel;

  /// Applies an `ng_comment` message's [arguments].
  void apply(Map<String, Object?> arguments) {
    if (arguments.containsKey('admin_ng')) _admin = _truthy(arguments['admin_ng']);
    if (_level(arguments['shared_ng_level']) case final int level) _sharedLevel = level;
    final list = arguments['ng_comments'];
    if (list is List) list.forEach(_change);
  }

  static bool _truthy(Object? value) => value != null && value != false && value != 0 && value != '';

  static int? _level(Object? value) => switch (value) {
    final int level => level,
    final String text => int.tryParse(text.trim()),
    _ => null,
  };

  void _change(Object? item) {
    if (item is! Map) return;
    final type = item['type'];
    final _NgEntry entry;
    if (_keywordTypes.contains(type)) {
      final keyword = item['ng_keyword'];
      entry = _NgEntry(type! as String, keyword: keyword is String ? keyword.toLowerCase() : '');
    } else if (_userTypes.contains(type)) {
      final orz = item['ng_orz_token'];
      entry = _NgEntry(
        type! as String,
        userId: Fc2LiveDanmakuProtocol.userId(item['ng_encrypted_user_id']),
        orz: orz is String ? orz : '',
      );
    } else {
      return;
    }
    final id = item['ng_comment_id'];
    final key = (id is int && id != 0) || (id is String && id.isNotEmpty) ? '$id' : null;
    final mode = item['mode'];
    if (mode == null || mode == 'add') {
      if (key != null) {
        _byId[key] = entry;
      } else {
        _unnamed.add(entry);
      }
    } else if (key != null) {
      _byId.remove(key);
    } else {
      _unnamed.removeWhere((held) => held == entry);
    }
  }

  Iterable<_NgEntry> get _entries => _byId.values.followedBy(_unnamed);

  /// Whether the page would hide [comment].
  bool hides(Map<Object?, Object?> comment) {
    final owner = comment['owner'] == 1;
    final name = comment['user_name'];
    if (!Fc2LiveDanmakuProtocol._isSet(comment['anonymous']) && name is String) {
      if (_keyword(Fc2LiveDanmakuProtocol.escapedText(name), owner: owner)) return true;
    }
    if (!owner) {
      final orz = comment['orz_token'];
      if (_sender(Fc2LiveDanmakuProtocol.userId(comment['encrypted_user_id']), orz is String ? orz : null)) {
        return true;
      }
    }
    final text = comment['comment'];
    return text is String && _keyword(Fc2LiveDanmakuProtocol.escapedText(text), owner: owner);
  }

  bool _applies(String type) => switch (type) {
    'admin_keyword' || 'admin_user' => _admin,
    'share_low' => _sharedLevel >= 1,
    'share_high' => _sharedLevel >= 2,
    _ => true,
  };

  bool _keyword(String text, {required bool owner}) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    return _entries.any(
      (entry) =>
          entry.keyword.isNotEmpty &&
          (owner ? entry.type == 'keyword' : _applies(entry.type)) &&
          lower.contains(entry.keyword),
    );
  }

  bool _sender(String userId, String? orz) {
    final decoded = userId.startsWith('id-');
    return _entries.any(
      (entry) =>
          _userTypes.contains(entry.type) &&
          _applies(entry.type) &&
          (decoded ? entry.userId.isNotEmpty && entry.userId == userId : entry.orz.isNotEmpty && entry.orz == orz),
    );
  }
}

/// One NG list entry: a keyword, or a sender's decoded id and `orz_token`.
@immutable
final class _NgEntry {
  const new(this.type, {this.keyword = '', this.userId = '', this.orz = ''});

  final String type;
  final String keyword;
  final String userId;
  final String orz;

  @override
  bool operator ==(Object other) =>
      other is _NgEntry && other.type == type && other.keyword == keyword && other.userId == userId && other.orz == orz;

  @override
  int get hashCode => Object.hash(type, keyword, userId, orz);
}

/// The audience of one connection from its `user_count` messages, which
/// carry only the fields that changed: every field keeps its last value,
/// and the sums are reported when they change (the page's `setUserCount`).
final class Fc2LiveAudience {
  final Map<String, int> _counts = {};

  static const List<String> _fields = ['pc_user_count', 'mobile_user_count', 'pc_total_count', 'mobile_total_count'];

  /// Viewers now: PC plus mobile, once either is known (a missing one
  /// counts 0); null before.
  int? get online => _sum('pc_user_count', 'mobile_user_count');

  /// This broadcast's viewers: PC plus mobile, as [online].
  int? get total => _sum('pc_total_count', 'mobile_total_count');

  int? _sum(String pc, String mobile) {
    final a = _counts[pc];
    final b = _counts[mobile];
    return a == null && b == null ? null : (a ?? 0) + (b ?? 0);
  }

  /// Applies a `user_count` message's [arguments] (counts that are not
  /// whole numbers of zero or more are ignored) and returns the figures that
  /// changed: [online] as `onlineViewers`, then [total] as `totalViewers`.
  List<LiveMessage> update(Map<String, Object?> arguments) {
    final onlineBefore = online;
    final totalBefore = total;
    for (final field in _fields) {
      final value = arguments[field];
      if (value is int && value >= 0) _counts[field] = value;
    }
    return [
      if (online case final int value when value != onlineBefore) _figure(LiveAudienceMetricKind.onlineViewers, value),
      if (total case final int value when value != totalBefore) _figure(LiveAudienceMetricKind.totalViewers, value),
    ];
  }

  static LiveMessage _figure(LiveAudienceMetricKind kind, int value) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    color: LiveMessageColor.white,
    data: LiveAudienceUpdate(kind: kind, value: value),
  );
}

/// FC2 Live's comment connection (new in v4: 3.x had none, the 26-3
/// upgrade), on the WebSocket runtime: a control socket of its own per
/// channel (`Fc2LiveDanmakuArgs.channelId`).
///
/// - Every handshake takes a fresh grant (`memberApi.php` and
///   `getControlServer.php`): a grant is good for one socket for about a
///   minute. The first one is taken when the connection starts; a channel
///   that does not exist, is not on air or is restricted (`NotFound`,
///   `StreamUnavailable`, `NeedsLogin`), or answers that cannot be read,
///   end it at once with [DanmakuCloseReason.connectionFailed]. A network
///   failure or rate limit of that request, and every failure of a later
///   one, is a failed handshake: the runtime's backoff and its eight
///   attempts apply, so a streamer who drops out briefly is joined again.
/// - The socket connects through the platform's proxy route with the
///   grant's headers and a WebSocket ping every 15 s
///   (`Fc2LiveControl.connect`), and is joined at `connect_complete`
///   ([DanmakuSocketPolicy.joinTimeout] 8 s).
/// - The page's heartbeat command goes out every 30 s from the open (ids
///   count up through the connection).
/// - `control_disconnection` (4500: the grant expired; 1000: the broadcast
///   ended) reconnects with a fresh grant; `move_server` does so at once and
///   without a notice. Server-ordered reconnects and join timeouts count
///   until a heartbeat is answered: past the policy's reconnects the
///   connection ends with [DanmakuCloseReason.reconnectsExhausted], since
///   the socket's own count restarts with every message.
/// - Failures never name the grant's token or cookie.
///
/// The app registers it as `SiteIds.fc2Live: () =>
/// Fc2LiveDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `Fc2LiveSite` and its proxy policy.
final class Fc2LiveDanmakuConnection extends DanmakuSocketConnection<Fc2LiveDanmakuArgs> {
  /// Creates the connection. [http] asks for the grants (as `fc2live`);
  /// [proxy] routes the socket; [connector] replaces the handshake (default
  /// `Fc2LiveControl.connect`) and [policy] the timing (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
  }) => Fc2LiveDanmakuConnection._(
    _Grants(Fc2LiveSite(http, proxy: proxy), connector ?? Fc2LiveControl.connect, proxy),
    proxy: proxy,
    policy: policy,
  );

  new _(this._grants, {required super.proxy, required super.policy})
    : super(site: SiteIds.fc2Live, connector: _grants.connect);

  /// The platform's timing: the page's 30 s heartbeat, 8 s for
  /// `connect_complete`, the runtime's defaults otherwise (90 s of silence,
  /// eight reconnects).
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: Fc2LiveDanmakuProtocol.heartbeatInterval,
    joinTimeout: Fc2LiveDanmakuProtocol.joinTimeout,
  );

  final _Grants _grants;
  _State? _state;

  _State? _of(DanmakuSocketSession session) {
    final state = _state;
    return state != null && identical(state.run, session.run) ? state : null;
  }

  @override
  @protected
  Future<DanmakuSocketTarget> target(Fc2LiveDanmakuArgs args, DanmakuRun run) async {
    final channelId = args.channelId;
    if (!Fc2LiveApi.isChannelId(channelId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'Not an FC2 channel');
    }
    final target = DanmakuSocketTarget(endpoints: [Fc2LiveDanmakuProtocol.endpoint(channelId)]);
    _state = _State(run, target);
    await _grants.begin(channelId);
    return target;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) => _of(session)?.joined = false;

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final state = _of(session);
    final message = Fc2LiveDanmakuProtocol.decode(data);
    if (state == null || message == null) return;
    switch (message.name) {
      case 'connect_complete':
        if (!state.joined) {
          state.joined = true;
          session.ready();
        }
      case 'ng_comment':
        state.ng.apply(message.arguments);
      case 'comment':
        for (final chat in Fc2LiveDanmakuProtocol.comments(message.arguments, ng: state.ng)) {
          if (!session.isActive) return;
          session.message(chat);
        }
      case 'user_count':
        for (final figure in state.audience.update(message.arguments)) {
          if (!session.isActive) return;
          session.message(figure);
        }
      case '_response_' when message.arguments['status'] == 0:
        state.unconfirmed = 0;
      case 'control_disconnection':
        final code = message.arguments['code'];
        _renew(session, state, 'control_disconnection${code is int ? ' $code' : ''}');
      case 'move_server':
        _renew(session, state, 'move_server', move: true);
      // initial_connect, connect_data, video_information,
      // point_information and the rest carry no chat.
    }
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) {
    final state = _of(session);
    return state == null ? null : Fc2LiveDanmakuProtocol.heartbeat(state.nextId++);
  }

  @override
  @protected
  void onJoinTimeout(DanmakuSocketSession session) {
    final state = _of(session);
    if (state != null) _renew(session, state, 'no connect_complete in time');
  }

  /// Replaces the socket with one on a fresh grant; [move] does it at once
  /// and without a notice (the page follows `move_server` quietly).
  void _renew(DanmakuSocketSession session, _State state, String reason, {bool move = false}) {
    state.joined = false;
    if (++state.unconfirmed > policy.maxReconnects) {
      session.run.closed(DanmakuCloseReason.reconnectsExhausted, detail: reason);
      return;
    }
    if (move) {
      session.markDisconnected();
      unawaited(session.reopen(state.target));
    } else {
      session.reconnect();
    }
  }

  @override
  @protected
  Future<void> stop() async {
    _grants.cancel();
    await super.stop();
  }
}

/// What one run of a [Fc2LiveDanmakuConnection] keeps.
final class _State {
  new(this.run, this.target);

  final DanmakuRun run;
  final DanmakuSocketTarget target;
  final Fc2LiveAudience audience = Fc2LiveAudience();

  /// The NG lists, kept across the run's sockets (each sends them again).
  final Fc2LiveNgList ng = Fc2LiveNgList();

  /// The next heartbeat id.
  int nextId = 1;

  /// Whether the current socket said `connect_complete`.
  bool joined = false;

  /// Server-ordered reconnects and join timeouts since the last answered
  /// heartbeat.
  int unconfirmed = 0;
}

/// The handshakes of a [Fc2LiveDanmakuConnection]: a fresh grant for the
/// channel of the nominal address, then its socket.
final class _Grants {
  new(this._site, this._connect, this._proxy);

  final Fc2LiveSite _site;
  final SocketConnector _connect;
  final ProxyPolicy _proxy;
  CancelToken _cancel = CancelToken();

  /// The first handshake's grant, or why it could not be taken.
  Object? _first;

  /// A new run for [channelId]: the previous run's requests are cancelled
  /// and the first grant is taken. A failure that asking again will not
  /// mend (a `SiteError` that is not transient: the channel does not exist,
  /// is not on air, is restricted, or answers what cannot be read) throws
  /// [DanmakuStartFailure]; any other failure (the network, a rate limit)
  /// is kept for the first handshake, which then fails and is retried.
  Future<void> begin(String channelId) async {
    cancel();
    final token = _cancel = CancelToken();
    final Object first;
    try {
      first = await _site.controlGrant(channelId, cancel: token);
    } on Object catch (error) {
      if (error is SiteError && !error.isTransient) {
        throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: '$error');
      }
      if (identical(_cancel, token)) _first = _HandshakeFailure('control grant: $error');
      return;
    }
    if (identical(_cancel, token)) _first = first;
  }

  /// Cancels the current run's requests and forgets its first grant.
  void cancel() {
    _cancel.cancel();
    _first = null;
  }

  Future<SocketChannel> connect(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    // The runtime only ever has the target's address, the grant request.
    final channelId =
        Fc2LiveDanmakuProtocol.channelOf(endpoint) ??
        (throw ArgumentError.value(endpoint, 'endpoint', 'not an FC2 grant address'));
    final first = _first;
    _first = null;
    final grant = switch (first) {
      final Fc2LiveGrant grant when grant.channelId == channelId => grant,
      final _HandshakeFailure failure => throw failure,
      _ => await _grant(channelId),
    };
    try {
      return await _connect(
        grant.endpoint,
        headers: grant.handshakeHeaders,
        protocols: null,
        route: _proxy.routeFor(SiteIds.fc2Live, grant.socket),
        connectTimeout: connectTimeout,
      );
    } on Object catch (error) {
      throw _HandshakeFailure('$error');
    }
  }

  Future<Fc2LiveGrant> _grant(String channelId) async {
    try {
      return await _site.controlGrant(channelId, cancel: _cancel);
    } on Object catch (error) {
      throw _HandshakeFailure('control grant: $error');
    }
  }
}

/// A failed grant or handshake, described without the grant's secrets.
final class _HandshakeFailure implements Exception {
  new(String message) : message = Fc2LiveDanmakuProtocol.redact(message);

  final String message;

  @override
  String toString() => message;
}
