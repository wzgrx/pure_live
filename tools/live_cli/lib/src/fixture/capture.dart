import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:live_cli/src/fixture/scrub.dart';

/// Version written into meta.json; bump when the sample layout changes.
const fixtureSchema = 1;

/// One HTTP request to record.
class CaptureRequest {
  /// Creates a request.
  const new({required this.url, this.method = 'GET', this.headers = const {}, this.body});

  /// Absolute URL.
  final Uri url;

  /// HTTP method.
  final String method;

  /// Request headers, sent as given.
  final Map<String, String> headers;

  /// Form or JSON body for POST.
  final String? body;
}

/// The raw exchange before scrubbing.
class RawExchange {
  /// Creates an exchange.
  const new({
    required this.request,
    required this.status,
    required this.headers,
    required this.body,
    required this.route,
    required this.capturedAt,
  });

  /// What was sent.
  final CaptureRequest request;

  /// HTTP status code.
  final int status;

  /// Response headers; repeated headers (Set-Cookie) keep every value.
  final Map<String, List<String>> headers;

  /// Response body bytes, after content decoding.
  final List<int> body;

  /// `direct` or the proxy URL used.
  final String route;

  /// When the response arrived (UTC).
  final DateTime capturedAt;
}

/// Performs [request]; [proxy] is `direct`, `env` (HTTPS_PROXY) or `host:port`.
Future<RawExchange> fetch(CaptureRequest request, {String proxy = 'direct'}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..autoUncompress = true;
  var route = 'direct';
  if (proxy == 'env') {
    client.findProxy = HttpClient.findProxyFromEnvironment;
    route = 'env:${HttpClient.findProxyFromEnvironment(request.url)}';
  } else if (proxy != 'direct') {
    client.findProxy = (_) => 'PROXY $proxy';
    route = 'proxy:$proxy';
  } else {
    client.findProxy = (_) => 'DIRECT';
  }
  try {
    final outgoing = await client.openUrl(request.method, request.url);
    outgoing.followRedirects = false;
    request.headers.forEach(outgoing.headers.set);
    if (request.body != null) outgoing.write(request.body);
    final response = await outgoing.close().timeout(const Duration(seconds: 60));
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) => headers[name] = [...values]);
    return RawExchange(
      request: request,
      status: response.statusCode,
      headers: headers,
      body: bytes,
      route: route,
      capturedAt: DateTime.now().toUtc(),
    );
  } finally {
    client.close(force: true);
  }
}

/// Result of [writeSample].
class WrittenSample {
  /// Creates a result.
  const new(this.directory, this.bodyFile, this.records);

  /// Sample directory.
  final Directory directory;

  /// Body file name.
  final String bodyFile;

  /// What was replaced.
  final List<ScrubRecord> records;
}

/// Thrown when a scrubbed file still contains an original secret.
class LeakException implements Exception {
  /// Creates the exception.
  const new(this.file, this.count);

  /// File that leaked.
  final String file;

  /// Number of distinct originals found (the values are not repeated here).
  final int count;

  @override
  String toString() => 'LeakException: $file still contains $count original value(s); nothing was written';
}

const _sensitiveRequestHeaders = {'authorization', 'x-csrf-token', 'x-auth-token'};

/// Scrubs [exchange] and writes body + meta.json into [directory]. The files
/// are only written when neither contains any original value.
Future<WrittenSample> writeSample(
  RawExchange exchange,
  Scrubber scrubber, {
  required Directory directory,
  required String platform,
  required String sample,
  String? extension,
  String tool = 'live_cli',
}) async {
  final contentType = exchange.headers['content-type']?.first ?? '';
  final ext = extension ?? _extensionFor(contentType, exchange.body);

  final requestHeaders = <String, String>{};
  exchange.request.headers.forEach((name, value) {
    final lower = name.toLowerCase();
    if (lower == 'cookie') {
      requestHeaders[name] = scrubber.scrubCookieHeader(value);
    } else if (_sensitiveRequestHeaders.contains(lower)) {
      requestHeaders[name] = scrubber.replace(value, ScrubRule.secret, 'header:$name');
    } else {
      requestHeaders[name] = value;
    }
  });
  final responseHeaders = <String, Object>{};
  exchange.headers.forEach((name, values) {
    final scrubbed = [
      for (final value in values)
        if (name == 'set-cookie') scrubber.scrubSetCookie(value) else scrubber.scrubQuery(value, 'header:$name'),
    ];
    responseHeaders[name] = scrubbed.length == 1 ? scrubbed.single : scrubbed;
  });

  final String bodyText;
  List<int>? bodyBytes;
  if (ext == 'bin') {
    bodyText = '';
    bodyBytes = exchange.body;
  } else {
    final text = utf8.decode(exchange.body, allowMalformed: true);
    bodyText = ext == 'json' ? _scrubJsonText(text, scrubber) : scrubber.scrubText(text);
  }
  final url = scrubber.scrubQuery(exchange.request.url.toString(), 'url');
  final requestBody = exchange.request.body == null ? null : scrubber.scrubQuery(exchange.request.body!, 'form');

  final meta = <String, Object?>{
    'schema': fixtureSchema,
    'platform': platform,
    'sample': sample,
    'capturedAt': exchange.capturedAt.toIso8601String(),
    'route': exchange.route,
    'request': {'method': exchange.request.method, 'url': url, 'headers': requestHeaders, 'body': ?requestBody},
    'response': {'status': exchange.status, 'headers': responseHeaders},
    'raw': {'sha256': sha256.convert(exchange.body).toString(), 'length': exchange.body.length},
    'body': 'body.$ext',
    'scrubbed': [for (final record in scrubber.records) record.toJson()],
    'tool': tool,
  };
  final metaText = '${const JsonEncoder.withIndent('  ').convert(meta)}\n';

  for (final (name, text) in [('body.$ext', bodyText), ('meta.json', metaText)]) {
    final leaks = scrubber.leaks(text);
    if (leaks.isNotEmpty) throw LeakException(name, leaks.length);
  }

  await directory.create(recursive: true);
  final bodyFile = File('${directory.path}/body.$ext');
  if (bodyBytes != null) {
    await bodyFile.writeAsBytes(bodyBytes);
  } else {
    await bodyFile.writeAsString(bodyText);
  }
  await File('${directory.path}/meta.json').writeAsString(metaText);
  return WrittenSample(directory, 'body.$ext', scrubber.records);
}

/// JSON bodies are scrubbed structurally and re-encoded with two-space
/// indentation so reviews show field-level diffs; the raw hash stays in meta.
String _scrubJsonText(String text, Scrubber scrubber) {
  try {
    final decoded = scrubber.scrubJson(jsonDecode(text));
    return '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  } on FormatException {
    return scrubber.scrubText(text);
  }
}

String _extensionFor(String contentType, List<int> body) {
  final type = contentType.toLowerCase();
  if (type.contains('json')) return 'json';
  if (type.contains('html')) return 'html';
  if (type.contains('javascript')) return 'js';
  if (type.contains('xml')) return 'xml';
  if (type.contains('mpegurl')) return 'm3u8';
  if (type.startsWith('text/')) return 'txt';
  final head = utf8.decode(body.take(64).toList(), allowMalformed: true).trimLeft();
  if (head.startsWith('{') || head.startsWith('[')) return 'json';
  if (head.startsWith('<')) return 'html';
  return 'bin';
}
