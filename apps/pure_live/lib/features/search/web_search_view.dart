import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/in_app_web.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// A web search to open (3.x `WebSearchLaunchRequest`).
@immutable
final class WebSearchRequest {
  /// Creates the request.
  const new({required this.uri, required this.platform, this.keyword = ''});

  /// The search address.
  final Uri uri;

  /// The platform id.
  final String platform;

  /// The words searched (the title's second line); may be empty.
  final String keyword;

  /// The request in the route [arguments] (`{'url': …, 'platform': …}`,
  /// 3.x's form, and the search page's `'keyword'`), or null when they are
  /// not a plain http(s) address without user information and a platform
  /// (3.x `parseWebSearchLaunchRequest`).
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
    final keyword = arguments['keyword'];
    return WebSearchRequest(uri: uri, platform: platform, keyword: keyword is String ? keyword.trim() : '');
  }
}

/// The web search route (`RoutePath.kWebSearch`, docs/A-界面设计/A09-浏览界面/A09.8-网页搜索): the
/// platform's search page in the app (3.x `WebSearchPage`; [InAppWeb]),
/// shown as the desktop site like 3.x (c8). When a page shows a room, a bar
/// at the bottom names the platform and the room and opens it (c4; 3.x
/// asked in a dialog every time); the room opens over this page, so Back
/// returns here (c5).
///
/// The app bar: Back goes back in the page first and closes it on the first
/// page; the title says the platform and the words (c2); "use the system
/// browser" (c3) and ✕, which closes at once (3.x).
///
/// Without an in-app WebView (Linux, a Windows without WebView2) the page
/// sends the search to the system browser and says how to come back: copy
/// the room's link and paste it into the search field (c7).
class WebSearchView extends ConsumerStatefulWidget {
  /// Creates the page for the route [arguments].
  const new({required this.arguments, this.openExternal, this.inApp, this.openRoom, super.key});

  /// The route arguments.
  final Object? arguments;

  /// Opens a web address outside the app; null uses
  /// [AppNavigator.openExternal].
  final Future<bool> Function(Uri uri)? openExternal;

  /// Whether the page opens in the app; null reads [InAppWeb.available].
  final bool? inApp;

  /// Opens a room; null uses [AppNavigator.toLiveRoomDetail].
  final Future<void> Function(LiveRoom room)? openRoom;

  @override
  ConsumerState<WebSearchView> createState() => _WebSearchViewState();
}

class _WebSearchViewState extends ConsumerState<WebSearchView> {
  late final WebSearchRequest? _request = WebSearchRequest.parse(widget.arguments);
  late Uri? _current = _request?.uri;
  bool _opening = false;
  RoomLink? _found;
  final Set<RoomLink> _dismissed = {};
  int _page = 0;

  bool get _inApp => widget.inApp ?? InAppWeb.available;

  @override
  void initState() {
    super.initState();
    final request = _request;
    // No WebView here: the search goes to the system browser at once (3.x
    // opened it straight from the search page on Linux).
    if (request != null && !_inApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openExternal(request.uri));
      });
    }
  }

  /// A page was shown: the bar names its room, unless the user closed the
  /// bar for that room (c4, c1: a dismissed room is not offered again).
  Future<void> _pageShown(Uri uri) async {
    _current = uri;
    final page = ++_page;
    RoomLink? link;
    try {
      link = await LinkParser(ref.read(sitesProvider), ref.read(appServicesProvider).http).parse(uri.toString());
    } on Object {
      link = null;
    }
    if (!mounted || page != _page) return;
    setState(() => _found = link == null || _dismissed.contains(link) ? null : link);
  }

  Future<void> _enter(RoomLink link) async {
    final room = LiveRoom(platform: link.platform, roomId: link.roomId);
    final open = widget.openRoom;
    // Over this page: Back from the room comes back here (c5).
    await (open != null ? open(room) : AppNavigator.toLiveRoomDetail(liveRoom: room));
  }

  void _dismiss(RoomLink link) => setState(() {
    _dismissed.add(link);
    _found = null;
  });

  Future<void> _openExternal(Uri uri) async {
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

  String get _subtitle {
    final request = _request;
    if (request == null) return '';
    final name = platformName(request.platform, fallback: request.platform);
    return request.keyword.isEmpty
        ? name
        : i18n('web_search_subtitle', args: {'platform': name, 'keyword': request.keyword});
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final inApp = request != null && _inApp;
    return EscapeBack(
      // Esc is Back: in the page first (c1).
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 4,
          title: PageTitle(title: i18n('web_search'), subtitle: _subtitle),
          actions: [
            if (inApp)
              IconButton(
                key: const ValueKey('web-search-external'),
                tooltip: i18n('open_in_system_browser'),
                icon: const Icon(AppIcons.openExternal),
                onPressed: () => unawaited(_openExternal(_current ?? request.uri)),
              ),
            IconButton(
              key: const ValueKey('web-search-close'),
              tooltip: i18n('close'),
              icon: const Icon(AppIcons.close),
              // `pop`, past the page's own back steps (3.x's ✕).
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: request == null
            ? _invalid(context)
            : inApp
            ? LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: InAppWebPage(
                        initial: request.uri,
                        desktopSite: true,
                        progressHeight: 4,
                        onPage: (uri) => unawaited(_pageShown(uri)),
                        failureBuilder: _failure,
                      ),
                    ),
                    if (_found case final link?)
                      WebSearchRoomBar.place(
                        width: constraints.maxWidth,
                        bar: WebSearchRoomBar(
                          platform: link.platform,
                          roomId: link.roomId,
                          onEnter: () => unawaited(_enter(link)),
                          onDismiss: () => _dismiss(link),
                        ),
                      ),
                  ],
                ),
              )
            : _external(context, request),
      ),
    );
  }

  /// The page did not load (3.x; c6 adds the system browser).
  Widget _failure(BuildContext context, VoidCallback retry) =>
      WebSearchFailure(onRetry: retry, onOpenExternal: () => unawaited(_openExternal(_current ?? _request!.uri)));

  /// Bad route arguments (3.x).
  Widget _invalid(BuildContext context) => _StateBody(
    key: const ValueKey('web-search-invalid'),
    icon: AppIcons.networkError,
    error: true,
    title: i18n('web_search_error_title'),
    text: i18n('web_search_invalid_address'),
    actions: [
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(AppIcons.close, size: 18),
        label: Text(i18n('close')),
      ),
    ],
  );

  /// The system browser (c7): how to come back, the address, and the button
  /// (busy while the browser opens).
  Widget _external(BuildContext context, WebSearchRequest request) => _StateBody(
    key: const ValueKey('web-search-system-browser'),
    icon: AppIcons.webSearch,
    text: i18n('search_web_external_tip'),
    detail: request.uri.host,
    actions: [
      FilledButton.icon(
        key: const ValueKey('web-search-open-external'),
        onPressed: _opening ? null : () => unawaited(_openExternal(request.uri)),
        icon: _opening
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(AppIcons.openExternal, size: 18),
        label: Text(i18n('open_in_system_browser')),
      ),
    ],
  );
}

