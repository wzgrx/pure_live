import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/search/search_capability.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/features/search/search_scope.dart';
import 'package:pure_live/features/search/search_widgets.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Where the WebView2 runtime is downloaded (3.x).
final Uri webView2DownloadPage = Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/');

/// The search page (3.x `SearchPage` with `SearchController`,
/// docs/T07/T07f/T07f.2): a search field that also takes room links, the
/// platform row, the filters, rooms or streamers from every platform as
/// they answer, paging, recent searches.
///
/// Narrow pages keep 3.x's order (field, platforms, filters); from
/// [searchOneRowWidth] the field (at most [searchFieldMaxWidth]) and the
/// platforms share the top line and the filters and the scope line the
/// next (c12, c13). Scrolling down slides away what is under the field
/// (narrow) or the filters (wide); scrolling up brings it back (X1 A).
class SearchView extends ConsumerStatefulWidget {
  /// Creates the page; [initialKeyword] is searched at once.
  const new({
    this.initialKeyword,
    this.openRoom,
    this.openExternal,
    this.openWebSearch,
    this.webView2Missing,
    this.timeout = searchRequestTimeout,
    super.key,
  });

  /// Words to search when the page opens.
  final String? initialKeyword;

  /// Opens a room; null uses [AppNavigator.toLiveRoomDetail].
  final void Function(LiveRoom room)? openRoom;

  /// Opens a web address outside the app; null uses
  /// [AppNavigator.openExternal].
  final Future<bool> Function(Uri uri)? openExternal;

  /// Opens the web search route with its arguments; null navigates to
  /// `RoutePath.kWebSearch`.
  final Future<void> Function(Map<String, String> arguments)? openWebSearch;

  /// Whether this is a Windows without the WebView2 runtime; null works it
  /// out ([Platform.isWindows] and not [InAppWeb.available]).
  final bool? webView2Missing;

