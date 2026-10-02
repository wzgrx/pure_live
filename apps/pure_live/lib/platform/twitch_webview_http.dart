import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_net/live_net.dart';

/// Runs a script in a headless browser page (the transport's only contact
/// with flutter_inappwebview, so tests drive a fake).
abstract interface class HeadlessBrowser {
  /// Opens a blank page of [origin] behind [proxyRule] (`host:port`, or null
  /// for a direct connection), runs [script] (the body of an async
  /// function) there and answers its result. Throws when the page or the
  /// script fails, or after [timeout].
  Future<Object?> evaluate({required Uri origin, required String script, required Duration timeout, String? proxyRule});
}

/// Twitch's integrity token as `gql.twitch.tv/integrity` answers it.
@immutable
final class TwitchIntegrityToken {
  /// Creates the token.
  const new({required this.token, required this.expiresAt});

  /// The `Client-Integrity` value.
  final String token;

  /// When Twitch stops accepting it (`expiration`, epoch milliseconds).
  final DateTime expiresAt;
}

/// Twitch GraphQL sent from inside a headless WebView (3.x
/// `TwitchWebIntegrityProvider.postGraphQl`), the last of TwitchSite's
/// `gqlFallbacks` on Android (docs/T02/T02c/T02c.2/record.md, "GraphQL 传输的接口约定").
///
/// When dart:io and Android's system TLS are refused or asked for an
/// integrity token, the page's own `fetch` sends the request: Chromium's
/// TLS and headers pass Twitch's client check, and its Kasada SDK (KPSDK)
/// answers the integrity challenge. The page asks `/integrity` only when
/// Twitch requires it, then sends the request again with the token; the
/// transport keeps the token (per client and device id, until shortly
/// before it expires) and sends it with later requests.
///
/// - Only `POST https://gql.twitch.tv/gql` is accepted; anything else is a
///   [TransportReason.protocol] failure, so the page cannot be used as a
///   general request tool.
/// - Only `client-id` and `device-id` go into the page, as in 3.x: account
///   cookies and OAuth stay out of the browser session (a playback token
///   asked through here is anonymous).
/// - The answer is Twitch's status and body; a page or script failure, a
///   timeout ([LiveRequest.timeout]) or a second integrity refusal is a
///   [TransportFailure].
final class TwitchWebViewHttp implements LiveHttp {
  /// Creates the transport. [proxy] routes the page like the dart:io
  /// client; [browser] runs the page (by default flutter_inappwebview's
  /// headless WebView); [now] is the clock of the token cache.
  new({required this.proxy, HeadlessBrowser? browser, DateTime Function()? now})
    : browser = browser ?? InAppHeadlessBrowser(),
      _now = now ?? DateTime.now;

  /// Whether this transport is injected on the running platform (Android,
  /// as 3.x's last fallback there).
  static bool get isAvailable => Platform.isAndroid;

  /// The one endpoint served.
  static final Uri endpoint = Uri.parse('https://gql.twitch.tv/gql');

  /// The page the script runs in: a blank document of Twitch's origin (the
  /// KPSDK needs a real twitch.tv origin).
  static final Uri origin = Uri.parse('https://www.twitch.tv/twitch');

  /// Twitch's KPSDK bootstrap script (3.x `TwitchWebIntegrityProvider.scriptUrl`).
  static const String kpsdkScript =
      'https://k.twitchcdn.net/149e9513-01fa-4fb0-aad4-566afd725d1b/2d206a39-8ed7-437e-a3be-862e0f06eea3/p.js';

  /// How long before its expiry a kept token is no longer sent.
  static const Duration tokenMargin = Duration(minutes: 1);

  /// The app's proxy rules.
  final ProxyPolicy proxy;

  /// The headless browser.
  final HeadlessBrowser browser;

  final DateTime Function() _now;
  final Map<String, TwitchIntegrityToken> _tokens = {};

  /// The token kept for [clientId] and [deviceId], while it is still good.
  TwitchIntegrityToken? tokenFor(String clientId, String deviceId) {
    final token = _tokens[_key(clientId, deviceId)];
    return token != null && _now().isBefore(token.expiresAt.subtract(tokenMargin)) ? token : null;
  }

