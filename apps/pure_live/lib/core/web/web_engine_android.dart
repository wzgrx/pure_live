import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv;

/// Android System WebView through webview_flutter (BSD-3-Clause; ADR
/// draft-webview). The WebView ships with the system, so it is always there.
final class AndroidWebEngine implements WebEngine {
  @override
  Future<WebAvailability> availability() async => WebAvailability.available;

  @override
  WebPage open({WebNavigationFilter? filter, String? userAgent}) => _AndroidWebPage(filter, userAgent);

  @override
  Future<List<WebCookie>> cookies(Uri url) async => [
    // webview_flutter_android 4.14.1 splits each pair at every `=` and keeps
    // the first and last part, so a value holding `=` arrives shortened
    // (ADR draft-webview, known limits); the platforms signed in here (B 站)
    // have no such values.
    for (final cookie in await wv.WebViewCookieManager().getCookies(domain: url))
      WebCookie(name: cookie.name, value: cookie.value),
  ];

  @override
  Future<void> clearCookies() => wv.WebViewCookieManager().clearCookies();
}

final class _AndroidWebPage implements WebPage {
  new(WebNavigationFilter? filter, String? userAgent) {
    unawaited(_controller.setJavaScriptMode(wv.JavaScriptMode.unrestricted));
    if (userAgent != null) unawaited(_controller.setUserAgent(userAgent));
    unawaited(
      _controller.setNavigationDelegate(
        wv.NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = Uri.tryParse(request.url);
            if (url == null || !isWebAddress(url)) return wv.NavigationDecision.prevent;
            if (!request.isMainFrame || filter == null) return wv.NavigationDecision.navigate;
            return await filter(url) ? wv.NavigationDecision.navigate : wv.NavigationDecision.prevent;
          },
          onPageStarted: (url) => _emit(url, WebPageStarted.new),
          onPageFinished: (url) => _emit(url, WebPageFinished.new),
          onUrlChange: (change) => _emit(change.url, WebUrlChanged.new),
          onProgress: (percent) => _add(WebPageProgress(percent)),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) _add(WebPageFailed(error.description));
          },
        ),
      ),
    );
  }

  final wv.WebViewController _controller = wv.WebViewController();
  final StreamController<WebPageEvent> _events = StreamController<WebPageEvent>.broadcast();

  void _add(WebPageEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _emit(String? url, WebPageEvent Function(Uri url) event) {
    final parsed = url == null ? null : Uri.tryParse(url);
    if (parsed != null) _add(event(parsed));
  }

  @override
  Stream<WebPageEvent> get events => _events.stream;

  @override
  Future<void> load(Uri url) => _controller.loadRequest(url);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<bool> goBack() async {
    if (!await _controller.canGoBack()) return false;
    await _controller.goBack();
    return true;
  }

  @override
  Future<Uri?> currentUrl() async {
    final url = await _controller.currentUrl();
    return url == null ? null : Uri.tryParse(url);
  }

  @override
  Future<Object?> evaluate(String script) => _controller.runJavaScriptReturningResult(script);

  @override
  Widget build(BuildContext context) => wv.WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() => _events.close();
}
