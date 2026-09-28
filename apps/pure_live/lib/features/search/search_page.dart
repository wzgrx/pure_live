import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/discover/discover_page.dart' show platformTab;
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/features/search/search_results.dart';
import 'package:pure_live_app/features/search/web_search_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Looks like a link or share text rather than a keyword.
bool looksLikeLink(String input) =>
    RegExp(r'https?://|\b[\w-]+\.(com|cn|tv|net)\b', caseSensitive: false).hasMatch(input);

/// Search: one box for keywords and links (principles §4.1). A recognised link
/// shows "打开直播间" on top; keywords search every platform, grouped by platform.
class SearchPage extends ConsumerStatefulWidget {
  const new({this.initialQuery, super.key});

  /// Text to search right away (shared text that is not a room link).
  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

/// Asks the search page to focus its box (Ctrl+F, principles §6.2); the
/// value counts the requests.
class SearchFocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// Focus requests for the search box.
final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, int>(SearchFocusRequest.new);

class _SearchPageState extends ConsumerState<SearchPage> {
  static const double _boxHeight = 48;
  static const double _barHeight = _boxHeight + 2 * Space.s2;

  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search box');
  String _keyword = '';
  bool _liveOnly = false;
  SearchSort _sort = SearchSort.smart;

  /// The platform chosen in the wide layout's rail; null is 综合.
  String? _platform;
  Future<RoomRef?>? _link;

  @override
  void initState() {
    super.initState();
    _applyInitial();
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery) _applyInitial();
  }

  void _applyInitial() {
    final query = widget.initialQuery;
    if (query == null || query.trim().isEmpty) return;
    _controller.text = query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _submit(query);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final input = value.trim();
    if (input.isEmpty) return;
    setState(() {
      _link = looksLikeLink(input) ? ref.read(linkResolverProvider)(input) : null;
      _keyword = _link == null ? input : '';
    });
  }

  /// TV search by voice (principles §5.3): the platform's recognizer, when it
  /// has one; the system keyboard's own microphone works as well.
  Future<void> _voice() async {
    final text = await TvDevice.recognizeSpeech();
    if (text == null || !mounted) return;
    setState(() => _controller.text = text);
    _submit(text);
  }

