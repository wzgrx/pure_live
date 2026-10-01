import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_auth.dart';

/// A file or folder on a WebDAV server.
final class WebDavEntry {
  /// Creates the entry.
  const new({required this.path, required this.isDir, this.modified, this.size});

  /// Path segments below the server's base folder.
  final List<String> path;

  /// Whether it is a folder.
  final bool isDir;

  /// Last change, when the server says.
  final DateTime? modified;

  /// Size in bytes, when the server says (files).
  final int? size;

  /// The name.
  String get name => path.isEmpty ? '' : path.last;
}

/// Why a WebDAV request failed.
enum WebDavProblem {
  /// The server refused the user name or password (401, 403).
  auth,

  /// The folder or file is not there (404, 409).
  notFound,

  /// The server answered something else.
  server,

  /// No answer (network, timeout, TLS).
  network,
}

/// A failed WebDAV request.
final class WebDavFailure implements Exception {
  /// Creates the failure.
  const new(this.problem, {this.status, this.detail = ''});

  /// What went wrong.
  final WebDavProblem problem;

  /// HTTP status, when there was an answer.
  final int? status;

  /// Technical detail for the log.
  final String detail;

  @override
  String toString() => 'WebDavFailure($problem, $status, $detail)';
}

/// How a [WebDavClient] signs its requests.
enum _Scheme { none, basic, digest }

/// The credentials one request went with.
typedef _Signed = ({_Scheme scheme, int count, String? authorization});

/// The WebDAV calls the backup page needs (3.x used webdav_client:
/// `readDir`, `read`, `write`, `remove`), over the app's [LiveHttp] so the
/// app proxy applies.
///
/// Authentication follows 3.x's webdav_client: the first request goes without
/// credentials and the server's `401` challenge picks Basic or Digest (Digest
/// when both are offered); later requests sign with that scheme directly.
/// Jianguoyun, Nextcloud and Alist ask for Basic.
final class WebDavClient {
  /// Creates the client for [config].
  new(this._http, this.config) : _base = Uri.parse(config.address.trim());

  final LiveHttp _http;

  /// The server.
  final WebDavConfig config;
  final Uri _base;

  static const String _site = 'webdav';

  List<String> get _baseSegments => [
    for (final segment in _base.pathSegments)
      if (segment.isNotEmpty) segment,
  ];

  /// The URL of [path] below the base folder; folders end with `/`.
  Uri urlOf(List<String> path, {bool dir = false}) =>
      _base.replace(pathSegments: [..._baseSegments, ...path, if (dir || path.isEmpty) '']);

  _Scheme _scheme = _Scheme.none;
  DigestChallenge? _digest;

  /// Requests signed with [_digest]'s nonce so far.
  int _nonceCount = 0;

  /// The request target Digest signs: what the request line carries.
  static String _target(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    return url.hasQuery ? '$path?${url.query}' : path;
  }

  /// The credentials for one request under the current scheme.
  _Signed _sign(String method, Uri url) {
    switch (_scheme) {
      case _Scheme.none:
        return (scheme: _Scheme.none, count: 0, authorization: null);
      case _Scheme.basic:
        final token = base64.encode(utf8.encode('${config.username}:${config.password}'));
        return (scheme: _Scheme.basic, count: 0, authorization: 'Basic $token');
      case _Scheme.digest:
        final count = ++_nonceCount;
        return (
          scheme: _Scheme.digest,
          count: count,
          authorization: digestAuthorization(
            challenge: _digest!,
            username: config.username,
            password: config.password,
            method: method,
            uri: _target(url),
            nc: count,
            cnonce: randomCnonce(),
          ),
        );
    }
  }

  /// Takes the scheme a `401` asks for; returns whether to send the request
  /// again. A request is not repeated with the credentials that just failed:
  /// Basic again, or Digest with a fresh nonce that is not `stale`. A `401`
  /// without a challenge gets one try with Basic; a challenge this client
  /// cannot answer (Bearer, SHA-256 Digest) gets no password.
  bool _learn(LiveResponse response, _Signed sent) {
    final challenges = parseAuthChallenges(response.headers['www-authenticate'] ?? const []);
    final digest = challenges.map(DigestChallenge.from).nonNulls.firstOrNull;
    if (digest != null) {
      _scheme = _Scheme.digest;
      _digest = digest;
      _nonceCount = 0;
      return sent.scheme != _Scheme.digest || digest.stale || sent.count > 1;
    }
    if (challenges.any((challenge) => challenge.scheme == 'basic') ||
        (challenges.isEmpty && sent.scheme == _Scheme.none)) {
      _scheme = _Scheme.basic;
      return sent.scheme != _Scheme.basic;
    }
    return false;
  }

  Future<LiveResponse> _exchange(
    String method,
    Uri url,
    Map<String, String> headers,
    List<int>? body,
    _Signed sent,
  ) async {
    try {
      return await _http.send(
        LiveRequest(
          site: _site,
          url: url,
          method: method,
          headers: {'authorization': ?sent.authorization, ...headers},
          body: body,
          timeout: const Duration(seconds: 30),
        ),
      );
    } on TransportFailure catch (error) {
      throw WebDavFailure(WebDavProblem.network, detail: '$error');
    }
  }

