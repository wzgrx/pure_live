import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_cast/src/failure.dart';
import 'package:meta/meta.dart';

/// An HTTP answer from a device.
@immutable
final class CastHttpResponse {
  /// Creates a response.
  const new(this.statusCode, this.body);

  /// HTTP status.
  final int statusCode;

  /// Body, decoded as UTF-8 (malformed bytes replaced).
  final String body;

  /// Whether the status is 2xx.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// HTTP to devices on the local network: device descriptions and SOAP
/// control. Tests replace it with a fake; the app shares one [IoCastHttp].
abstract interface class CastHttp {
  /// Sends one request. Throws [CastTimeoutFailure] when [timeout] passes
  /// before the whole body arrived, [CastNetworkFailure] when the connection
  /// fails and [CastProtocolFailure] for an oversized body. HTTP error
  /// statuses are returned, not thrown.
  Future<CastHttpResponse> send(
    String method,
    Uri url, {
    required Duration timeout,
    Map<String, String> headers = const {},
    String? body,
  });

  /// Releases connections; later requests fail.
  void close();
}

/// [CastHttp] on `dart:io`'s [HttpClient].
///
/// Always direct: a proxy cannot reach the local network. Header names keep
/// their case (`SOAPAction`) because some renderers compare them
/// case-sensitively. Connections are not reused: several embedded servers
/// mishandle keep-alive.
final class IoCastHttp implements CastHttp {
  /// Creates a client; bodies over [maxBody] bytes fail.
  new({this.maxBody = 512 * 1024, this.userAgent = 'PureLive/4 UPnP/1.1 DLNADOC/1.50'});

  /// Largest body read (descriptions and SOAP answers are a few KiB).
  final int maxBody;

  /// `User-Agent` sent with every request.
  final String userAgent;

  HttpClient? _client;
  bool _closed = false;

  HttpClient get _io => _client ??= HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..userAgent = userAgent;

  @override
  Future<CastHttpResponse> send(
    String method,
    Uri url, {
    required Duration timeout,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (_closed) throw const CastNetworkFailure('client closed');
    HttpClientRequest? request;
    Future<CastHttpResponse> exchange() async {
      final opened = request = await _io.openUrl(method, url)
        ..persistentConnection = false
        ..followRedirects = method == 'GET';
      headers.forEach((name, value) => opened.headers.set(name, value, preserveHeaderCase: true));
      if (body != null) {
        final bytes = utf8.encode(body);
        opened
          ..contentLength = bytes.length
          ..add(bytes);
      }
      final response = await opened.close();
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response) {
        buffer.add(chunk);
        if (buffer.length > maxBody) throw CastProtocolFailure('body over $maxBody bytes from ${url.host}');
      }
      return CastHttpResponse(response.statusCode, utf8.decode(buffer.takeBytes(), allowMalformed: true));
    }

    try {
      return await exchange().timeout(timeout);
    } on TimeoutException {
      request?.abort();
      throw CastTimeoutFailure(timeout, '$method ${url.host}:${url.port}');
    } on IOException catch (error) {
      // SocketException, HttpException, TlsException.
      throw CastNetworkFailure('$method ${url.host}:${url.port}: $error');
    } on CastFailure {
      request?.abort();
      rethrow;
    }
  }

  @override
  void close() {
    _closed = true;
    _client?.close(force: true);
    _client = null;
  }
}
