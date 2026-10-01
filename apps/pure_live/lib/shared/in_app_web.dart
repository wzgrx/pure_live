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

/// The User-Agent of a desktop browser (3.x `WebSearchController
/// .getDynamicUserAgent`): the web search shows the platforms' desktop
/// sites on phones too, which do not push their apps and whose room links
/// the app reads (docs/ui/compare/U.5b c8).
const String desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

/// A web page in the app (3.x `WebSearchPage`'s and the web login's view):
/// only http(s) navigation, untrusted certificates refused, the back key
/// goes back in the page first, a progress line while loading and the
/// failure in words.
class InAppWebPage extends StatefulWidget {
  /// Creates the view of [initial].
  const new({
    required this.initial,
    this.userAgent,
    this.onPage,
    this.onCreated,
    this.desktopSite = false,
    this.failureBuilder,
    this.progressHeight = 2,
    super.key,
  });

  /// The first address.
  final Uri initial;

  /// The User-Agent; null keeps the WebView's own ([desktopSite] sets
  /// [desktopUserAgent]).
  final String? userAgent;

  /// Called with every address the page shows (after redirects).
  final void Function(Uri uri)? onPage;

  /// Gets the controller once the view exists.
  final void Function(InAppWebViewController controller)? onCreated;

  /// Shows the desktop site laid out at its width and zoomable, with every
  /// navigation checked (3.x's web search settings).
  final bool desktopSite;

  /// What covers the page when it failed to load; `retry` loads it again.
  /// Null shows the reason and "retry".
  final Widget Function(BuildContext context, VoidCallback retry)? failureBuilder;

  /// The height of the progress line.
  final double progressHeight;

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _failed = false;

  Future<void> _back(Object? result) async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      // `pop`, not `maybePop`: this page's PopScope refuses `maybePop` and
      // would call this again without end.
      Navigator.of(context).pop(result);
    }
  }

  void _retry() => unawaited(_controller?.reload());

  InAppWebViewSettings get _settings => widget.desktopSite
      // 3.x's wide viewport, overview and zoom are the WebView's defaults.
      ? InAppWebViewSettings(userAgent: widget.userAgent ?? desktopUserAgent, useShouldOverrideUrlLoading: true)
      // No pop-up windows, no autoplay (the defaults).
      : InAppWebViewSettings(userAgent: widget.userAgent ?? '');

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_back(result));
    },
    child: Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(widget.initial)),
          initialSettings: _settings,
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
        if (_progress < 1)
          LinearProgressIndicator(
            key: const ValueKey('in-app-web-progress'),
            value: _progress == 0 ? null : _progress,
            minHeight: widget.progressHeight,
          ),
        if (_failed)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child:
                  widget.failureBuilder?.call(context, _retry) ??
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(i18n('web_search_load_failed'), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _retry, child: Text(i18n('retry'))),
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
