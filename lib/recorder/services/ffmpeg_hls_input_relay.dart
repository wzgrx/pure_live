import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pure_live/core/common/log.dart';

/// Relays HLS resources over an app-private loopback server, verifying upstream
/// HTTPS and allowing recording inputs to end without cancelling output IO.
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
    required this.drainOnStop,
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
  final bool drainOnStop;
  final Map<String, Uri> _resources = <String, Uri>{};
  final Map<String, String> _resourceIds = <String, String>{};
  final Map<String, String> _manifests = <String, String>{};
  // Retain current and previous playlist generations, including keys/maps and
  // all nested renditions. Never retain every segment seen since startup.
  final Map<String, List<Set<String>>> _manifestReferences = {};
  final Map<String, int> _activeResources = {};
  StreamSubscription<HttpRequest>? _subscription;
  Future<void>? _closing;
  var _nextResourceId = 0;
  var _closed = false;
  var _finishing = false;
  var _targetSeconds = 1;

  bool get finishRequested => _finishing;

  // Native HLS reloads on the playlist's target duration. Do not impose FLV's
  // shorter drain budget and cancel before a healthy playlist can be reloaded.
  Duration get drainTimeout => Duration(seconds: (2 * _targetSeconds + 2).clamp(3, 20));

  @visibleForTesting
  int get resourceCount => _resources.length;

  Uri get inputUri =>
      Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port, path: '/$_secret/root.m3u8');

  /// TLS relay: first HTTPS HLS input on Android/Linux. Live recordings opt in
  /// on every native platform so ENDLIST can finish input without cancel IO.
  /// [force] exists for deterministic loopback unit tests on desktop hosts.
  static Future<FFmpegHlsInputRelay?> startForArguments(
    Iterable<String> source, {
    bool force = false,
    bool drainOnStop = false,
  }) async {
    final arguments = List<String>.of(source);
    final inputIndex = arguments.indexOf('-i');
    if (inputIndex < 0 || inputIndex + 1 >= arguments.length) return null;

    final upstream = Uri.tryParse(arguments[inputIndex + 1].trim());
    if (upstream == null || !_isHlsUri(upstream)) return null;
    final supportedHost = !kIsWeb && (Platform.isAndroid || Platform.isLinux);
    if (!force && !drainOnStop && (!supportedHost || upstream.scheme.toLowerCase() != 'https')) return null;

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
      drainOnStop: drainOnStop,
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

  /// Freeze each media playlist at the last published generation with ENDLIST.
  /// Keep active media/key/map responses intact; no bytes are cut mid-segment.
  Future<void> finish() async {
    if (drainOnStop) _finishing = true;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
    await _subscription?.cancel();
    _resources.clear();
    _resourceIds.clear();
    _manifests.clear();
    _manifestReferences.clear();
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

    _activeResources.update(resourceId, (count) => count + 1, ifAbsent: () => 1);
    try {
      final cached = _manifests[resourceId];
      if (_finishing && (cached != null || _isHlsUri(upstream))) {
        await _replyManifest(request, _endedManifest(cached));
        return;
      }
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

      if (upstreamResponse.statusCode == HttpStatus.ok && _isManifest(finalUri, contentType)) {
        final bytes = await _readManifest(upstreamResponse);
        if (_closed) return;
        final manifest = utf8.decode(bytes, allowMalformed: true);
        // Stop may arrive while a refresh is in flight. Do not extend the
        // recording by publishing its newer generation after the stop intent.
        final previous = _manifests[resourceId];
        final rewritten = _finishing && previous != null ? previous : _rewriteManifest(manifest, finalUri, resourceId);
        await _replyManifest(request, _finishing ? _endedManifest(rewritten) : rewritten);
        return;
      }

      final length = upstreamResponse.contentLength;
      if (length >= 0) request.response.contentLength = length;
      request.response.bufferOutput = false;
      await upstreamResponse.pipe(request.response);
    } on TimeoutException {
      await _replyStatus(request, HttpStatus.gatewayTimeout);
    } on Object catch (error) {
      if (!_closed) Log.w('FFmpeg HLS relay request failed for ${upstream.host}: $error');
      await _replyStatus(request, HttpStatus.badGateway);
    } finally {
      final count = _activeResources[resourceId] ?? 1;
      if (count <= 1) {
        _activeResources.remove(resourceId);
      } else {
        _activeResources[resourceId] = count - 1;
      }
      _pruneResources();
    }
  }

  String _rewriteManifest(String source, Uri baseUri, String manifestId) {
    final hadTrailingNewline = source.endsWith('\n');
    final output = <String>[];
    final referenced = <String>{};
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add('');
      } else if (trimmed.startsWith('#')) {
        output.add(
          line.replaceAllMapped(_uriAttribute, (match) {
            final replacement = _localResource(baseUri.resolve(match.group(1)!), referenced);
            return replacement == null ? match.group(0)! : 'URI="$replacement"';
          }),
        );
      } else {
        output.add(_localResource(baseUri.resolve(trimmed), referenced) ?? line);
      }
    }
    final value = output.join('\n');
    final rewritten = hadTrailingNewline ? '$value\n' : value;
    // Per-response cap plus aggregate cap bound malicious/oversized trees.
    final retainedCharacters = _manifests.entries
        .where((entry) => entry.key != manifestId)
        .fold<int>(0, (total, entry) => total + entry.value.length);
    if (retainedCharacters + rewritten.length > 8 * 1024 * 1024) {
      throw const FormatException('HLS manifest tree exceeds the relay limit');
    }
    _manifests[manifestId] = rewritten;
    final previous = _manifestReferences[manifestId];
    _manifestReferences[manifestId] = [referenced, if (previous != null) previous.first];
    final target = RegExp(r'^#EXT-X-TARGETDURATION:(\d+)', multiLine: true).firstMatch(source);
    _targetSeconds = max(_targetSeconds, int.tryParse(target?.group(1) ?? '') ?? 1);
    // Publish a generation only after its registry is reconciled. Waiting for
    // response.close lets the next request observe an obsolete third window.
    _pruneResources();
    return rewritten;
  }

  String? _localResource(Uri upstream, Set<String> referenced) {
    if (!const <String>{'http', 'https'}.contains(upstream.scheme.toLowerCase())) return null;
    final key = upstream.toString();
    final id = _resourceIds.putIfAbsent(key, () {
      final value = (++_nextResourceId).toRadixString(36);
      _resources[value] = upstream;
      return value;
    });
    referenced.add(id);
    final extension = _localExtension(upstream);
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server.port,
      path: '/$_secret/$id$extension',
    ).toString();
  }

  void _pruneResources() {
    if (_closed) return;
    final reachable = <String>{};
    final pending = <String>['root', ..._activeResources.keys];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!reachable.add(id)) continue;
      for (final generation in _manifestReferences[id] ?? <Set<String>>[]) {
        pending.addAll(generation);
      }
    }
    for (final id in _resources.keys.where((id) => !reachable.contains(id)).toList()) {
      final uri = _resources.remove(id);
      if (uri != null) _resourceIds.remove(uri.toString());
      _manifests.remove(id);
      _manifestReferences.remove(id);
    }
  }

  static String _endedManifest(String? cached) {
    if (cached == null) return '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-ENDLIST\n';
    // ENDLIST belongs to media playlists, never a master variant catalogue.
    if (!cached.contains('#EXT-X-TARGETDURATION:') || cached.contains('#EXT-X-ENDLIST')) return cached;
    return '${cached.trimRight()}\n#EXT-X-ENDLIST\n';
  }

  static Future<void> _replyManifest(HttpRequest request, String manifest) async {
    request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (request.method != 'HEAD') request.response.write(manifest);
    await request.response.close();
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
    try {
      await request.response.close();
    } on Object {
      // The native reader or service close may already have ended this socket.
    }
  }

  void _handleServerError(Object error, StackTrace stackTrace) {
    if (!_closed) Log.w('FFmpeg HLS relay server failed: $error\n$stackTrace');
  }
}
