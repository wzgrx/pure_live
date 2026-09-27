import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_net/live_net.dart';

/// Why a WebDAV request failed.
enum WebDavError {
  /// 401: wrong user name or password.
  unauthorized,

  /// 403: the account may not do this.
  forbidden,

  /// 404: no such file or directory.
  notFound,

  /// 507: the server is full.
  insufficientStorage,

  /// Any other unexpected status.
  server,

  /// No response (DNS, connection, TLS, timeout).
  network,

  /// A response that is not WebDAV (for example an HTML login page).
  invalidResponse,
}

/// A failed WebDAV request. [detail] never contains the password.
final class WebDavException implements Exception {
  /// Creates the exception.
  const new(this.error, {this.status, this.detail});

  /// What went wrong.
  final WebDavError error;

  /// HTTP status, when there was a response.
  final int? status;

  /// Diagnostic detail.
  final String? detail;

  @override
  String toString() =>
      'WebDavException(${error.name}${status == null ? '' : ', $status'}${detail == null ? '' : ': $detail'})';
}

/// One entry of a directory listing.
@immutable
final class WebDavEntry {
  /// Creates an entry.
  const new({required this.path, required this.isDirectory, this.size, this.modified});

  /// Decoded path segments below the profile's base URL.
  final List<String> path;

  /// Whether this is a directory (collection).
  final bool isDirectory;

  /// Size in bytes, when the server reports it.
  final int? size;

  /// Last modification, when the server reports it.
  final DateTime? modified;

  /// The last path segment.
  String get name => path.isEmpty ? '' : path.last;

  @override
  String toString() => 'WebDavEntry(${path.join('/')}${isDirectory ? '/' : ''})';
}

/// One `<response>` of a PROPFIND multistatus body.
@immutable
final class DavResource {
  /// Creates a resource.
  const new({required this.href, required this.isCollection, this.size, this.modified});

  /// The `href` as sent (percent-encoded path or absolute URL).
  final String href;

  /// Whether `resourcetype` contains `collection`.
  final bool isCollection;

  /// `getcontentlength`.
  final int? size;

  /// `getlastmodified`.
  final DateTime? modified;
}

/// A small WebDAV client (F-DAV-01) for backups: list, upload, download,
/// delete and create directories, with HTTP Basic authentication.
///
/// It runs on `live_net`'s [LiveHttp], so requests follow the app's proxy
/// policy under the site id [site]. Paths are lists of decoded segments below
/// [base]; the client encodes them. Digest authentication is not supported
/// (every common service accepts Basic over HTTPS).
final class WebDavClient {
  /// Talks to [base] (a directory URL, trailing slash optional) as
  /// [username] with [password].
  new(
    this._http, {
    required this.base,
    this.username = '',
    String password = '',
    this.timeout = const Duration(seconds: 30),
  }) : _authorization = username.isEmpty && password.isEmpty
           ? null
           : 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// Site id for the proxy policy and logs.
  static const site = 'webdav';

  final LiveHttp _http;

  /// The profile's base URL.
  final Uri base;

  /// User name.
  final String username;

  /// Limit for one request, body included.
  final Duration timeout;

  final String? _authorization;

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop>\n'
      '</d:propfind>\n';

  List<String> get _baseSegments => [
    for (final segment in base.pathSegments)
      if (segment.isNotEmpty) segment,
  ];

  /// The URL of [path]; directories end with a slash.
  Uri urlOf(List<String> path, {bool directory = false}) => base.replace(
    pathSegments: [
      ..._baseSegments,
      for (final segment in path)
        if (segment.isNotEmpty) segment,
      if (directory) '',
    ],
  );

  Future<LiveResponse> _send(String method, Uri url, {Map<String, String> headers = const {}, List<int>? body}) async {
    try {
      return await _http.send(
        LiveRequest(
          site: site,
          url: url,
          method: method,
          headers: {'authorization': ?_authorization, ...headers},
          body: body,
          followRedirects: method == 'GET',
          timeout: timeout,
        ),
      );
    } on TransportFailure catch (failure) {
      throw WebDavException(WebDavError.network, detail: '${failure.reason.name}${_detail(failure.detail)}');
    }
  }

  static String _detail(String? detail) => detail == null ? '' : ': $detail';

  static Never _fail(LiveResponse response) {
    final error = switch (response.status) {
      401 => WebDavError.unauthorized,
      403 => WebDavError.forbidden,
      404 || 410 => WebDavError.notFound,
      507 => WebDavError.insufficientStorage,
      _ => WebDavError.server,
    };
    throw WebDavException(error, status: response.status);
  }

  Future<LiveResponse> _propfind(List<String> directory, {required int depth}) => _send(
    'PROPFIND',
    urlOf(directory, directory: true),
    headers: {'depth': '$depth', 'content-type': 'application/xml; charset=utf-8'},
    body: utf8.encode(_propfindBody),
  );

  /// Checks the connection and credentials; returns whether [directory]
  /// exists (a missing one is created on the first upload).
  Future<bool> check(List<String> directory) async {
    final response = await _propfind(directory, depth: 0);
    if (response.status == 207) {
      if (!_looksLikeMultistatus(response.text)) {
        throw const WebDavException(WebDavError.invalidResponse, detail: 'not a multistatus body');
      }
      return true;
    }
    if (response.status == 404) return false;
    _fail(response);
  }