  static String _key(String clientId, String deviceId) => '$clientId\u0000$deviceId';

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final url = request.url;
    final site = request.site;
    if (url.scheme != 'https' ||
        url.host.toLowerCase() != endpoint.host ||
        url.path != endpoint.path ||
        request.method.toUpperCase() != 'POST') {
      throw TransportFailure(site, TransportReason.protocol, 'the Twitch WebView refuses ${request.method} $url');
    }
    final cancel = request.cancel;
    if (cancel?.isCancelled ?? false) throw TransportFailure(site, TransportReason.cancelled);
    final clientId = request.headers['client-id'] ?? '';
    final deviceId = request.headers['device-id'] ?? '';
    final script = graphQlScript(
      body: utf8.decode(request.body ?? const [], allowMalformed: true),
      clientId: clientId,
      deviceId: deviceId,
      integrityToken: tokenFor(clientId, deviceId)?.token,
    );
    final route = proxy.routeFor(site, url);
    final run = browser.evaluate(
      origin: origin,
      script: script,
      proxyRule: route is HttpProxyRoute ? '${route.host}:${route.port}' : null,
      timeout: request.timeout,
    );
    final Object? value;
    try {
      value = cancel == null
          ? await run
          : await Future.any([run, cancel.whenCancelled.then<Object?>((_) => throw const _Cancelled())]);
    } on _Cancelled {
      unawaited(run.then<void>((_) {}, onError: (Object _) {}));
      throw TransportFailure(site, TransportReason.cancelled);
    } on TimeoutException {
      throw TransportFailure(site, TransportReason.timeout, 'the Twitch WebView took too long');
    } on Object catch (error) {
      throw TransportFailure(site, TransportReason.connect, 'the Twitch WebView failed: $error');
    }
    final envelope = _envelope(value);
    if (envelope == null) throw TransportFailure(site, TransportReason.protocol, 'the Twitch WebView answered nothing');
    final integrity = envelope['integrity'];
    if (integrity is Map) {
      final token = '${integrity['token'] ?? ''}'.trim();
      final expiration = integrity['expiration'];
      if (token.isNotEmpty && expiration is num && expiration > 0) {
        _tokens[_key(clientId, deviceId)] = TwitchIntegrityToken(
          token: token,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiration.toInt(), isUtc: true),
        );
      }
    }
    final status = envelope['status'];
    final body = envelope['body'];
    if (status is! num || body is! String) {
      throw TransportFailure(site, TransportReason.protocol, 'the Twitch WebView answered no status or body');
    }
    return LiveResponse(status: status.toInt(), bytes: utf8.encode(body), url: url);
  }

  static Map<Object?, Object?>? _envelope(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
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

  /// The page script (3.x `buildGraphQlScript`): POST [body] to GraphQL
  /// with [integrityToken] when there is one; when Twitch answers with an
  /// integrity challenge, load the KPSDK, ask `/integrity` and send again
  /// with the new token. Its result is the JSON text
  /// `{status, body, integrity}` (`integrity` the new token or null); a
  /// second challenge throws.
  @visibleForTesting
  static String graphQlScript({
    required String body,
    required String clientId,
    required String deviceId,
    String? integrityToken,
  }) {
    final gqlHeaders = jsonEncode({
      'Accept': 'application/json',
      'Content-Type': 'text/plain;charset=UTF-8',
      'Client-ID': clientId,
      'Device-Id': deviceId,
    });
    final integrityHeaders = jsonEncode({'Client-ID': clientId, 'X-Device-Id': deviceId});
    return '''
const gqlHeaders = $gqlHeaders;
const requestBody = ${jsonEncode(body)};
const initialToken = ${jsonEncode(integrityToken?.trim() ?? '')};
const requestGraphQl = async token => {
  const headers = Object.assign({}, gqlHeaders);
  if (token) headers['Client-Integrity'] = token;
  const response = await window.fetch(${jsonEncode('$endpoint')}, {
    headers, body: requestBody, method: 'POST', mode: 'cors', credentials: 'omit'
  });
  return {status: response.status, body: await response.text()};
};
const failedIntegrity = body => {
  let decoded;
  try { decoded = JSON.parse(body); } catch (_) { return false; }
  const envelopes = Array.isArray(decoded) ? decoded : [decoded];
  return envelopes.some(envelope => envelope && Array.isArray(envelope.errors) && envelope.errors.some(error => {
    const message = String(error && error.message || '').toLowerCase();
    return message.includes('failed integrity check') || message.includes('integrity token');
  }));
};
let result = await requestGraphQl(initialToken);
let integrity = null;
if (failedIntegrity(result.body)) {
  integrity = await new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback, value) => { if (!settled) { settled = true; clearTimeout(timer); callback(value); } };
    const timer = setTimeout(() => finish(reject, 'Twitch KPSDK readiness timed out'), 20000);
    document.addEventListener('kpsdk-load', () => window.KPSDK.configure([{
      protocol: 'https:', method: 'POST', domain: 'gql.twitch.tv', path: '/integrity'
    }]), {once: true});
    document.addEventListener('kpsdk-ready', () => {
      window.fetch('https://gql.twitch.tv/integrity', {
        headers: $integrityHeaders, body: null, method: 'POST', mode: 'cors', credentials: 'omit'
      }).then(async response => {
        const text = await response.text();
        if (response.status !== 200) throw new Error('Twitch integrity status ' + response.status);
        finish(resolve, JSON.parse(text));
      }).catch(error => finish(reject, String(error)));
    }, {once: true});
    const script = document.createElement('script');
    script.addEventListener('error', () => finish(reject, 'Twitch KPSDK script failed to load'));
    script.src = ${jsonEncode(kpsdkScript)};
    document.body.appendChild(script);
  });
  if (!integrity || typeof integrity.token !== 'string' || !integrity.token) {
    throw new Error('Twitch integrity endpoint returned an incomplete token');
  }
  result = await requestGraphQl(integrity.token);
  if (failedIntegrity(result.body)) throw new Error('Twitch GraphQL still failed integrity validation');
}
return JSON.stringify({status: result.status, body: result.body, integrity});
''';
  }
}

