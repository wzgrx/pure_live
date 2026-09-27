import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// One upstream answer of an HLS line.
final class HlsUpstreamResponse {
  /// Creates an answer.
  const new({required this.status, required this.url, required this.body, this.contentLength = -1});

  /// HTTP status.
  final int status;

  /// Where the answer came from after redirects: playlists resolve their
  /// entries against it.
  final Uri url;

  /// The body; cancelling the subscription drops the connection.
  final Stream<List<int>> body;

  /// Length when the upstream gave one, else -1.
  final int contentLength;
}

/// Fetches the resources of an HLS line for the relay (SRC-4).
abstract interface class HlsUpstream {
  /// GETs [url] with exactly [headers].
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers);

  /// Drops open connections.
  void close();
}

/// [HlsUpstream] over `dart:io`: TLS verification on, the proxy policy's
/// route for the site per request, reads failing after [idleTimeout]
/// without data.
final class IoHlsUpstream implements HlsUpstream {
  /// Creates the upstream.
  new({
    required String site,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 15),
  }) : _client = HttpClient()
         ..connectionTimeout = connectTimeout
         ..autoUncompress = true
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
    );
  }

  @override
  void close() => _client.close(force: true);
}

enum _Kind { playlist, segment, part, map, key }

final class _Entry {
  new(this.url, this.kind, this.restore);

  final Uri url;
  final _Kind kind;
  SegmentRestore? restore;
}

/// Serves one HLS line on the loopback relay (playback spec SRC-2 item 3):
/// every playlist is fetched upstream and rewritten so that its playlists,
/// segments, maps and keys point back here; each upstream request carries
/// the line's headers and the recipe's cookies for that path; segments of a
/// media playlist go through the recipe's restorer. Only addresses taken
/// from the line's own playlists are served (no open proxy).
final class HlsRoute {
  /// Creates the route under [prefix] (`/<secret>/`).
  new({
    required this.prefix,
    required this.port,
    required this.line,
    required this.upstream,
    this.maxEntries = 2048,
    this.maxPlaylistBytes = 4 << 20,
    this.maxRestoredBytes = 64 << 20,
  });

  /// Path prefix, ending with `/`.
  final String prefix;

  /// Loopback port.
  final int port;

  /// The line served.
  final StreamLine line;

  /// Upstream fetcher.
  final HlsUpstream upstream;

  /// Segments, maps and keys remembered, oldest dropped first.
  final int maxEntries;

  /// Largest playlist read.
  final int maxPlaylistBytes;

  /// Largest segment restored in memory.
  final int maxRestoredBytes;

  final _playlists = <String, _Entry>{};
  final _media = <String, _Entry>{};
  final _names = <String, String>{};
  var _next = 0;
  var _closed = false;

  static const _index = 'index.m3u8';
  static final _uriAttribute = RegExp('URI="([^"]*)"');

  /// The playlist the engine opens.
  Uri get uri => _local(_index);

  Uri _local(String name) => Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '$prefix$name');

  _Entry? _entry(String name) {
    if (name == _index) return _Entry(line.url, _Kind.playlist, null);
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

  /// [text] with its references pointing back to this route; [base] is the
  /// playlist's upstream address.
  String rewrite(String text, Uri base, {SegmentRestore? restore}) {
    final master = text.contains('#EXT-X-STREAM-INF');
    String? local(String reference, _Kind kind) {
      final Uri url;
      try {
        url = base.resolve(reference.trim());
      } on FormatException {
        return null;
      }
      if (!url.isScheme('http') && !url.isScheme('https')) return null;
      return _local(_name(url, kind, kind == _Kind.segment ? restore : null)).toString();
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
    return out.toString();
  }

  Map<String, String> _headersFor(Uri url) {
    final headers = {...line.headers};
    final recipe = line.hlsRelay;
    if (recipe?.cookies != null) {
      final cookie = recipe!.cookieHeaderFor(url);
      if (cookie == null) {
        headers.remove('cookie');
      } else {
        headers['cookie'] = cookie;
      }
    }
    return headers;
  }

  /// Answers [request] for [name]; unknown names get 404.
  Future<void> serve(HttpRequest request, String name) async {
    final response = request.response;
    final entry = _closed ? null : _entry(name);
    if (entry == null || request.method != 'GET') {
      await _status(response, HttpStatus.notFound);
      return;
    }
    HlsUpstreamResponse answer;
    try {
      answer = await upstream.get(entry.url, _headersFor(entry.url));
    } on Object {
      await _status(response, HttpStatus.badGateway);
      return;
    }
    if (answer.status != HttpStatus.ok) {
      unawaited(answer.body.drain<void>().catchError((Object _) {}));
      await _status(response, answer.status >= 400 ? answer.status : HttpStatus.badGateway);
      return;
    }
    try {
      if (entry.kind == _Kind.playlist) {
        final bytes = await _read(answer.body, maxPlaylistBytes);
        final text = utf8.decode(bytes, allowMalformed: true);
        if (!text.trimLeft().startsWith('#EXTM3U')) {
          await _status(response, HttpStatus.badGateway);
          return;
        }
        final restore = text.contains('#EXT-X-STREAM-INF') ? null : line.hlsRelay?.restore?.call(text);
        final body = utf8.encode(rewrite(text, answer.url, restore: restore));
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
      // Upstream or player went away mid-body; the player retries.
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
    upstream.close();
  }
}
