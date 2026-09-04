import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pure_live/core/common/log.dart';

/// Relays verified HTTPS HLS resources over an app-private loopback server.
///
/// FFmpeg 9.0.1's HLS demuxer copies headers, cookies and timeouts from the
/// manifest connection to child requests, but not the `ca_file` TLS option.
/// Embedded OpenSSL builds on Android/Linux therefore verify the manifest and
/// can still reject a segment from the same server. Dart uses the platform
/// trust path correctly, so this relay keeps certificate and hostname checks
/// enabled upstream while FFmpeg reads only short-lived loopback HTTP URLs.
class FFmpegHlsInputRelay {
  FFmpegHlsInputRelay._({
    required this._server,
    required this._client,
    required Uri upstream,
    required this._headers,
    required this._secret,
  }) {
    _resources['root'] = upstream;
  }

  static const int _maximumManifestBytes = 4 * 1024 * 1024;
  static final RegExp _hlsPath = RegExp(r'\.m3u8$', caseSensitive: false);
  static final RegExp _uriAttribute = RegExp(r'URI="([^"]+)"', caseSensitive: false);
  static const Set<String> _allowedMediaExtensions = <String>{
    '3gp',
    'aac',
    'ac3',
    'avi',
    'eac3',
    'flac',
    'm4a',
    'm4s',
    'm4v',
    'mkv',
    'mov',
    'mp2',
    'mp3',
    'mp4',
    'mpeg',
    'mpegts',
    'mpg',
    'mxf',
    'ogg',
    'pls',
    'ts',
    'vob',
    'vtt',
    'wav',
    'webvtt',
  };

  final HttpServer _server;
  final HttpClient _client;
  final Map<String, String> _headers;
  final String _secret;
  final Map<String, Uri> _resources = <String, Uri>{};
  final Map<String, String> _resourceIds = <String, String>{};
  StreamSubscription<HttpRequest>? _subscription;
  var _nextResourceId = 0;
  var _closed = false;