/// The bar of a room the web page shows (U.5b c4; 3.x asked in a dialog
/// every time): the platform's logo, "这是一个直播间", the platform and the
/// room id, "进入" and ✕ (this room is not offered again).
class WebSearchRoomBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.platform, required this.roomId, required this.onEnter, required this.onDismiss, super.key});

  /// The room's platform id.
  final String platform;

  /// The room id.
  final String roomId;

  /// Opens the room.
  final VoidCallback onEnter;

  /// Hides the bar for this room.
  final VoidCallback onDismiss;

  /// Places [bar] over a page [width] wide: the full width on phones held
  /// upright, on the right 420 wide on sideways phones and 440 on wide
  /// windows.
  static Widget place({required double width, required Widget bar}) {
    if (width < 600) return Positioned(left: 12, right: 12, bottom: 16, child: SafeArea(top: false, child: bar));
    final wide = width >= 1200;
    return Positioned(
      right: wide ? 24 : 12,
      bottom: wide ? 24 : 16,
      width: wide ? 440 : 420,
      child: SafeArea(top: false, left: false, child: bar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final name = platformName(platform, fallback: platform);
    return Material(
      key: const ValueKey('web-search-room-bar'),
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(7), child: PlatformLogo(platform)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(i18n('web_search_room_banner'), style: styles.t14SemiBold.copyWith(color: scheme.onSurface)),
                  Text(
                    i18n('room_menu_subtitle', args: {'platform': name, 'id': roomId}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.t12.copyWith(color: scheme.onSurfaceVariant).tabular,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const ValueKey('web-search-room-enter'),
              onPressed: onEnter,
              child: Text(i18n('search_room_enter')),
            ),
            IconButton(
              key: const ValueKey('web-search-room-dismiss'),
              tooltip: i18n('web_search_room_dismiss'),
              onPressed: onDismiss,
              icon: const Icon(AppIcons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web page did not load (3.x's failure page; U.5b c6 adds the system
/// browser under "retry").
class WebSearchFailure extends StatelessWidget {
  /// Creates the page.
  const new({required this.onRetry, required this.onOpenExternal, super.key});

  /// Loads the page again.
  final VoidCallback onRetry;

  /// Opens the page in the system browser.
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) => _StateBody(
    key: const ValueKey('web-search-failed'),
    icon: AppIcons.networkError,
    error: true,
    title: i18n('web_search_error_title'),
    text: i18n('web_search_load_failed'),
    actions: [
      FilledButton.icon(
        key: const ValueKey('web-search-retry'),
        onPressed: onRetry,
        icon: const Icon(AppIcons.retry, size: 18),
        label: Text(i18n('retry')),
      ),
      TextButton.icon(
        key: const ValueKey('web-search-failed-external'),
        onPressed: onOpenExternal,
        icon: const Icon(AppIcons.openExternal, size: 18),
        label: Text(i18n('open_in_system_browser')),
      ),
    ],
  );
}

/// A centred state of the page: a 48-point icon (error colour for
/// failures), a title, a sentence, a quiet detail and the buttons below.
class _StateBody extends StatelessWidget {
  const new({
    required this.icon,
    required this.text,
    required this.actions,
    this.title,
    this.detail,
    this.error = false,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String text;
  final String? detail;
  final bool error;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity)),
          child: Center(child: _content(scheme, styles)),
        ),
      ),
    );
  }

  Widget _content(ColorScheme scheme, AppTextStyles styles) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: error ? scheme.error : scheme.primary),
        if (title case final title?) ...[
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: styles.t15SemiBold.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: styles.t13.copyWith(color: scheme.onSurfaceVariant),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: styles.t14.copyWith(color: scheme.onSurface),
          ),
        ],
        if (detail case final detail?) ...[
          const SizedBox(height: 8),
          Text(detail, style: styles.t13.copyWith(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 20),
        for (final (index, action) in actions.indexed) ...[if (index > 0) const SizedBox(height: 8), action],
      ],
    ),
  );
}
