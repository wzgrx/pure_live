import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// TwitCasting's comment stream: the web player's `eventpubsuburl.php` and
/// `event.pubsub` socket (the archived v4's spec/sites/twitcasting.md §7,
/// checked against the recording `fixtures/twitcasting/danmaku/S08-live` and
/// the player script; docs/D-弹幕/D01-平台弹幕协议/D01.12-TwitCasting弹幕/record.md), without I/O.
///
/// - A broadcast's socket URL is asked for with a form POST of its
///   `movie_id`. The answer is a JSON object whose `url` is
///   `wss://<node>.twitcasting.tv/event.pubsub/v1/streams/<movie>/events`
///   with the query `token=…&n=…`; the token is signed for about an hour.
/// - The client sends nothing. The server pushes JSON arrays of events, and
///   an empty array when nothing else went out for 10 s.
/// - Only `comment` events are chat. Gifts come only to a URL with `gift=1`
///   (the player adds it), which this client does not ask for.
abstract final class TwitcastingDanmakuProtocol {
  /// Where a broadcast's socket URL is asked for.
  static final Uri pubsubUrl = Uri.parse('https://twitcasting.tv/eventpubsuburl.php');

  /// The server's keep-alive: an empty array when nothing else was sent for
  /// this long (measured 2026-09-29).
  static const Duration keepAliveInterval = Duration(seconds: 10);

  /// Silence after which the player replaces the socket
  /// (`DISCONNECTION_THRESHOLD`): three missed keep-alives.
  static const Duration silenceTimeout = Duration(seconds: 30);

  /// Handshake headers: the site's origin and the adapter's bare user agent
  /// (`TwitcastingApi.headers`).
  static const Map<String, String> socketHeaders = {'origin': TwitcastingApi.origin, 'user-agent': 'Mozilla/5.0'};

  static const int _maxEpochMilliseconds = 8640000000000000;
  static final RegExp _signed = RegExp(r'''(?<=[?&])(token|n)=[^&#\s'"]*''');

  /// The request for [movieId]'s socket URL: a form POST of `movie_id` with
  /// the adapter's headers, sent as `twitcasting` (its proxy route).
  static LiveRequest request(int movieId, {Duration timeout = defaultRequestTimeout, CancelToken? cancel}) =>
      LiveRequest.form(
        site: SiteIds.twitcasting,
        url: pubsubUrl,
        fields: {'movie_id': '$movieId'},
        headers: TwitcastingApi.headers,
        timeout: timeout,
        cancel: cancel,
      );

  /// The socket URL of an `eventpubsuburl.php` [response]: a `wss` URL on a
  /// `twitcasting.tv` host. Throws [FormatException] for anything else (a
  /// status that is not 2xx, a body that is not that JSON).
  static Uri socketUrl(LiveResponse response) {
    if (!response.isSuccess) throw FormatException('eventpubsuburl.php answered HTTP ${response.status}');
    final Object? root;
    try {
      root = response.json;
    } on FormatException {
      throw const FormatException('eventpubsuburl.php answered no JSON');
    }
    final url = root is Map ? root['url'] : null;
    final uri = url is String ? Uri.tryParse(url.trim()) : null;
    if (uri == null || uri.scheme != 'wss' || !_isSiteHost(uri.host)) {
      throw const FormatException('eventpubsuburl.php answered no socket URL');
    }
    return uri;
  }

  static bool _isSiteHost(String host) => host == 'twitcasting.tv' || host.endsWith('.twitcasting.tv');

  /// The address a [TwitcastingDanmakuConnection]'s socket is given for
  /// [movieId]: `eventpubsuburl.php?movie_id=…`. Every handshake turns it
  /// into a freshly signed socket URL, as the player does.
  static Uri endpoint(int movieId) => pubsubUrl.replace(queryParameters: {'movie_id': '$movieId'});

  /// The broadcast of an [endpoint] address, or null for any other address.
  static int? movieOf(Uri address) {
    if (address.scheme != pubsubUrl.scheme || address.host != pubsubUrl.host || address.path != pubsubUrl.path) {
      return null;
    }
    final movie = int.tryParse(address.queryParameters['movie_id'] ?? '');
    return movie != null && movie > 0 ? movie : null;
  }

  /// [text] with the values of the socket URL's signature (`token`, `n`)
  /// left out: `dart:io` names the whole URL in a failed handshake.
  static String redact(String text) => text.replaceAllMapped(_signed, (match) => '${match[1]}=…');