  Uri get inputUri =>
      Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port, path: '/$_secret/root.m3u8');

  /// Creates a relay only for the first HTTPS HLS input on Android/Linux.
  /// [force] exists for deterministic loopback unit tests on desktop hosts.
  static Future<FFmpegHlsInputRelay?> startForArguments(Iterable<String> source, {bool force = false}) async {
    final arguments = List<String>.of(source);
    final inputIndex = arguments.indexOf('-i');
    if (inputIndex < 0 || inputIndex + 1 >= arguments.length) return null;

    final upstream = Uri.tryParse(arguments[inputIndex + 1].trim());
    if (upstream == null || !_isHlsUri(upstream)) return null;
    final supportedHost = !kIsWeb && (Platform.isAndroid || Platform.isLinux);
    if (!force && (!supportedHost || upstream.scheme.toLowerCase() != 'https')) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20)
      ..autoUncompress = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    final relay = FFmpegHlsInputRelay._(
      server: server,
      client: client,
      upstream: upstream,
      headers: _readInputHeaders(arguments, inputIndex),
      secret: _newSecret(),
    );
    relay._subscription = server.listen(relay._handleRequest, onError: relay._handleServerError);
    return relay;
  }

  List<String> replaceFirstInput(Iterable<String> source) {
    final arguments = List<String>.of(source);
    final inputIndex = arguments.indexOf('-i');
    if (inputIndex >= 0 && inputIndex + 1 < arguments.length) {
      arguments[inputIndex + 1] = inputUri.toString();
    }
    return List<String>.unmodifiable(arguments);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _subscription?.cancel();
    await _server.close(force: true);
    _resources.clear();
    _resourceIds.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (_closed || segments.length != 2 || segments.first != _secret) {
      await _replyStatus(request, HttpStatus.notFound);
      return;
    }
    final resourceId = segments.last.split('.').first;
    final upstream = _resources[resourceId];
    if (upstream == null || (request.method != 'GET' && request.method != 'HEAD')) {
      await _replyStatus(request, upstream == null ? HttpStatus.notFound : HttpStatus.methodNotAllowed);
      return;
    }

    try {
      final upstreamRequest = await _client.openUrl(request.method, upstream);
      for (final entry in _headers.entries) {
        upstreamRequest.headers.set(entry.key, entry.value, preserveHeaderCase: true);
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);

      final upstreamResponse = await upstreamRequest.close().timeout(const Duration(seconds: 20));
      final finalUri = upstreamResponse.redirects.fold<Uri>(
        upstream,
        (current, redirect) => current.resolveUri(redirect.location),
      );
      request.response.statusCode = upstreamResponse.statusCode;
      final contentType = upstreamResponse.headers.contentType;
      if (contentType != null) request.response.headers.contentType = contentType;
      _copyResponseHeader(upstreamResponse, request.response, HttpHeaders.acceptRangesHeader);
      _copyResponseHeader(upstreamResponse, request.response, HttpHeaders.contentRangeHeader);

      if (request.method == 'HEAD') {
        await upstreamResponse.drain<void>();
        await request.response.close();
        return;
      }

      if (_isManifest(finalUri, contentType)) {
        final bytes = await _readManifest(upstreamResponse);
        final manifest = utf8.decode(bytes, allowMalformed: true);
        final rewritten = _rewriteManifest(manifest, finalUri);
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.write(rewritten);
        await request.response.close();
        return;
      }

      final length = upstreamResponse.contentLength;
      if (length >= 0) request.response.contentLength = length;
      await upstreamResponse.pipe(request.response);
    } on TimeoutException {
      await _replyStatus(request, HttpStatus.gatewayTimeout);
    } on Object catch (error) {
      Log.w('FFmpeg HLS relay request failed for ${upstream.host}: $error');
      await _replyStatus(request, HttpStatus.badGateway);
    }
  }

  String _rewriteManifest(String source, Uri baseUri) {
    final hadTrailingNewline = source.endsWith('\n');
    final output = <String>[];
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add('');
      } else if (trimmed.startsWith('#')) {
        output.add(
          line.replaceAllMapped(_uriAttribute, (match) {
            final replacement = _localResource(baseUri.resolve(match.group(1)!));
            return replacement == null ? match.group(0)! : 'URI="$replacement"';
          }),
        );
      } else {
        output.add(_localResource(baseUri.resolve(trimmed)) ?? line);
      }
    }
    final value = output.join('\n');
    return hadTrailingNewline ? '$value\n' : value;
  }

  String? _localResource(Uri upstream) {
    if (!const <String>{'http', 'https'}.contains(upstream.scheme.toLowerCase())) return null;
    final key = upstream.toString();
    final id = _resourceIds.putIfAbsent(key, () {
      final value = (++_nextResourceId).toRadixString(36);
      _resources[value] = upstream;
      return value;
    });
    final extension = _localExtension(upstream);
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server.port,
      path: '/$_secret/$id$extension',
    ).toString();
  }

  static bool _isHlsUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return const <String>{'http', 'https'}.contains(scheme) && _hlsPath.hasMatch(uri.path);
  }

  /// FFmpeg validates an HLS child URL's suffix before opening it. Opaque
  /// loopback IDs therefore keep a known media suffix even when a CDN uses a
  /// suffix-less or script-style URL. The response bytes remain authoritative
  /// for demuxing; this only passes FFmpeg's pre-open allow-list.
  static String _localExtension(Uri upstream) {
    if (_isHlsUri(upstream)) return '.m3u8';
    final lastSegment = upstream.pathSegments.isEmpty ? '' : upstream.pathSegments.last;
    final separator = lastSegment.lastIndexOf('.');
    if (separator >= 0 && separator + 1 < lastSegment.length) {
      final extension = lastSegment.substring(separator + 1).toLowerCase();
      if (_allowedMediaExtensions.contains(extension)) return '.$extension';
    }
    return '.ts';
  }

  static bool _isManifest(Uri uri, ContentType? contentType) {
    if (_isHlsUri(uri)) return true;
    final mime = contentType?.mimeType.toLowerCase() ?? '';
    return mime.contains('mpegurl') || mime == 'application/x-mpegurl';
  }

  static Map<String, String> _readInputHeaders(List<String> arguments, int inputIndex) {
    final headers = <String, String>{};
    for (var index = 0; index < inputIndex - 1; index++) {
      final option = arguments[index];
      final value = arguments[index + 1];
      if (option == '-user_agent' && value.trim().isNotEmpty) {
        headers[HttpHeaders.userAgentHeader] = value.trim();
      } else if (option == '-headers') {
        for (final line in value.split(RegExp(r'[\r\n]+'))) {
          final separator = line.indexOf(':');
          if (separator <= 0) continue;
          final name = line.substring(0, separator).trim();
          final headerValue = line.substring(separator + 1).trim();
          if (name.isEmpty || headerValue.isEmpty || _isHopByHopHeader(name)) continue;
          headers[name] = headerValue;
        }
      }
    }
    return Map<String, String>.unmodifiable(headers);
  }

  static bool _isHopByHopHeader(String name) {
    return const <String>{
      'connection',
      'content-length',
      'host',
      'keep-alive',
      'proxy-authenticate',
      'proxy-authorization',
      'te',
      'trailer',
      'transfer-encoding',
      'upgrade',
    }.contains(name.toLowerCase());
  }

  static String _newSecret() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(18, (_) => random.nextInt(256), growable: false));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<Uint8List> _readManifest(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > _maximumManifestBytes) throw const FormatException('HLS manifest exceeds the relay limit');
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static void _copyResponseHeader(HttpClientResponse source, HttpResponse destination, String name) {
    final value = source.headers.value(name);
    if (value != null && value.isNotEmpty) destination.headers.set(name, value);
  }

  static Future<void> _replyStatus(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      request.response.headers.contentLength = 0;
    } on StateError {
      // A streaming response may already have committed its headers. Closing
      // it still wakes FFmpeg immediately instead of leaving a partial request
      // waiting for the read timeout.
    }
    await request.response.close();
  }

  void _handleServerError(Object error, StackTrace stackTrace) {
    if (!_closed) Log.w('FFmpeg HLS relay server failed: $error\n$stackTrace');
  }
}
