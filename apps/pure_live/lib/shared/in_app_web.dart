import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The in-app browser (flutter_inappwebview, 3.x's WebView): web search and
/// the Bilibili web login use it where it exists, else the system browser
/// and the cookie page.
abstract final class InAppWeb {
  /// Whether pages can open web content in the app; the app sets it
  /// (M12.3: Android always, Windows when the WebView2 runtime is
  /// installed); false in tests and on Linux.
  static bool available = false;

  /// Finds out whether this device has a usable WebView.
  static Future<bool> detect() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return true;
    if (!Platform.isWindows) return false;
    try {
      return await WebViewEnvironment.getAvailableVersion() != null;
    } on Object {
      return false;
    }
  }
}

/// Whether [uri] may be loaded inside the app: web pages only (3.x refused
/// app schemes, files and JavaScript URLs).
bool isWebPage(Uri? uri) => uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

/// A web page in the app (3.x `WebSearchPage`'s and the web login's view):
/// only http(s) navigation, untrusted certificates refused, the back key
/// goes back in the page first, a progress line while loading and the
/// failure in words.
class InAppWebPage extends StatefulWidget {
  /// Creates the view of [initial].
  const new({required this.initial, this.userAgent, this.onPage, this.onCreated, super.key});

  /// The first address.
  final Uri initial;

  /// The User-Agent; null keeps the WebView's own.
  final String? userAgent;

  /// Called with every address the page shows (after redirects).
  final void Function(Uri uri)? onPage;

  /// Gets the controller once the view exists.
  final void Function(InAppWebViewController controller)? onCreated;

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _failed = false;

  Future<void> _back() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(widget.initial)),
          // No pop-up windows, no autoplay (the defaults).
          initialSettings: InAppWebViewSettings(userAgent: widget.userAgent ?? ''),
          onWebViewCreated: (controller) {
            _controller = controller;
            widget.onCreated?.call(controller);
          },
          shouldOverrideUrlLoading: (controller, action) async =>
              isWebPage(action.request.url?.uriValue) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL,
          onReceivedServerTrustAuthRequest: (controller, challenge) async =>
              ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
          onProgressChanged: (controller, progress) {
            if (mounted) setState(() => _progress = progress / 100);
          },
          onLoadStart: (controller, url) {
            if (mounted && _failed) setState(() => _failed = false);
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame ?? false) {
              if (mounted) setState(() => _failed = true);
            }
          },
          onUpdateVisitedHistory: (controller, url, isReload) {
            final uri = url?.uriValue;
            if (uri != null) widget.onPage?.call(uri);
          },
        ),
        if (_progress < 1) LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 2),
        if (_failed)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(i18n('web_search_load_failed'), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => unawaited(_controller?.reload()), child: Text(i18n('retry'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
