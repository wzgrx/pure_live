import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:live_net/live_net.dart';

/// HTTPS through Android's own TLS stack (`AppChannelsPlugin.kt`, channel
/// `pure_live/native_http`).
///
/// Some proxies reset dart:io's TLS connection after CONNECT (Twitch
/// GraphQL, 3.x `android_native_http.dart`), and Cloudflare refuses
/// dart:io's TLS fingerprint (Kick, UPGRADES X-1). The native side only
/// reaches [allowedHosts] over https and answers at most 8 MiB, so the
/// channel cannot be turned into a general request tool. Twitch gets it as a
/// GraphQL fallback; Kick adds its hosts on both sides when it returns.
final class AndroidNativeHttp implements LiveHttp {
  /// Creates the transport; [proxy] routes each request like the dart:io
  /// client does.
  new({required this.proxy, this.channel = const MethodChannel('pure_live/native_http')});

  /// Hosts the native side serves (keep in step with `NativeHttpChannel.ALLOWED_HOSTS`).
  static const Set<String> allowedHosts = {'gql.twitch.tv'};

  /// Whether this transport exists on the running platform.
  static bool get isAvailable => Platform.isAndroid;

  /// The app's proxy rules.
  final ProxyPolicy proxy;

  /// The native channel.
  final MethodChannel channel;

  /// Whether [url] may go through the channel.
  static bool allows(Uri url) => url.scheme == 'https' && allowedHosts.contains(url.host.toLowerCase());

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final url = request.url;
    if (!allows(url)) throw TransportFailure(request.site, TransportReason.protocol, 'native HTTP refuses $url');
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    final route = proxy.routeFor(request.site, url);
    final call = channel.invokeMapMethod<String, Object?>('send', {
      'url': url.toString(),
      'method': request.method,
      'headers': request.headers,
      if (request.body != null) 'body': Uint8List.fromList(request.body!),
      'timeoutMillis': request.timeout.inMilliseconds,
      if (route is HttpProxyRoute) 'proxyHost': route.host,
      if (route is HttpProxyRoute) 'proxyPort': route.port,
    });
    final Map<String, Object?>? answer;
    try {
      final cancel = request.cancel;
      answer = cancel == null
          ? await call
          : await Future.any([call, cancel.whenCancelled.then<Map<String, Object?>?>((_) => null)]);
    } on PlatformException catch (error) {
      throw TransportFailure(request.site, TransportReason.connect, error.message);
    } on MissingPluginException {
      throw TransportFailure(request.site, TransportReason.protocol, 'native HTTP is not available');
    }
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    return decodeNativeAnswer(request.site, url, answer);
  }

  /// The response in the channel's [answer] (`status`, `headers`, `body`).
  static LiveResponse decodeNativeAnswer(String site, Uri url, Map<Object?, Object?>? answer) {
    final status = answer?['status'];
    if (status is! num) throw TransportFailure(site, TransportReason.protocol, 'native HTTP answered nothing');
    final body = answer?['body'];
    final headers = <String, List<String>>{};
    final rawHeaders = answer?['headers'];
    if (rawHeaders is Map) {
      for (final MapEntry(:key, :value) in rawHeaders.entries) {
        if (key is String && value is List) headers[key.toLowerCase()] = [for (final item in value) '$item'];
      }
    }
    return LiveResponse(status: status.toInt(), bytes: body is Uint8List ? body : const [], url: url, headers: headers);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      body: Stream.value(response.bytes),
      url: response.url,
      headers: response.headers,
      contentLength: response.bytes.length,
    );
  }

  @override
  void close() {}
}