  /// How long one platform may take for one page.
  final Duration timeout;

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  late final LiveStore _store;
  late final SearchModel _model;
  late final SearchHistory _history;
  late final SearchScopeStore _scope;
  late final Future<void> _scopeLoaded;
  late final LinkParser _links;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = createPureLiveScrollController();
  final List<StreamSubscription<Object>> _subscriptions = [];
  bool _preferRealOnline = false;
  Set<String> _realOnline = const {};
  bool _linkDetected = false;
  bool _resolvingLink = false;
  CancelToken? _linkCancel;
  List<String>? _dismissedFailures;
  bool _failureDetails = false;
  bool _webView2Asking = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(storeProvider);
    final registry = ref.read(sitesProvider);
    final settings = _store.settings;
    _preferRealOnline = settings.get(Settings.preferRealOnlineCounts);
    _realOnline = settings.get(Settings.realOnlinePlatforms).toSet();
    _model = SearchModel(
      // One snapshot of the user's platform list for the page's lifetime,
      // so the chips, the chosen index and paging stay together (3.x).
      sites: [for (final id in registry.availableIds(settings.get(Settings.hotAreasList))) registry.of(id)],
      audienceCompare: (left, right) => LiveRoom.compareAudienceRanking(
        left,
        right,
        preferRealOnline: _preferRealOnline,
        platformEnabled: _realOnline.contains,
      ),
      timeout: widget.timeout,
    )..addListener(_changed);
    _history = SearchHistory(_store.meta)..addListener(_changed);
    unawaited(_history.load());
    // The platforms left out of "all" (M13.16), read before the first search.
    _scope = SearchScopeStore(_store.meta);
    _scopeLoaded = _scope.load().then((excluded) {
      if (mounted) _model.setExcluded(excluded);
    });
    _links = LinkParser(registry, ref.read(appServicesProvider).http);
    _text.addListener(_textChanged);
    _scroll.addListener(_scrolled);
    _subscriptions
      ..add(
        settings.watch(Settings.preferRealOnlineCounts).listen((value) {
          _preferRealOnline = value;
          _model.reorder();
        }),
      )
      ..add(
        settings.watch(Settings.realOnlinePlatforms).listen((value) {
          _realOnline = value.toSet();
          _model.reorder();
        }),
      );
    final initial = widget.initialKeyword?.trim() ?? '';
    if (initial.isNotEmpty) {
      _text.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_submit());
      });
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _linkCancel?.cancel();
    _model
      ..removeListener(_changed)
      ..dispose();
    _history
      ..removeListener(_changed)
      ..dispose();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _textChanged() {
    final text = _text.text.trim();
    final detected = text.isNotEmpty && _links.containsSupportedLink(text);
    // The clear and paste buttons follow the text too.
    if (mounted) setState(() => _linkDetected = detected);
  }

  void _scrolled() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 480) return;
    unawaited(_model.loadMore());
  }

  void _toast(String message) => AppNavigator.toast(message);

  /// Opens [room]; [playlist] is the list it was picked from (U.2b2).
  void _openRoom(LiveRoom room, {List<LiveRoom> playlist = const []}) {
    final open = widget.openRoom;
    if (open != null) {
      open(room);
    } else {
      unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room, playlist: playlist));
    }
  }

  String _siteName(String platform) {
    final site = ref.read(sitesProvider).maybeOf(platform);
    return platformName(platform, fallback: site?.name ?? platform);
  }

  /// Searches the field's words; a room link opens the room instead.
  Future<void> _submit([String? word]) async {
    if (word != null) {
      _text.value = TextEditingValue(
        text: word,
        selection: TextSelection.collapsed(offset: word.length),
      );
    }
    final text = _text.text.trim();
    if (text.isEmpty) {
      _toast(i18n('please_input_keyword'));
      return;
    }
    _focus.unfocus();
    if (_linkDetected) {
      if (await _openLink(text) || !mounted) return;
    } else if (SiteIds.isRetiredLink(text)) {
      _toast(i18n('platform_retired'));
      return;
    }
    unawaited(_history.add(text));
    _dismissedFailures = null;
    _failureDetails = false;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _scopeLoaded;
    if (!mounted) return;
    await _model.search(text);
  }

  /// Opens the scope panel; a changed choice is remembered and "all" is
  /// searched again (c6).
  Future<void> _openScope() async {
    final excluded = await showSearchScopePanel(context, sites: _model.sites, excluded: _model.excluded);
    if (!mounted || setEquals(excluded, _model.excluded)) return;
    unawaited(_scope.save(excluded));
    _dismissedFailures = null;
    _failureDetails = false;
    _model.setExcluded(excluded, draft: _text.text);
  }

  /// Opens the room [text] links to; false when no room was found (the
  /// words are then searched, adapters understand some links themselves).
  Future<bool> _openLink(String text) async {
    _linkCancel?.cancel();
    final cancel = _linkCancel = CancelToken();
    setState(() => _resolvingLink = true);
    RoomLink? link;
    try {
      link = await _links.parse(text, cancel: cancel);
    } on Object {
      link = null;
    }
    if (!mounted || cancel.isCancelled) return true;
    setState(() => _resolvingLink = false);
    if (link == null) {
      _toast(i18n('search_link_not_found'));
      return false;
    }
    _openRoom(LiveRoom(platform: link.platform, roomId: link.roomId));
    return true;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _toast(i18n('search_clipboard_empty'));
      return;
    }
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The chosen platform's web search (3.x `openWebSearch`; U.5b): in the
  /// app where a WebView exists; on a Windows without WebView2 the dialog
  /// first (c15, X4 A); elsewhere (Linux) the page that sends it to the
  /// system browser.
  Future<void> _openWebSearch() async {
    final site = _model.selectedSite;
    if (site == null) {
      _toast(i18n('select_platform_for_web_search'));
      return;
    }
    final name = _siteName(site.id);
    final text = _text.text.trim();
    if (text.isEmpty) {
      _toast(i18n('please_input_keyword'));
      return;
    }
    final uri = webSearchUrl(site.id, text);
    if (uri == null) {
      _toast(i18n('search_web_unavailable', args: {'site': name}));
      return;
    }
    final arguments = {'url': uri.toString(), 'platform': site.id, 'keyword': text};
    if (widget.webView2Missing ?? (Platform.isWindows && !InAppWeb.available)) {
      if (!await _askWithoutWebView2() || !mounted) return;
    }
    final open = widget.openWebSearch;
    if (open != null) {
      await open(arguments);
    } else {
      await AppNavigator.toNamed<void>(RoutePath.kWebSearch, arguments: arguments);
    }
  }

  /// Windows without WebView2 (3.x asked on every visit of the page; c15):
  /// cancel, the download page, or the system browser (true).
  Future<bool> _askWithoutWebView2() async {
    if (_webView2Asking) return false;
    _webView2Asking = true;
    final String? choice;
    try {
      choice = await showAppDialog<String>(
        context: context,
        builder: (dialogContext) => AppDialog(
          key: const ValueKey('webview2-dialog'),
          title: i18n('webview2_missing_title'),
          icon: AppIcons.componentMissing,
          message: i18n('webview2_missing_web_search'),
          actions: [
            const DialogCancelButton(),
            TextButton(
              key: const ValueKey('webview2-download'),
              onPressed: () => Navigator.pop(dialogContext, 'download'),
              child: Text(i18n('webview2_open_download')),
            ),
            DialogActionButton(
              key: const ValueKey('webview2-browser'),
              label: i18n('webview2_use_system_browser'),
              onPressed: () => Navigator.pop(dialogContext, 'browser'),
            ),
          ],
        ),
      );
    } finally {
      _webView2Asking = false;
    }
    if (choice == 'download') {
      var opened = false;
      try {
        opened = await (widget.openExternal ?? AppNavigator.openExternal)(webView2DownloadPage);
      } on Object {
        opened = false;
      }
      if (!opened) _toast(i18n('webview2_open_error'));
    }
    return choice == 'browser';
  }

  void _retry() {
    _dismissedFailures = null;
    unawaited(_model.search(_model.keyword));
  }

  void _selectPlatform(int index) {
    _dismissedFailures = null;
    _model.select(index, draft: _text.text);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final scheme = Theme.of(context).colorScheme;
    return EscapeBack(
      // Esc leaves the page like Back (c1); a Scaffold keeps DismissIntent for drawers.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final oneRow = width >= searchOneRowWidth;
          final strip = SearchPlatformStrip(
            sites: _model.sites,
            selected: _model.selected,
            onSelected: _selectPlatform,
          );
          final options = SearchOptionsBar(
            model: _model,
            oneLine: oneRow,
            onModeChanged: (mode) {
              _dismissedFailures = null;
              _model.setMode(mode, draft: _text.text);
            },
            onOpenWebSearch: () => unawaited(_openWebSearch()),
            onOpenScope: () => unawaited(_openScope()),
          );
          final geometry = RoomGridGeometry.of(
            context,
            width: width,
            spacing: spacing,
            appearance: appearance,
            fontSizes: fontSizes,
          );
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: oneRow
                  ? Row(
                      children: [
                        const SizedBox(width: 16),
                        SizedBox(
                          width: math.min(searchFieldMaxWidth, math.max(280, width * 0.38)),
                          child: _field(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: strip),
                      ],
                    )
                  : Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _field(context)),
            ),
            body: CustomScrollView(
              key: const ValueKey('search-content'),
              controller: _scroll,
              physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverFloatingHeader(
                  animationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 200),
                    reverseDuration: Duration(milliseconds: 150),
                  ),
                  child: oneRow
                      ? options
                      : ColoredBox(
                          color: scheme.surface,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [strip, options]),
                        ),
                ),
                if (_linkDetected)
                  SliverToBoxAdapter(
                    child: SearchLinkBanner(resolving: _resolvingLink, onOpen: () => unawaited(_submit())),
                  ),
                if (_model.pending > 0) SliverToBoxAdapter(child: SearchPendingRow(count: _model.pending)),
                ..._content(context, geometry, spacing, mainSpacing),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final empty = _text.text.isEmpty;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      // Round when focused too (c2; 3.x's theme turned it square).
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      key: const ValueKey('search-field'),
      controller: _text,
      focusNode: _focus,
      autofocus: widget.initialKeyword == null,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => unawaited(_submit()),
      style: styles.t14,
      decoration: InputDecoration(
        hintText: i18n('search_hint'),
        hintStyle: styles.t14.copyWith(color: scheme.onSurfaceVariant),
        hintMaxLines: 1,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: border(scheme.outline, 1),
        enabledBorder: border(scheme.outline, 1),
        focusedBorder: border(scheme.primary, 2),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        prefixIcon: IconButton(
          key: const ValueKey('search-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(AppIcons.back),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (empty)
              IconButton(
                key: const ValueKey('search-paste'),
                tooltip: i18n('search_paste'),
                onPressed: () => unawaited(_paste()),
                icon: const Icon(AppIcons.paste),
              )
            else
              IconButton(
                key: const ValueKey('search-clear'),
                tooltip: i18n('clear'),
                onPressed: () {
                  _text.clear();
                  _focus.requestFocus();
                },
                icon: const Icon(AppIcons.close),
              ),
            IconButton(
              key: const ValueKey('search-submit'),
              tooltip: i18n('search_live'),
              onPressed: () => unawaited(_submit()),
              icon: const Icon(AppIcons.submitSearch),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, RoomGridGeometry geometry, double spacing, double mainSpacing) {
    if (!_model.searched) {
      return [
        if (_history.words.isNotEmpty)
          SliverToBoxAdapter(
            child: SearchHistoryPanel(
              words: _history.words,
              onSelected: (word) => unawaited(_submit(word)),
              onRemove: (word) => unawaited(_history.remove(word)),
              onClear: () => unawaited(_history.clear()),
            ),
          ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppStatusView(
            key: const ValueKey('search-start'),
            type: AppStatusType.empty,
            icon: AppIcons.searchStart,
            title: i18n('search_start_title'),
            subtitle: i18n('search_start_desc'),
          ),
        ),
      ];
    }
    if (_model.resultCount == 0) {
      if (_model.loading) {
        return [
          if (_model.mode == SearchMode.rooms)
            // Static cards of the real size (c8; U.4a c8).
            const SliverFillRemaining(child: RoomGridSkeleton(key: ValueKey('search-skeleton')))
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ];
      }
      return [SliverFillRemaining(hasScrollBody: false, child: _emptyStatus())];
    }
    final rooms = _model.results;
    return [
      if (_model.failed.isNotEmpty && !identical(_model.failed, _dismissedFailures))
        SliverToBoxAdapter(child: _failureNote(context)),
      if (_model.mode == SearchMode.rooms)
        SliverPadding(
          padding: const EdgeInsets.all(roomGridPadding),
          sliver: SliverGrid.builder(
            gridDelegate: geometry.delegate(spacing: spacing, mainSpacing: mainSpacing),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return RoomGridCard(
                key: ValueKey('room-${room.identityKey}'),
                room: room,
                // "All" mixes platforms: the badge shows which (c14, U.4a c2).
                mixedPlatforms: _model.selected == 0,
                onOpen: () => _openRoom(room, playlist: rooms),
              );
            },
          ),
        )
      else
        SliverList.builder(
          itemCount: _model.anchors.length,
          itemBuilder: (context, index) {
            final result = _model.anchors[index];
            return AnchorResultTile(
              key: ValueKey('anchor-${result.key}'),
              result: result,
              platformName: _siteName(result.platform),
              onTap: () => _openRoom(result.toRoom()),
            );
          },
        ),
      SliverToBoxAdapter(child: _footer(context)),
    ];
  }

  /// Whether an overseas platform is among the failed ones.
  bool get _overseasFailed => _model.failed.any(overseasPlatforms.contains);

  /// `有 3 个平台连接失败`, with the proxy hint when an overseas one failed.
  String _failureText() => [
    i18n('search_failures_note', args: {'count': '${_model.failed.length}'}),
    if (_overseasFailed) i18n('search_failures_proxy_hint'),
  ].join('，');

  String _failedNames() => [for (final id in _model.failed) _siteName(id)].join('、');

  /// A quiet note above the results (c9; 3.x's banner named every failed
  /// platform on each search): how many failed, why overseas ones may,
  /// which ones on request, and what to do about it.
  Widget _failureNote(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final action = TextButton.styleFrom(visualDensity: VisualDensity.compact);
    return Container(
      key: const ValueKey('search-failure-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 2),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(AppIcons.info, size: 18, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_failureText(), style: styles.t13)),
              IconButton(
                key: const ValueKey('search-failure-close'),
                visualDensity: VisualDensity.compact,
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: () => setState(() => _dismissedFailures = _model.failed),
                icon: const Icon(AppIcons.close, size: 18),
              ),
            ],
          ),
          if (_failureDetails)
            Padding(
              key: const ValueKey('search-failure-names'),
              padding: const EdgeInsets.fromLTRB(26, 2, 8, 0),
              child: Text(_failedNames(), style: styles.t12.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Wrap(
            children: [
              TextButton(
                key: const ValueKey('search-failure-details'),
                style: action,
                onPressed: () => setState(() => _failureDetails = !_failureDetails),
                child: Text(i18n(_failureDetails ? 'search_failures_hide' : 'search_failures_details')),
              ),
              TextButton(
                key: const ValueKey('search-failure-retry'),
                style: action,
                onPressed: _retry,
                child: Text(i18n('retry')),
              ),
              if (_model.selected == 0)
                TextButton(
                  key: const ValueKey('search-failure-scope'),
                  style: action,
                  onPressed: () => unawaited(_openScope()),
                  child: Text(i18n('search_scope')),
                ),
              if (_overseasFailed)
                TextButton(
                  key: const ValueKey('search-failure-proxy'),
                  style: action,
                  onPressed: () =>
                      unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings, arguments: SettingsSection.network)),
                  child: Text(i18n('search_proxy_settings')),
                ),
              if (_model.canOpenWebSearch)
                TextButton(
                  style: action,
                  onPressed: () => unawaited(_openWebSearch()),
                  child: Text(i18n('continue_web_search')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The four empty states, each with a sentence and a button whose icon
  /// says what it does (c10; 3.x showed "refresh" on every one).
  Widget _emptyStatus() {
    final unsupported = _model.unsupported;
    if (unsupported != null) {
      final name = _siteName(unsupported.id);
      return AppStatusView(
        key: const ValueKey('search-unsupported'),
        type: AppStatusType.empty,
        icon: AppIcons.noResults,
        title: i18n('search_no_results'),
        subtitle: _model.mode == SearchMode.anchors
            ? i18n('search_anchor_unsupported', args: {'site': name})
            : searchCoverageText(SearchCapabilities.of(unsupported.id), name),
        buttonText: _model.canOpenWebSearch ? i18n('continue_web_search') : null,
        buttonIcon: AppIcons.webSearch,
        onButtonPressed: _model.canOpenWebSearch ? () => unawaited(_openWebSearch()) : null,
      );
    }
    if (_model.hidesAllOffline) {
      return AppStatusView(
        key: const ValueKey('search-all-offline'),
        type: AppStatusType.empty,
        icon: AppIcons.noResults,
        title: i18n('search_no_live_results'),
        subtitle: i18n('search_offline_hidden_desc'),
        buttonText: i18n('search_show_offline'),
        buttonIcon: AppIcons.showHidden,
        onButtonPressed: () => _model.setIncludeOffline(value: true),
      );
    }
    if (_model.failed.isNotEmpty) {
      return AppStatusView(
        key: const ValueKey('search-failed'),
        type: AppStatusType.error,
        title: i18n('search_failed_title'),
        subtitle: '${_failureText()}\n${_failedNames()}',
        buttonText: i18n('retry'),
        buttonIcon: AppIcons.retry,
        onButtonPressed: _retry,
      );
    }
    return AppStatusView(
      key: const ValueKey('search-empty'),
      type: AppStatusType.empty,
      icon: AppIcons.noResults,
      title: i18n('search_no_results'),
      subtitle: i18n('search_no_results_desc'),
      buttonText: _model.canOpenWebSearch ? i18n('continue_web_search') : null,
      buttonIcon: AppIcons.webSearch,
      onButtonPressed: _model.canOpenWebSearch ? () => unawaited(_openWebSearch()) : null,
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Center(
          child: _model.loadingMore
              ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
              : _model.hasMore
              ? TextButton.icon(
                  key: const ValueKey('search-load-more'),
                  onPressed: () => unawaited(_model.loadMore()),
                  icon: const Icon(AppIcons.loadMore),
                  label: Text(i18n('load_more_results')),
                )
              : Text(
                  i18n('all_results_loaded'),
                  key: const ValueKey('search-all-loaded'),
                  style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant),
                ),
        ),
      ),
    );
  }
}