  /// Lists [directory]: directories first, then files, newest first.
  Future<List<WebDavEntry>> list(List<String> directory) async {
    final response = await _propfind(directory, depth: 1);
    if (response.status != 207) _fail(response);
    final text = response.text;
    if (!_looksLikeMultistatus(text)) {
      throw const WebDavException(WebDavError.invalidResponse, detail: 'not a multistatus body');
    }
    final self = [..._baseSegments, ...directory.where((segment) => segment.isNotEmpty)];
    final entries = <WebDavEntry>[];
    for (final resource in parseMultistatus(text)) {
      final segments = _segmentsOf(resource.href);
      if (segments == null || listEquals(segments, self)) continue;
      // Only direct children of the directory, as Depth 1 promises.
      if (segments.length != self.length + 1 || !listEquals(segments.sublist(0, self.length), self)) continue;
      entries.add(
        WebDavEntry(
          path: [...directory.where((segment) => segment.isNotEmpty), segments.last],
          isDirectory: resource.isCollection,
          size: resource.size,
          modified: resource.modified,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final byTime = (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0));
      return byTime != 0 ? byTime : a.name.compareTo(b.name);
    });
    return entries;
  }

  List<String>? _segmentsOf(String href) {
    try {
      final resolved = base.resolve(href.trim());
      return [
        for (final segment in resolved.pathSegments)
          if (segment.isNotEmpty) segment,
      ];
    } on FormatException {
      return null;
    }
  }

  /// Creates [directory] and its parents when they are missing.
  Future<void> ensureDirectory(List<String> directory) async {
    final segments = directory.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty || await check(segments)) return;
    for (var length = 1; length <= segments.length; length++) {
      final response = await _send('MKCOL', urlOf(segments.sublist(0, length), directory: true));
      // 405: already there.
      if (response.status == 201 || response.status == 200 || response.status == 405) continue;
      _fail(response);
    }
  }

  /// Uploads [bytes] to [path], replacing an existing file.
  Future<void> put(List<String> path, List<int> bytes, {String contentType = 'application/json; charset=utf-8'}) async {
    final response = await _send('PUT', urlOf(path), headers: {'content-type': contentType}, body: bytes);
    if (response.status != 200 && response.status != 201 && response.status != 204) _fail(response);
  }

  /// Downloads [path].
  Future<List<int>> get(List<String> path) async {
    final response = await _send('GET', urlOf(path));
    if (response.status != 200) _fail(response);
    return response.bytes;
  }

  /// Deletes [path]; a missing file counts as deleted.
  Future<void> delete(List<String> path) async {
    final response = await _send('DELETE', urlOf(path));
    if (response.status == 200 || response.status == 202 || response.status == 204 || response.status == 404) return;
    _fail(response);
  }

  static bool _looksLikeMultistatus(String text) => _element('multistatus').hasMatch(text);

  static const _prefix = r'(?:[A-Za-z_][\w.\-]*:)?';

  static RegExp _element(String name) =>
      RegExp('<$_prefix$name\\b[^>]*?(?:/>|>(.*?)</$_prefix$name\\s*>)', dotAll: true, caseSensitive: false);

  static final RegExp _response = _element('response');
  static final RegExp _href = _element('href');
  static final RegExp _resourceType = _element('resourcetype');
  static final RegExp _collection = RegExp('<${_prefix}collection\\b', caseSensitive: false);
  static final RegExp _length = _element('getcontentlength');
  static final RegExp _modified = _element('getlastmodified');

  /// Parses a PROPFIND multistatus body. Tolerates any namespace prefix
  /// (`d:`, `D:`, `lp1:`, none) because servers differ; this is the only XML
  /// the client reads, so it does not need a full XML parser.
  static List<DavResource> parseMultistatus(String xml) {
    final resources = <DavResource>[];
    for (final match in _response.allMatches(xml)) {
      final block = match[1] ?? '';
      final href = _text(_href.firstMatch(block)?[1]);
      if (href == null || href.isEmpty) continue;
      final type = _resourceType.firstMatch(block)?[1] ?? '';
      final length = _text(_length.firstMatch(block)?[1]);
      final modified = _text(_modified.firstMatch(block)?[1]);
      resources.add(
        DavResource(
          href: href,
          isCollection: _collection.hasMatch(type),
          size: length == null ? null : int.tryParse(length),
          modified: modified == null ? null : _parseDate(modified),
        ),
      );
    }
    return resources;
  }

  static DateTime? _parseDate(String value) {
    try {
      return HttpDate.parse(value);
    } on HttpException {
      return DateTime.tryParse(value);
    } on FormatException {
      return DateTime.tryParse(value);
    }
  }

  static final RegExp _cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
  static final RegExp _entity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

  static String? _text(String? raw) {
    if (raw == null) return null;
    final text = raw.replaceAllMapped(_cdata, (m) => m[1]!).trim();
    return text.replaceAllMapped(_entity, (m) {
      final name = m[1]!;
      return switch (name) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ when name.startsWith('#x') => String.fromCharCode(int.parse(name.substring(2), radix: 16)),
        _ => String.fromCharCode(int.parse(name.substring(1))),
      };
    });
  }
}