  @override
  Widget build(BuildContext context) {
    final voice = TvScope.of(context).enabled && ref.watch(tvDeviceProvider).voiceSearch;
    ref.listen(searchFocusRequestProvider, (_, _) {
      _focus.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
    return Scaffold(
      // The box keeps 8 dp above and below instead of filling the bar.
      appBar: PageAppBar(
        toolbarHeight: _barHeight,
        title: SearchBar(
          controller: _controller,
          focusNode: _focus,
          hintText: t.search.hint,
          elevation: const WidgetStatePropertyAll(0),
          constraints: const BoxConstraints(minHeight: _boxHeight, maxHeight: _boxHeight, maxWidth: 800),
          leading: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          trailing: [
            if (voice) IconButton(tooltip: t.search.voice, icon: const Icon(Icons.mic_none), onPressed: _voice),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: t.search.clear,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _controller.clear();
                  _keyword = '';
                  _link = null;
                }),
              ),
          ],
          onChanged: (_) => setState(() {}),
        ),
        actions: [WebSearchButton(keyword: _controller)],
      ),
      body: _link != null ? _LinkResult(future: _link!) : _keywordResults(),
    );
  }

  Widget _keywordResults() {
    final platforms = ref.watch(searchablePlatformsProvider);
    if (_keyword.isEmpty) {
      return MessageView(icon: Icons.search, title: t.search.hint);
    }
    final size = MediaQuery.sizeOf(context);
    final layout = WindowLayout(size);
    // principles §5.2: from the expanded class a filter rail replaces the
    // platform tabs (not on TV, whose canvas has its own rules, nor on
    // landscape phones).
    final wide = !TvScope.of(context).enabled && layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
    final keyword = _keyword;
    final sort = _sort;
    final margin = PageMargin.of(context);
    bool Function(RoomCard card)? where;
    if (_liveOnly) where = (card) => card.state == LiveState.live;
    Widget results(String? platform) => platform == null
        ? _CombinedResults(keyword: keyword, liveOnly: _liveOnly, sort: sort, platforms: platforms)
        : RoomGrid(
            query: SearchQuery(platform, keyword),
            where: where,
            arrange: (cards) => sortSearch(cards, sort, platforms: platforms),
            emptyText: t.search.empty,
            originLabel: t.search.results,
            offlineAsRows: true,
          );
    // The sort menu's icon sits on the line it starts from; its label and
    // the chip follow.
    final tools = [
      PopupMenuButton<SearchSort>(
        tooltip: t.follows.sortTooltip,
        initialValue: sort,
        onSelected: (value) => setState(() => _sort = value),
        itemBuilder: (context) => [
          for (final MapEntry(key: option, value: label) in searchSortLabels.entries)
            CheckedPopupMenuItem(value: option, checked: option == sort, child: Text(label)),
        ],
        child: Padding(
          padding: const EdgeInsets.all(Space.s2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort, size: Sizes.iconDense),
              const SizedBox(width: Space.s1),
              Text(searchSortLabels[sort]!),
            ],
          ),
        ),
      ),
      const SizedBox(width: Space.s2),
      FilterChip(
        label: Text(t.search.liveOnly),
        selected: _liveOnly,
        onSelected: (value) => setState(() => _liveOnly = value),
      ),
    ];
    if (wide) {
      final platform = platforms.contains(_platform) ? _platform : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _PlatformRail.width,
            child: _PlatformRail(
              keyword: keyword,
              platforms: platforms,
              selected: platform,
              onSelected: (value) => setState(() => _platform = value),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                // The heading on the grid's line, the chip ending on the margin.
                Padding(
                  padding: EdgeInsetsDirectional.only(start: margin, end: margin),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          platform == null ? t.search.all : platformName(platform),
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...tools,
                    ],
                  ),
                ),
                Expanded(
                  child: KeyedSubtree(key: ValueKey(platform), child: results(platform)),
                ),
              ],
            ),
          ),
        ],
      );
    }
    // Compact and medium (principles §5.2): the platforms as discover's logo
    // tabs over the whole width, the order and 只看开播 on a second row.
    return DefaultTabController(
      length: platforms.length + 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTabBar(
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.travel_explore, size: 18),
                    const SizedBox(width: Space.s2),
                    Text(t.search.all),
                  ],
                ),
              ),
              for (final id in platforms) platformTab(id),
            ],
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(math.max(0, margin - Space.s2), Space.s1, margin, 0),
            child: Row(children: tools),
          ),
          Expanded(child: TabBarView(children: [results(null), for (final id in platforms) results(id)])),
        ],
      ),
    );
  }
}

/// The filter rail of wide windows (principles §5.2): 综合 and each platform
/// with the number of rooms the combined search found there so far. The
/// platforms without results fold into one "其它平台" entry, so the few that
/// matter are not lost among a dozen zeros.
class _PlatformRail extends ConsumerStatefulWidget {
  const new({required this.keyword, required this.platforms, required this.selected, required this.onSelected});

  /// Width of the rail.
  static const double width = 216;

  final String keyword;
  final List<String> platforms;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  ConsumerState<_PlatformRail> createState() => _PlatformRailState();
}

class _PlatformRailState extends ConsumerState<_PlatformRail> {
  bool _othersOpen = false;

