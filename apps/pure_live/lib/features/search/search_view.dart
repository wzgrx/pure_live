import 'dart:async';

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
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The search page (3.x `SearchPage` with `SearchController`): a search
/// field that also takes room links, the platform row, rooms or streamers
/// from every platform as they answer, paging, filters, recent searches.
class SearchView extends ConsumerStatefulWidget {
  /// Creates the page; [initialKeyword] is searched at once.
  const new({this.initialKeyword, this.openRoom, this.openExternal, this.timeout = searchRequestTimeout, super.key});

  /// Words to search when the page opens.
  final String? initialKeyword;

  /// Opens a room; null uses [AppNavigator.toLiveRoomDetail].
  final void Function(LiveRoom room)? openRoom;

  /// Opens a web address outside the app; null uses
  /// [AppNavigator.openExternal].
  final Future<bool> Function(Uri uri)? openExternal;

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

  void _openRoom(LiveRoom room) {
    final open = widget.openRoom;
    if (open != null) {
      open(room);
    } else {
      unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
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

  /// Chooses the platforms "all" searches, remembers them and searches again.
  Future<void> _editScope() async {
    final excluded = await showSearchScopeDialog(context, _model.sites, _model.excluded);
    if (excluded == null || !mounted) return;
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
    if (InAppWeb.available) {
      // In the app (3.x `WebSearchPage`), which offers to open the rooms it
      // shows.
      await AppNavigator.toNamed<void>(RoutePath.kWebSearch, arguments: {'url': uri.toString(), 'platform': site.id});
      return;
    }
    var opened = false;
    try {
      opened = await (widget.openExternal ?? AppNavigator.openExternal)(uri);
    } on Object {
      opened = false;
    }
    if (mounted) _toast(i18n(opened ? 'search_web_opened' : 'external_browser_not_opened'));
  }

  void _retry() {
    _dismissedFailures = null;
    unawaited(_model.search(_model.keyword));
  }

  static int _columns(double width) => width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));

