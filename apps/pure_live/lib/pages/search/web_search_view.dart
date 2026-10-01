import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// A web search to open (3.x `WebSearchLaunchRequest`).
@immutable
final class WebSearchRequest {
  /// Creates the request.
  const new({required this.uri, required this.platform});

  /// The search address.
  final Uri uri;

  /// The platform id.
  final String platform;

  /// The request in the route [arguments] (`{'url': …, 'platform': …}`,
  /// 3.x's form), or null when they are not a plain http(s) address
  /// without user information and a platform (3.x
  /// `parseWebSearchLaunchRequest`).
  static WebSearchRequest? parse(Object? arguments) {
    if (arguments is! Map) return null;
    final rawUrl = arguments['url'];
    final rawPlatform = arguments['platform'];
    if (rawUrl is! String || rawPlatform is! String) return null;
    final uri = Uri.tryParse(rawUrl.trim());
    final platform = rawPlatform.trim().toLowerCase();
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.trim().isEmpty ||
        uri.userInfo.isNotEmpty ||
        platform.isEmpty) {
      return null;
    }
    return WebSearchRequest(uri: uri, platform: platform);
  }
}

/// The web search route (`RoutePath.kWebSearch`): the platform's search
/// page opens in the system browser (3.x did this on Linux; its in-app
/// WebView needs a WebView plugin the app does not have yet). A room link
/// copied there and pasted into the search field opens the room.
class WebSearchView extends StatefulWidget {
  /// Creates the page for the route [arguments].
  const new({required this.arguments, this.openExternal, super.key});

  /// The route arguments.
  final Object? arguments;

  /// Opens a web address outside the app; null uses
  /// [AppNavigator.openExternal].
  final Future<bool> Function(Uri uri)? openExternal;

  @override
  State<WebSearchView> createState() => _WebSearchViewState();
}

class _WebSearchViewState extends State<WebSearchView> {
  late final WebSearchRequest? _request = WebSearchRequest.parse(widget.arguments);
  bool _opening = false;

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await (widget.openExternal ?? AppNavigator.openExternal)(uri);
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = _request;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('web_search'))),
      body: SingleChildScrollView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: request == null
                  ? [
                      Icon(Icons.link_off_rounded, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        i18n('web_search_invalid_address'),
                        key: const ValueKey('web-search-invalid'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(i18n('close')),
                      ),
                    ]
                  : [
                      Icon(Icons.open_in_browser_rounded, size: 48, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(i18n('search_web_external_tip'), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        request.uri.host,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('web-search-open-external'),
                        onPressed: _opening ? null : () => unawaited(_open(request.uri)),
                        icon: _opening
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.open_in_new_rounded),
                        label: Text(i18n('open_in_system_browser')),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