  /// The chat of one pushed frame (text, or UTF-8 bytes): every `comment`
  /// event in order ([comment]). A frame that is not JSON, the keep-alive
  /// `[]` and every other event give nothing; a single event outside an
  /// array is read like a one-event array (as the archived v4 did).
  static List<LiveMessage> decode(Object? data) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const [];
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    return [
      for (final event in root is List ? root : [root])
        if (comment(event) case final LiveMessage message) message,
    ];
  }

  /// A `comment` event as white chat, or null for any other event:
  ///
  /// - the text is `message`, trimmed; blank or not a string: null;
  /// - the name is the author's `name`, else `screenName`; the user id is
  ///   the author's `id` (anonymous comments have ids like `c:tw123`);
  /// - the message id is `id` (a number), the time `createdAt` (ms); a
  ///   time that is not positive or out of `DateTime`'s range is left out.
  ///
  /// `numComments`, `isAnonymous` and the author's picture and `grade` are
  /// not read.
  static LiveMessage? comment(Object? event) {
    if (event is! Map || event['type'] != 'comment') return null;
    final text = event['message'];
    if (text is! String || text.trim().isEmpty) return null;
    final author = event['author'] is Map ? event['author'] as Map : const <Object?, Object?>{};
    final name = _text(author['name']);
    final created = event['createdAt'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name.isNotEmpty ? name : _text(author['screenName']),
      userId: _id(author['id']),
      message: text.trim(),
      messageId: _id(event['id']),
      sentAt: created is int && created > 0 && created <= _maxEpochMilliseconds
          ? DateTime.fromMillisecondsSinceEpoch(created)
          : null,
      color: LiveMessageColor.white,
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static String _id(Object? value) => switch (value) {
    final int number => '$number',
    final String text => text.trim(),
    _ => '',
  };
}

/// TwitCasting's comment connection (new in v4: 3.x had none, the 12-3
/// upgrade), on the WebSocket runtime: one socket per broadcast
/// (`TwitcastingDanmakuArgs.movieId`), no client frames.
///
/// - Every handshake, the first and each reconnect, first asks
///   `eventpubsuburl.php` for a freshly signed URL, as the player does. A
///   request that fails or gives no URL counts as a failed handshake: the
///   runtime's backoff and its eight attempts apply.
/// - An open socket counts as joined.
/// - The server sends at least an empty array every 10 s; 30 s without any
///   frame replaces the socket (the player's threshold). Nothing is sent: the
///   10 s heartbeat period only paces that watchdog.
/// - Failures name the socket URL without its signature.
///
/// The app registers it as `SiteIds.twitcasting: () =>
/// TwitcastingDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `TwitcastingSite` (proxy route by the platform id) and its proxy
/// policy for the socket.
final class TwitcastingDanmakuConnection extends DanmakuSocketConnection<TwitcastingDanmakuArgs> {
  /// Creates the connection. [http] asks for the socket URLs; [proxy] routes
  /// the socket; [connector] replaces `dart:io`'s handshake and [policy] the
  /// timing (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
  }) => TwitcastingDanmakuConnection._(_Resolver(http, connector ?? connectIoSocket), proxy: proxy, policy: policy);

  new _(this._resolver, {required super.proxy, required super.policy})
    : super(site: SiteIds.twitcasting, connector: _resolver.connect);

  /// The platform's timing: a 10 s tick for the silence watchdog (no frame
  /// is sent) and the player's 30 s of silence; the runtime's defaults
  /// otherwise. No join timer: an open socket is joined.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: TwitcastingDanmakuProtocol.keepAliveInterval,
    inactivityTimeout: TwitcastingDanmakuProtocol.silenceTimeout,
  );

  final _Resolver _resolver;

  @override
  @protected
  Future<DanmakuSocketTarget> target(TwitcastingDanmakuArgs args, DanmakuRun run) async {
    if (args.movieId <= 0) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No broadcast');
    }
    _resolver.renew();
    return DanmakuSocketTarget(
      endpoints: [TwitcastingDanmakuProtocol.endpoint(args.movieId)],
      headers: TwitcastingDanmakuProtocol.socketHeaders,
    );
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) => session.ready();

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    for (final message in TwitcastingDanmakuProtocol.decode(data)) {
      if (!session.isActive) return;
      session.message(message);
    }
  }

  @override
  @protected
  Future<void> stop() async {
    _resolver.cancel();
    await super.stop();
  }
}

/// The handshake of a [TwitcastingDanmakuConnection]: resolves the
/// `eventpubsuburl.php` address to a signed socket URL, then connects.
final class _Resolver {
  new(this._http, this._connect);

  final LiveHttp _http;
  final SocketConnector _connect;
  CancelToken _cancel = CancelToken();

  /// A new run: the previous run's requests are cancelled.
  void renew() {
    _cancel.cancel();
    _cancel = CancelToken();
  }

  /// Cancels the current run's requests.
  void cancel() => _cancel.cancel();

  Future<SocketChannel> connect(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    final movie = TwitcastingDanmakuProtocol.movieOf(endpoint);
    final url = movie == null ? endpoint : await _resolve(movie, connectTimeout);
    try {
      return await _connect(url, headers: headers, protocols: protocols, route: route, connectTimeout: connectTimeout);
    } on Object catch (error) {
      throw _HandshakeFailure(TwitcastingDanmakuProtocol.redact('$error'));
    }
  }

  Future<Uri> _resolve(int movie, Duration timeout) async {
    final response = await _http.send(TwitcastingDanmakuProtocol.request(movie, timeout: timeout, cancel: _cancel));
    return TwitcastingDanmakuProtocol.socketUrl(response);
  }
}

/// A failed handshake, described without the URL's signature.
final class _HandshakeFailure implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}
