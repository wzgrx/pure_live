import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/hls_cookies.dart';
import 'package:live_media/src/relay/hls_window.dart';
import 'package:live_media/src/relay/upstream.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// Restores one segment's bytes (Bigo's descrambling).
typedef SegmentRestore = Uint8List Function(Uint8List segment);

/// What the HLS relay does for a line the engine cannot fetch by itself.
@immutable
final class HlsRelayRecipe {
  /// Creates a recipe; every part is optional.
  const new({this.cookies, this.restore, this.queryPolicy, this.master});

  /// The `Cookie` header for a request to the URL, read at every request so
  /// a renewed grant applies at once (niconico's per-path cookies); null
  /// keeps the line's own `cookie` header. Throwing fails that request.
  final String? Function(Uri url)? cookies;

  /// For the text of a media playlist, how its segments are restored, or
  /// null when they pass as they are (Bigo).
  final SegmentRestore? Function(String playlist)? restore;

  /// Token propagation of the line's playlist to its children (3.x's
  /// `HlsSourceQueryPolicy`).
  final HlsSourceQueryPolicy? queryPolicy;

  /// Rewrites the line's own master before it is served (niconico's exact
  /// variant, `HlsMasterSelection.rewrite`).
  final String Function(Uri source, String text)? master;
}

/// One upstream answer of an HLS line.
final class HlsUpstreamResponse {
  /// Creates an answer.
  const new({
    required this.status,
    required this.url,
    required this.body,
    this.contentLength = -1,
    this.setCookies = const [],
  });

  /// HTTP status.
  final int status;

  /// Where the answer came from after redirects: playlists resolve their
  /// entries against it.
  final Uri url;

  /// The body; cancelling the subscription drops the connection.
  final Stream<List<int>> body;

  /// Length when the upstream gave one, else -1.
  final int contentLength;

  /// `Set-Cookie` values of the answer.
  final List<String> setCookies;
}

/// Fetches the resources of an HLS line for the relay.
abstract interface class HlsUpstream {
  /// GETs [url] with exactly [headers].
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers);

  /// Drops open connections.
  void close();
}