final class _Cancelled implements Exception {
  const new();
}

/// flutter_inappwebview's headless WebView as a [HeadlessBrowser] (3.x
/// `_evaluateExclusive` and `WebViewProxyScope`).
///
/// One page at a time: Android's WebView proxy override is process-global,
/// so a page's proxy is set before it loads and cleared after it closes,
/// never while another page runs. On Android the page navigates to the real
/// origin and only its main document is answered with a blank page (some
/// WebView builds keep a synthetic origin for `loadDataWithBaseURL`, and
/// the KPSDK then never becomes ready); the WebView's own User-Agent is
/// kept, so it matches its TLS fingerprint.
final class InAppHeadlessBrowser implements HeadlessBrowser {
  /// Creates the browser.
  new();

  static Future<void> _tail = Future<void>.value();

  @override
  Future<Object?> evaluate({
    required Uri origin,
    required String script,
    required Duration timeout,
    String? proxyRule,
  }) async {
    final predecessor = _tail;
    final release = Completer<void>();
    _tail = release.future;
    try {
      await predecessor;
      return await _withProxy(proxyRule, () => _run(origin, script).timeout(timeout));
    } finally {
      release.complete();
    }
  }

  static Future<T> _withProxy<T>(String? rule, Future<T> Function() body) async {
    if (rule == null || !Platform.isAndroid) return await body();
    final controller = ProxyController.instance();
    var overridden = false;
    try {
      if (await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
        await controller.setProxyOverride(
          settings: ProxySettings(proxyRules: [ProxyRule(url: rule)]),
        );
        overridden = true;
      }
      return await body();
    } finally {
      if (overridden) {
        try {
          await controller.clearProxyOverride();
        } on PlatformException {
          // The next override replaces it anyway.
        }
      }
    }
  }

  static Future<Object?> _run(Uri origin, String script) async {
    final created = Completer<InAppWebViewController>();
    final loaded = Completer<void>();
    final page = WebUri.uri(origin);
    final android = Platform.isAndroid;
    final view = HeadlessInAppWebView(
      initialUrlRequest: android ? URLRequest(url: page) : null,
      initialData: android
          ? null
          : InAppWebViewInitialData(
              data: '<!doctype html><html><head></head><body></body></html>',
              baseUrl: page,
              historyUrl: page,
            ),
      initialSettings: InAppWebViewSettings(transparentBackground: true),
      shouldInterceptRequest: android
          ? (controller, request) async {
              if (request.isForMainFrame != true || request.url.host != origin.host) return null;
              return WebResourceResponse(
                contentType: 'text/html',
                data: Uint8List.fromList(utf8.encode('<!doctype html><html><head></head><body></body></html>')),
                headers: const {'Cache-Control': 'no-store'},
                statusCode: 200,
                reasonPhrase: 'OK',
              );
            }
          : null,
      onWebViewCreated: (controller) {
        if (!created.isCompleted) created.complete(controller);
      },
      onLoadStop: (controller, url) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    try {
      await view.run();
      final controller = await created.future;
      await loaded.future;
      final result = await controller.callAsyncJavaScript(functionBody: script);
      if (result == null || result.error != null) {
        throw StateError('Twitch WebView script failed: ${result?.error ?? 'no result'}');
      }
      return result.value;
    } finally {
      if (view.isRunning()) await view.dispose();
    }
  }
}
