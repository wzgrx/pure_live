import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/in_app_web.dart';

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
/// page in the app (3.x `WebSearchPage`; [InAppWeb]), which offers to open
/// a room once the page shows one. Without an in-app WebView (Linux, a
/// Windows without WebView2) it opens in the system browser, and a room link
/// copied there and pasted into the search field opens the room.
class WebSearchView extends ConsumerStatefulWidget {
  /// Creates the page for the route [arguments].
  const new({required this.arguments, this.openExternal, super.key});

  /// The route arguments.
  final Object? arguments;

  /// Opens a web address outside the app; null uses
  /// [AppNavigator.openExternal].
  final Future<bool> Function(Uri uri)? openExternal;

  @override
  ConsumerState<WebSearchView> createState() => _WebSearchViewState();
}

class _WebSearchViewState extends ConsumerState<WebSearchView> {
  late final WebSearchRequest? _request = WebSearchRequest.parse(widget.arguments);
  bool _opening = false;
  final Set<RoomLink> _offered = {};
  bool _asking = false;

  /// A page that shows a room: asks once per room whether to open it (3.x).
  Future<void> _pageShown(Uri uri) async {
    if (_asking) return;
    final RoomLink? link;
    try {
      link = await LinkParser(ref.read(sitesProvider), ref.read(appServicesProvider).http).parse(uri.toString());
    } on Object {
      return;
    }
    if (link == null || !_offered.add(link) || !mounted) return;
    _asking = true;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('web_search_room_found')),
        content: Text(uri.toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
        ],
      ),
    );
    _asking = false;
    if (open != true || !mounted) return;
    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: link.platform, roomId: link.roomId),
    );
  }

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
    if (request != null && InAppWeb.available) {
      return Scaffold(
        appBar: AppBar(
          title: Text(i18n('web_search')),
          actions: [
            IconButton(
              tooltip: i18n('open_in_system_browser'),
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => unawaited(_open(request.uri)),
            ),
          ],
        ),
        body: InAppWebPage(initial: request.uri, onPage: (uri) => unawaited(_pageShown(uri))),
      );
    }
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