/// [HlsUpstream] over `dart:io`: TLS verification as [mediaHttpClient], the
/// proxy policy's route for the site per request, reads failing after
/// [idleTimeout] without data.
final class IoHlsUpstream implements HlsUpstream {
  /// Creates the upstream.
  new({
    required String site,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 15),
    MediaTlsExemptions tls = MediaTlsExemptions.known,
  }) : _client = mediaHttpClient(connectTimeout: connectTimeout, tls: tls, autoUncompress: true)
         ..findProxy = ((url) => proxy.routeFor(site, url).directive);

  final HttpClient _client;

  /// Limit for connecting and for the answer's headers.
  final Duration connectTimeout;

  /// Limit between two chunks of a body.
  final Duration idleTimeout;

  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) async {
    final request = await _client.getUrl(url).timeout(connectTimeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(connectTimeout);
    var at = url;
    for (final redirect in response.redirects) {
      at = at.resolveUri(redirect.location);
    }
    return HlsUpstreamResponse(
      status: response.statusCode,
      url: at,
      body: response.timeout(idleTimeout),
      contentLength: response.contentLength,
      setCookies: response.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
  }

  @override
  void close() => _client.close(force: true);
}

enum _Kind { playlist, segment, part, map, key }

final class _Entry {
  new(this.url, this.kind, this.restore);

  Uri url;
  final _Kind kind;
  SegmentRestore? restore;
}

/// Resolves a fresh line for the same quality and line as [current].
typedef HlsLineRenewer = Future<LivePlayLine> Function(LivePlayLine current);

/// Serves one HLS line on the loopback relay: every playlist is fetched
/// upstream and rewritten so that its playlists, segments, maps and keys
/// point back here; each upstream request carries the line's headers, the
/// recipe's cookies for that path and the session cookies upstream set
/// (TwitCasting's `lvhls_ssid_{movie}`); segments of a media playlist go
/// through the recipe's restorer. Only addresses taken from the line's own
/// playlists are served (no open proxy).
///
/// From archive v4's `HlsRoute`, with 3.x's session cookies, token
/// propagation and master selection added, and lease renewal: a line whose
/// lease cuts the connection (CHZZK, PandaTV) is renewed at its
/// `refreshAt`, and the playlists the engine already knows are pointed at
/// the renewed URLs (children of a master by position).
///
/// With [prefetch] (recording, M8.1) every media playlist goes through an
/// [HlsMediaWindow]: segments stay listed until the engine took them and
/// are downloaded in parallel ahead of it.
final class HlsRoute {
  /// Creates the route under [prefix] (`/<secret>/`).
  new({
    required this.prefix,
    required this.port,
    required this._line,
    required this.upstream,
    this.recipe = const HlsRelayRecipe(),
    this.renew,
    this.retryDelay = const Duration(seconds: 10),
    this.maxEntries = 2048,
    this.maxPlaylistBytes = 4 << 20,
    this.maxRestoredBytes = 64 << 20,
    this.prefetch,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _cookies = HlsSessionCookies(now: now) {
    _scheduleRenewal();
  }

  /// Path prefix, ending with `/`.
  final String prefix;

  /// Loopback port.
  final int port;

  /// Upstream fetcher.
  final HlsUpstream upstream;

  /// What the relay does besides forwarding.
  final HlsRelayRecipe recipe;

  /// Renews a line whose lease cuts the connection; null never renews.
  final HlsLineRenewer? renew;

  /// Wait before another renewal after a failed one.
  final Duration retryDelay;

  /// Segments, maps and keys remembered, oldest dropped first.
  final int maxEntries;

  /// Largest playlist read.
  final int maxPlaylistBytes;

  /// Largest segment restored in memory.
  final int maxRestoredBytes;

  /// Prefetch and retained window of media playlists; null serves every
  /// request on demand.
  final HlsPrefetchOptions? prefetch;

  final DateTime Function() _now;
  final HlsSessionCookies _cookies;
  LivePlayLine _line;
  final _index = _Entry(Uri(), _Kind.playlist, null);
  final _playlists = <String, _Entry>{};
  final _media = <String, _Entry>{};
  final _names = <String, String>{};
  List<String> _masterChildren = const [];
  final _windows = <_Entry, HlsMediaWindow>{};
  var _next = 0;
  var _closed = false;
  var _renewals = 0;
  Timer? _renewTimer;

  static const _indexName = 'index.m3u8';
  static final _uriAttribute = RegExp('URI="([^"]*)"');

  /// The line served (changes on each renewal).
  LivePlayLine get line => _line;

  /// Completed renewals.
  int get renewals => _renewals;

  /// Session cookies kept from upstream answers.
  int get sessionCookieCount => _cookies.count;

  /// The playlist the engine opens.
  Uri get uri => _local(_indexName);

  Uri _local(String name) => Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '$prefix$name');

  _Entry? _entry(String name) {
    if (name == _indexName) return _index..url = Uri.parse(_line.url);
    return _playlists[name] ?? _media[name];
  }

  /// The local name for [url] of [kind], the same for the same resource.
  String _name(Uri url, _Kind kind, SegmentRestore? restore) {
    final key = '${kind.name} $url';
    final known = _names[key];
    if (known != null) {
      final entry = _playlists[known] ?? _media.remove(known);
      if (entry != null) {
        entry.restore = restore;
        if (kind != _Kind.playlist) _media[known] = entry;
        return known;
      }
    }
    final number = _next++;
    final extension = RegExp(r'\.[A-Za-z0-9]{1,6}$').firstMatch(url.path)?.group(0) ?? '';
    final name = switch (kind) {
      _Kind.playlist => 'p$number.m3u8',
      _Kind.segment || _Kind.part => 's$number$extension',
      _Kind.map => 'm$number$extension',
      _Kind.key => 'k$number',
    };
    _names[key] = name;
    final entry = _Entry(url, kind, restore);
    if (kind == _Kind.playlist) {
      _playlists[name] = entry;
    } else {
      _media[name] = entry;
      while (_media.length > maxEntries) {
        final oldest = _media.keys.first;
        final dropped = _media.remove(oldest)!;
        _names.remove('${dropped.kind.name} ${dropped.url}');
      }
    }
    return name;
  }

  Uri? _resolve(Uri base, String reference) {
    final Uri url;
    try {
      url = base.resolve(reference.trim());
    } on FormatException {
      return null;
    }
    if (!url.isScheme('http') && !url.isScheme('https')) return null;
    return recipe.queryPolicy?.apply(url) ?? url;
  }

  /// [text] with its references pointing back to this route; [base] is the
  /// playlist's upstream address. Child playlists of a master are listed in
  /// order for renewal.
  String rewrite(String text, Uri base, {SegmentRestore? restore, bool index = false}) {
    final master = text.contains('#EXT-X-STREAM-INF');
    final children = <String>[];
    String? local(String reference, _Kind kind) {
      final url = _resolve(base, reference);
      if (url == null) return null;
      final name = _name(url, kind, kind == _Kind.segment ? restore : null);
      if (kind == _Kind.playlist) children.add(name);
      return _local(name).toString();
    }

    final out = StringBuffer();
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) {
        out.writeln();
      } else if (!line.startsWith('#')) {
        out.writeln(local(line, master ? _Kind.playlist : _Kind.segment) ?? raw);
      } else {
        final colon = line.indexOf(':');
        final kind = switch (colon < 0 ? line : line.substring(0, colon)) {
          '#EXT-X-KEY' || '#EXT-X-SESSION-KEY' => _Kind.key,
          '#EXT-X-MAP' => _Kind.map,
          '#EXT-X-MEDIA' || '#EXT-X-I-FRAME-STREAM-INF' || '#EXT-X-RENDITION-REPORT' => _Kind.playlist,
          '#EXT-X-PART' || '#EXT-X-PRELOAD-HINT' => _Kind.part,
          _ => null,
        };
        out.writeln(
          kind == null
              ? raw
              : line.replaceFirstMapped(_uriAttribute, (match) {
                  final to = local(match.group(1)!, kind);
                  return to == null ? match.group(0)! : 'URI="$to"';
                }),
        );
      }
    }
    if (index && master) _masterChildren = List.unmodifiable(children);
    return out.toString();
  }

  Map<String, String> _headersFor(Uri url) {
    final headers = {...line.headers};
    final cookies = recipe.cookies;
    var cookie = cookies == null ? headers['cookie'] : cookies(url);
    cookie = _cookies.headerFor(url, initialHeader: cookie);
    if (cookie == null) {
      headers.remove('cookie');
    } else {
      headers['cookie'] = cookie;
    }
    return headers;
  }

  HlsMediaWindow _windowOf(_Entry entry) => _windows.putIfAbsent(
    entry,
    () => HlsMediaWindow(
      options: prefetch!,
      source: () => identical(entry, _index) ? Uri.parse(_line.url) : entry.url,
      resolve: _resolve,
      fetch: (url) async {
        final answer = await upstream.get(url, _headersFor(url));
        _cookies.receive(answer.url, answer.setCookies);
        return (status: answer.status, url: answer.url, body: answer.body);
      },
    ),
  );

  /// The media windows (tests, diagnostics).
  Iterable<HlsMediaWindow> get windows => _windows.values;

  /// Answers [request] for [name]; unknown names get 404.
  Future<void> serve(HttpRequest request, String name) async {
    final response = request.response;
    final entry = _closed ? null : _entry(name);
    if (entry == null || request.method != 'GET') {
      await _status(response, HttpStatus.notFound);
      return;
    }
    final url = entry.url;
    if (entry.kind == _Kind.segment && await _serveHeld(response, entry)) return;
    HlsUpstreamResponse answer;
    try {
      answer = await upstream.get(url, _headersFor(url));
    } on Object {
      await _status(response, HttpStatus.badGateway);
      return;
    }
    _cookies.receive(answer.url, answer.setCookies);
    if (answer.status != HttpStatus.ok) {
      unawaited(answer.body.drain<void>().catchError((Object _) {}));
      await _status(response, answer.status >= 400 ? answer.status : HttpStatus.badGateway);
      return;
    }
    try {
      if (entry.kind == _Kind.playlist) {
        var text = utf8.decode(await _read(answer.body, maxPlaylistBytes), allowMalformed: true);
        if (!text.trimLeft().startsWith('#EXTM3U')) {
          await _status(response, HttpStatus.badGateway);
          return;
        }
        final isIndex = identical(entry, _index);
        if (isIndex && recipe.master != null && text.contains('#EXT-X-STREAM-INF')) {
          text = recipe.master!(Uri.parse(_line.url), text);
        }
        final restore = text.contains('#EXT-X-STREAM-INF') ? null : recipe.restore?.call(text);
        if (prefetch != null && !text.contains('#EXT-X-STREAM-INF')) text = _windowOf(entry).serve(text, answer.url);
        final body = utf8.encode(rewrite(text, answer.url, restore: restore, index: isIndex));
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
          ..contentLength = body.length
          ..add(body);
      } else if (entry.restore case final restore?) {
        final body = restore(await _read(answer.body, maxRestoredBytes));
        response
          ..statusCode = HttpStatus.ok
          ..contentLength = body.length
          ..add(body);
      } else {
        response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false;
        if (answer.contentLength >= 0) response.contentLength = answer.contentLength;
        await response.addStream(answer.body);
      }
    } on Object {
      // Upstream or player went away mid-body, or the restorer refused it;
      // the player retries.
      try {
        response.statusCode = HttpStatus.badGateway;
      } on Object {
        // Headers already sent.
      }
    }
    try {
      await response.close();
    } on Object {
      // The player already hung up.
    }
  }

  /// Answers a segment from its media window when it holds it.
  Future<bool> _serveHeld(HttpResponse response, _Entry entry) async {
    final window = _windows.values.where((window) => window.owns(entry.url)).firstOrNull;
    final held = window == null ? null : await window.take(entry.url);
    if (held == null || _closed) return false;
    try {
      final body = entry.restore?.call(held) ?? held;
      response
        ..statusCode = HttpStatus.ok
        ..contentLength = body.length
        ..add(body);
    } on Object {
      try {
        response.statusCode = HttpStatus.badGateway;
      } on Object {
        // Headers already sent.
      }
    }
    try {
      await response.close();
    } on Object {
      // The player already hung up.
    }
    return true;
  }

  void _scheduleRenewal() {
    _renewTimer?.cancel();
    final lease = _line.lease;
    if (renew == null || lease == null || !lease.cutsConnection || _closed) return;
    var delay = lease.refreshAt.difference(_now());
    if (delay < Duration.zero) delay = Duration.zero;
    _renewTimer = Timer(delay, () => unawaited(renewNow()));
  }

  /// Renews the line now: the index points at the renewed URL, and the
  /// child playlists of a master at the renewed master's children by
  /// position. A failure keeps the old line and retries after [retryDelay].
  /// Returns whether the renewal succeeded.
  Future<bool> renewNow() async {
    final renewer = renew;
    if (renewer == null || _closed) return false;
    try {
      final next = await renewer(_line);
      if (_closed) return false;
      if (_masterChildren.isNotEmpty) {
        final source = Uri.parse(next.url);
        final answer = await upstream.get(source, {...next.headers, ..._headersFor(source)});
        _cookies.receive(answer.url, answer.setCookies);
        if (answer.status != HttpStatus.ok) throw UpstreamStatusException(answer.status, source);
        var text = utf8.decode(await _read(answer.body, maxPlaylistBytes), allowMalformed: true);
        if (recipe.master != null && text.contains('#EXT-X-STREAM-INF')) text = recipe.master!(source, text);
        final urls = <Uri>[
          for (final raw in const LineSplitter().convert(text))
            if (raw.trim() case final line when line.isNotEmpty && !line.startsWith('#'))
              ?_resolve(answer.url, line)
            else if (_uriAttribute.firstMatch(raw)?.group(1) case final reference?
                when raw.startsWith('#EXT-X-MEDIA') || raw.startsWith('#EXT-X-I-FRAME-STREAM-INF'))
              ?_resolve(answer.url, reference),
        ];
        if (urls.length != _masterChildren.length) {
          throw const FormatException('The renewed master has other variants');
        }
        for (final (index, name) in _masterChildren.indexed) {
          final entry = _playlists[name];
          if (entry == null) continue;
          _names.remove('${entry.kind.name} ${entry.url}');
          entry.url = urls[index];
          _names['${entry.kind.name} ${entry.url}'] = name;
        }
      }
      _line = next;
      _renewals++;
      _scheduleRenewal();
      return true;
    } on Object {
      if (!_closed) {
        _renewTimer?.cancel();
        _renewTimer = Timer(retryDelay, () => unawaited(renewNow()));
      }
      return false;
    }
  }

  static Future<Uint8List> _read(Stream<List<int>> body, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
      if (builder.length > limit) throw const FormatException('upstream body too large');
    }
    return builder.takeBytes();
  }

  static Future<void> _status(HttpResponse response, int status) async {
    try {
      response.statusCode = status;
      await response.close();
    } on Object {
      // The peer went away.
    }
  }

  /// Stops serving and drops upstream connections.
  void close() {
    _closed = true;
    _renewTimer?.cancel();
    for (final window in _windows.values) {
      window.close();
    }
    _windows.clear();
    _cookies.clear();
    upstream.close();
  }
}