  @override
  Widget build(BuildContext context) {
    // Cards follow the card settings.
    watchSetting(ref, Settings.roomCardMobilePreset);
    watchSetting(ref, Settings.roomCardDesktopPreset);
    watchSetting(ref, Settings.roomCardMobileConfig);
    watchSetting(ref, Settings.roomCardDesktopConfig);
    final appearance = cardAppearanceOf(_store.settings);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: _field(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(searchPlatformStripHeight),
          child: SearchPlatformStrip(
            sites: _model.sites,
            selected: _model.selected,
            onSelected: (index) {
              _dismissedFailures = null;
              _model.select(index, draft: _text.text);
            },
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          key: const ValueKey('search-content'),
          controller: _scroll,
          physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: SearchOptionsBar(
                model: _model,
                onModeChanged: (mode) {
                  _dismissedFailures = null;
                  _model.setMode(mode, draft: _text.text);
                },
                onOpenWebSearch: () => unawaited(_openWebSearch()),
                onEditScope: () => unawaited(_editScope()),
              ),
            ),
            if (_linkDetected) SliverToBoxAdapter(child: _linkBanner(context)),
            if (_model.pending > 0) SliverToBoxAdapter(child: _pendingRow(context)),
            ..._content(context, _columns(constraints.maxWidth), appearance),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context) {
    final empty = _text.text.isEmpty;
    return TextField(
      key: const ValueKey('search-field'),
      controller: _text,
      focusNode: _focus,
      autofocus: widget.initialKeyword == null,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => unawaited(_submit()),
      decoration: InputDecoration(
        hintText: i18n('search_hint'),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (empty)
              IconButton(
                key: const ValueKey('search-paste'),
                tooltip: i18n('search_paste'),
                onPressed: () => unawaited(_paste()),
                icon: const Icon(Icons.content_paste_rounded),
              )
            else
              IconButton(
                key: const ValueKey('search-clear'),
                tooltip: i18n('clear'),
                onPressed: () {
                  _text.clear();
                  _focus.requestFocus();
                },
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              key: const ValueKey('search-submit'),
              tooltip: i18n('search_live'),
              onPressed: () => unawaited(_submit()),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('search-link-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: 0,
      color: scheme.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.link_rounded, color: scheme.onSecondaryContainer),
        title: Text(i18n('search_link_detected'), style: TextStyle(color: scheme.onSecondaryContainer)),
        subtitle: Text(
          i18n(_resolvingLink ? 'search_link_resolving' : 'search_link_desc'),
          style: TextStyle(color: scheme.onSecondaryContainer),
        ),
        trailing: _resolvingLink
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : FilledButton(
                key: const ValueKey('search-link-open'),
                onPressed: () => unawaited(_submit()),
                child: Text(i18n('search_room_enter')),
              ),
      ),
    );
  }

  Widget _pendingRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('search-pending'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 4),
          Text(
            i18n('search_pending', args: {'count': '${_model.pending}'}),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, int columns, RoomCardAppearance appearance) {
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
            type: AppStatusType.empty,
            icon: Icons.travel_explore_rounded,
            title: i18n('search_start_title'),
            subtitle: i18n('search_start_desc'),
          ),
        ),
      ];
    }
    if (_model.resultCount == 0) {
      if (_model.loading) {
        return [
          SliverToBoxAdapter(
            child: _model.mode == SearchMode.rooms
                ? SearchSkeletonGrid(columns: columns)
                : const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
          ),
        ];
      }
      return [SliverFillRemaining(hasScrollBody: false, child: _emptyStatus())];
    }
    return [
      if (_model.failed.isNotEmpty && !identical(_model.failed, _dismissedFailures))
        SliverToBoxAdapter(child: _failureBanner(context)),
      if (_model.mode == SearchMode.rooms)
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList.builder(
            itemCount: (_model.results.length + columns - 1) ~/ columns,
            itemBuilder: (context, row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: row * columns + column < _model.results.length
                          ? _card(context, _model.results[row * columns + column], appearance)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
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

  Widget _card(BuildContext context, LiveRoom room, RoomCardAppearance appearance) {
    return RoomCard(
      key: ValueKey('room-${room.identityKey}'),
      data: AudiencePolicy(preferRealOnline: _preferRealOnline, realOnlinePlatforms: _realOnline).cardOf(room),
      appearance: appearance,
      dense: true,
      onTap: () => _openRoom(room),
      onLongPress: () => unawaited(showRoomMenu(context, store: _store, room: room, onOpen: () => _openRoom(room))),
    );
  }

  /// Whether an overseas platform is among the failed ones.
  bool get _overseasFailed => _model.failed.any(overseasPlatforms.contains);

  /// `有 3 个平台连接失败`, with the proxy hint when an overseas one failed.
  String _failureText() => [
    i18n('search_failures_note', args: {'count': '${_model.failed.length}'}),
    if (_overseasFailed) i18n('search_failures_proxy_hint'),
  ].join('，');

  String _failedNames() => [for (final id in _model.failed) _siteName(id)].join('、');

  /// A quiet note above the results (M13.16; it was a banner naming every
  /// failed platform on each search): how many failed, why overseas ones
  /// may, which ones on request, and what to do about it.
  Widget _failureBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
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
                child: Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_failureText(), style: theme.textTheme.bodyMedium)),
              IconButton(
                key: const ValueKey('search-failure-close'),
                visualDensity: VisualDensity.compact,
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: () => setState(() => _dismissedFailures = _model.failed),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (_failureDetails)
            Padding(
              key: const ValueKey('search-failure-names'),
              padding: const EdgeInsets.fromLTRB(26, 2, 8, 0),
              child: Text(_failedNames(), style: small),
            ),
          Wrap(
            children: [
              TextButton(
                key: const ValueKey('search-failure-details'),
                style: action,
                onPressed: () => setState(() => _failureDetails = !_failureDetails),
                child: Text(i18n(_failureDetails ? 'search_failures_hide' : 'search_failures_details')),
              ),
              TextButton(style: action, onPressed: _retry, child: Text(i18n('retry'))),
              if (_model.selected == 0)
                TextButton(
                  key: const ValueKey('search-failure-scope'),
                  style: action,
                  onPressed: () => unawaited(_editScope()),
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

  Widget _emptyStatus() {
    final unsupported = _model.unsupported;
    if (unsupported != null) {
      final name = _siteName(unsupported.id);
      return AppStatusView(
        key: const ValueKey('search-unsupported'),
        type: AppStatusType.empty,
        icon: Icons.search_off_rounded,
        title: i18n('search_no_results'),
        subtitle: _model.mode == SearchMode.anchors
            ? i18n('search_anchor_unsupported', args: {'site': name})
            : searchCoverageText(SearchCapabilities.of(unsupported.id), name),
        buttonText: _model.canOpenWebSearch ? i18n('continue_web_search') : null,
        buttonIcon: Icons.open_in_browser_rounded,
        onButtonPressed: _model.canOpenWebSearch ? () => unawaited(_openWebSearch()) : null,
      );
    }
    if (_model.hidesAllOffline) {
      return AppStatusView(
        type: AppStatusType.empty,
        icon: Icons.search_off_rounded,
        title: i18n('search_no_live_results'),
        subtitle: i18n('search_offline_hidden_desc'),
        buttonText: i18n('search_show_offline'),
        buttonIcon: Icons.visibility_rounded,
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
        onButtonPressed: _retry,
      );
    }
    return AppStatusView(
      type: AppStatusType.empty,
      icon: Icons.search_off_rounded,
      title: i18n('search_no_results'),
      subtitle: i18n('search_no_results_desc'),
      buttonText: _model.canOpenWebSearch ? i18n('continue_web_search') : null,
      buttonIcon: Icons.open_in_browser_rounded,
      onButtonPressed: _model.canOpenWebSearch ? () => unawaited(_openWebSearch()) : null,
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
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
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(i18n('load_more_results')),
                )
              : Text(
                  i18n('all_results_loaded'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
      ),
    );
  }
}