  Future<LiveResponse> _send(String method, Uri url, {Map<String, String> headers = const {}, List<int>? body}) async {
    var sent = _sign(method, url);
    var response = await _exchange(method, url, headers, body, sent);
    if (response.status == 401 && _learn(response, sent)) {
      sent = _sign(method, url);
      response = await _exchange(method, url, headers, body, sent);
      if (response.status == 401) _learn(response, sent);
    }
    if (response.isSuccess) return response;
    throw WebDavFailure(switch (response.status) {
      401 || 403 => WebDavProblem.auth,
      404 || 409 => WebDavProblem.notFound,
      _ => WebDavProblem.server,
    }, status: response.status);
  }

  static const String _propfind =
      '<?xml version="1.0" encoding="utf-8"?> '
      '<d:propfind xmlns:d="DAV:"><d:prop> '
      '<d:resourcetype/><d:getlastmodified/><d:getcontentlength/>'
      '</d:prop></d:propfind>';

  /// The contents of folder [dir] (`PROPFIND`, depth 1), without the folder
  /// itself.
  Future<List<WebDavEntry>> list(List<String> dir) async {
    final url = urlOf(dir, dir: true);
    final response = await _send(
      'PROPFIND',
      url,
      headers: {'depth': '1', 'content-type': 'application/xml; charset=utf-8'},
      body: utf8.encode(_propfind),
    );
    return parseMultistatus(response.text, requestUrl: response.url, base: _baseSegments, dir: dir);
  }

  /// Checks that the base folder can be listed (the settings dialog's test).
  Future<void> check() async {
    await _send(
      'PROPFIND',
      urlOf(const [], dir: true),
      headers: {'depth': '0', 'content-type': 'application/xml; charset=utf-8'},
      body: utf8.encode(_propfind),
    );
  }

  /// Reads file [path].
  Future<List<int>> read(List<String> path) async => (await _send('GET', urlOf(path))).bytes;

  /// Writes file [path].
  Future<void> write(List<String> path, List<int> bytes) =>
      _send('PUT', urlOf(path), headers: {'content-type': 'text/plain; charset=utf-8'}, body: bytes);

  /// Removes file or folder [path].
  Future<void> remove(List<String> path, {bool dir = false}) => _send('DELETE', urlOf(path, dir: dir));
}

/// Reads a `207 Multi-Status` answer: one entry per `response`, its path
/// relative to the [base] segments, without the listed folder [dir] itself.
/// Namespace prefixes vary between servers (`d:`, `D:`, `lp1:`, none), so
/// elements are matched by local name.
List<WebDavEntry> parseMultistatus(
  String xml, {
  required Uri requestUrl,
  required List<String> base,
  required List<String> dir,
}) {
  final entries = <WebDavEntry>[];
  for (final match in _element('response').allMatches(xml)) {
    final body = match.group(1) ?? '';
    final href = _text(body, 'href');
    if (href == null || href.isEmpty) continue;
    final Uri url;
    try {
      url = requestUrl.resolve(href);
    } on FormatException {
      continue;
    }
    final segments = [
      for (final segment in url.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.length < base.length || !_startsWith(segments, base)) continue;
    final path = segments.sublist(base.length);
    if (_same(path, dir)) continue;
    final type = _text(body, 'resourcetype') ?? '';
    final isDir = RegExp(r'<(?:[\w.-]+:)?collection\b').hasMatch(type) || url.path.endsWith('/');
    DateTime? modified;
    final lastModified = _text(body, 'getlastmodified');
    if (lastModified != null && lastModified.isNotEmpty) {
      try {
        modified = HttpDate.parse(lastModified);
      } on Object {
        modified = DateTime.tryParse(lastModified);
      }
    }
    final size = int.tryParse(_text(body, 'getcontentlength') ?? '');
    entries.add(WebDavEntry(path: path, isDir: isDir, modified: modified, size: isDir ? null : size));
  }
  return entries;
}

bool _startsWith(List<String> list, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (list[i] != prefix[i]) return false;
  }
  return true;
}

bool _same(List<String> a, List<String> b) => a.length == b.length && _startsWith(a, b);

RegExp _element(String name) =>
    RegExp('<(?:[\\w.-]+:)?$name\\b[^>]*>(.*?)</(?:[\\w.-]+:)?$name\\s*>', dotAll: true, caseSensitive: false);

String? _text(String xml, String name) {
  final match = _element(name).firstMatch(xml);
  if (match == null) return null;
  return _unescape(match.group(1)!.trim());
}

String _unescape(String text) => text.replaceAllMapped(RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'), (m) {
  final code = m.group(1)!;
  return switch (code) {
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'quot' => '"',
    'apos' => "'",
    _ when code.startsWith('#x') => String.fromCharCode(int.parse(code.substring(2), radix: 16)),
    _ => String.fromCharCode(int.parse(code.substring(1))),
  };
});