  @override
  Widget build(BuildContext context) {
    final combined = ref.watch(combinedSearchProvider(widget.keyword)).value;
    final counts = combined?.counts ?? const <String, int>{};
    // A failure is news too: it stays in view with its tag.
    bool found(String id) => (counts[id] ?? 0) > 0 || (combined?.failed.contains(id) ?? false);
    final shown = [
      for (final id in widget.platforms)
        if (found(id)) id,
    ];
    final others = [
      for (final id in widget.platforms)
        if (!found(id)) id,
    ];
    final open = _othersOpen || others.contains(widget.selected);
    Widget? count(String text) => combined == null ? null : Text(text, style: LiveTheme.of(context).numeric);
    Widget platform(String id) => ListTile(
      leading: PlatformLogo(platformId: id, size: Sizes.iconDense),
      title: Text(platformName(id), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: count(combined?.failed.contains(id) ?? false ? t.search.failedTag : '${counts[id] ?? 0}'),
      selected: widget.selected == id,
      onTap: () => widget.onSelected(id),
    );
    return ListTileTheme.merge(
      contentPadding: EdgeInsetsDirectional.only(start: PageMargin.of(context), end: Space.s4),
      horizontalTitleGap: Space.s3,
      minLeadingWidth: Sizes.iconDense,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.s2),
        children: [
          ListTile(
            leading: const Icon(Icons.travel_explore, size: Sizes.iconDense),
            title: Text(t.search.all, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: count('${combined?.items.length ?? 0}'),
            selected: widget.selected == null,
            onTap: () => widget.onSelected(null),
          ),
          for (final id in shown) platform(id),
          if (others.isNotEmpty)
            ListTile(
              leading: Icon(open ? Icons.expand_less : Icons.expand_more, size: Sizes.iconDense),
              title: Text(t.search.otherPlatforms(n: others.length), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => setState(() => _othersOpen = !open),
            ),
          if (open)
            for (final id in others) platform(id),
        ],
      ),
    );
  }
}

class _LinkResult extends StatelessWidget {
  const new({required this.future});

  final Future<RoomRef?> future;

  @override
  Widget build(BuildContext context) => FutureBuilder<RoomRef?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return LoadingView(label: t.search.resolvingLink);
      if (snapshot.hasError) {
        final text = describeError(snapshot.error!);
        return MessageView.error(title: text.title, message: text.message);
      }
      final room = snapshot.data;
      if (room == null) return MessageView(title: t.search.noLinkMatch);
      final margin = PageMargin.of(context);
      return ListView(
        padding: EdgeInsets.fromLTRB(margin, Space.s2, margin, Space.s4),
        children: [
          Card(
            child: ListTile(
              leading: PlatformLogo(platformId: room.platform, size: Sizes.iconLg),
              title: Text(t.common.openRoom),
              subtitle: Text('${platformNames[room.platform] ?? room.platform} · ${room.roomId}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(roomLocation(room)),
            ),
          ),
        ],
      );
    },
  );
}

class _CombinedResults extends ConsumerWidget {
  const new({required this.keyword, required this.liveOnly, required this.sort, required this.platforms});

  final String keyword;
  final bool liveOnly;
  final SearchSort sort;
  final List<String> platforms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = combinedSearchProvider(keyword);
    final async = ref.watch(provider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingView(),
      error: (error, _) => MessageView.error(title: describeError(error).title),
      data: (state) {
        final found = liveOnly ? state.items.where((card) => card.state == LiveState.live).toList() : state.items;
        final failed = state.failed;
        return RoomCardGrid(
          density: ref.watch(cardDensityProvider),
          offlineAsRows: true,
          items: sortSearch(found, sort, platforms: platforms),
          hasMore: state.hasMore,
          moreError: state.moreError,
          emptyText: failed.length == platforms.length ? t.search.allFailed : t.search.empty,
          originLabel: t.search.results,
          header: failed.isEmpty || failed.length == platforms.length
              ? null
              : Padding(
                  padding: EdgeInsets.fromLTRB(PageMargin.of(context), Space.s2, PageMargin.of(context), 0),
                  child: Text(
                    t.search.someFailed(platforms: failed.map(platformName).join(t.common.listSeparator)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          onLoadMore: () => ref.read(provider.notifier).loadMore(),
          onRefresh: () => ref.refresh(provider.future),
        );
      },
    );
  }
}
