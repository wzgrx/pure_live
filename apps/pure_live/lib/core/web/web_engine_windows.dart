import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart' as wpi;

/// Microsoft Edge WebView2 through webview_all_windows (MIT; ADR
/// ADR 0032). The runtime is a system component: Windows 11 ships it,
/// older Windows 10 may not, and then entries explain how to install it.
final class WindowsWebEngine implements WebEngine {
  Future<void>? _environment;

  /// One WebView2 environment per run, with its profile under the app's data
  /// folder (the default next to the executable is not writable in every
  /// install location).
  Future<void> _ready() => _environment ??= () async {
    final root = await getApplicationSupportDirectory();
    await WindowsWebViewController.ensureEnvironment(userDataPath: '${root.path}${Platform.pathSeparator}WebView2');
  }();

  @override
  Future<WebAvailability> availability() async {
    final version = await WindowsWebViewController.getWebViewVersion();
    return version == null || version.isEmpty ? WebAvailability.missingRuntime : WebAvailability.available;
  }

  @override
  WebPage open({WebNavigationFilter? filter, String? userAgent}) => _WindowsWebPage(_ready(), filter, userAgent);

  @override
  Future<List<WebCookie>> cookies(Uri url) async {
    await _ready();
    final cookies = await WindowsWebViewCookieManager(const WindowsWebViewCookieManagerCreationParams())
        .getWindowsCookies(url);
    return [for (final cookie in cookies) WebCookie(name: cookie.name, value: cookie.value)];
  }

  @override
  Future<void> clearCookies() async {
    await _ready();
    await WindowsWebViewCookieManager(const WindowsWebViewCookieManagerCreationParams()).clearCookies();
  }
}

final class _WindowsWebPage implements WebPage {
  new(Future<void> environment, WebNavigationFilter? filter, String? userAgent) {
    _setup = () async {
      await environment;
      final controller = WindowsWebViewController(const WindowsWebViewControllerCreationParams());
      final delegate = WindowsNavigationDelegate(const WindowsNavigationDelegateCreationParams());
      await delegate.setOnNavigationRequest((request) async {
        final url = Uri.tryParse(request.url);
        if (url == null || !isWebAddress(url)) return wpi.NavigationDecision.prevent;
        if (!request.isMainFrame || filter == null) return wpi.NavigationDecision.navigate;
        return await filter(url) ? wpi.NavigationDecision.navigate : wpi.NavigationDecision.prevent;
      });
      await delegate.setOnPageStarted((url) => _emit(url, WebPageStarted.new));
      await delegate.setOnPageFinished((url) => _emit(url, WebPageFinished.new));
      await delegate.setOnUrlChange((change) => _emit(change.url, WebUrlChanged.new));
      await delegate.setOnProgress((percent) => _add(WebPageProgress(percent)));
      await delegate.setOnWebResourceError((error) {
        if (error.isForMainFrame ?? true) _add(WebPageFailed(error.description));
      });
      await controller.setPlatformNavigationDelegate(delegate);
      await controller.setJavaScriptMode(wpi.JavaScriptMode.unrestricted);
      if (userAgent != null) await controller.setUserAgent(userAgent);
      return controller;
    }();
  }

  late final Future<WindowsWebViewController> _setup;
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
  Future<void> load(Uri url) async {
    await (await _setup).loadRequest(wpi.LoadRequestParams(uri: url));
  }

  @override
  Future<void> reload() async {
    await (await _setup).reload();
  }

  @override
  Future<bool> goBack() async {
    final controller = await _setup;
    if (!await controller.canGoBack()) return false;
    await controller.goBack();
    return true;
  }

  @override
  Future<Uri?> currentUrl() async {
    final url = await (await _setup).currentUrl();
    return url == null ? null : Uri.tryParse(url);
  }

  @override
  Future<Object?> evaluate(String script) async => await (await _setup).runJavaScriptReturningResult(script);

  @override
  Widget build(BuildContext context) => FutureBuilder<WindowsWebViewController>(
    future: _setup,
    builder: (context, snapshot) {
      final controller = snapshot.data;
      if (controller == null) return const SizedBox.expand();
      return WindowsWebViewWidget(WindowsWebViewWidgetCreationParams(controller: controller)).build(context);
    },
  );

  @override
  Future<void> dispose() async {
    await _events.close();
    try {
      await (await _setup).dispose();
    } on Object {
      // Setup failed (no runtime): nothing to release.
    }
  }
}
