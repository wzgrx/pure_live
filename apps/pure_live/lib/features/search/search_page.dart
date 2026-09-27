import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/features/search/search_results.dart';
import 'package:pure_live_app/l10n/strings.dart';

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
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final voice = TvScope.of(context).enabled && ref.watch(tvDeviceProvider).voiceSearch;
    ref.listen(searchFocusRequestProvider, (_, _) {
      _focus.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
    return Scaffold(
      appBar: AppBar(
        titleSpacing: TvScope.of(context).enabled ? Space.s2 : layout.margin,
        title: SearchBar(
          controller: _controller,
          focusNode: _focus,
          hintText: S.searchHint,
          elevation: const WidgetStatePropertyAll(0),
          leading: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          trailing: [
            if (voice) IconButton(tooltip: '语音搜索', icon: const Icon(Icons.mic_none), onPressed: _voice),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: '清除',
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
      ),
      body: _link != null ? _LinkResult(future: _link!) : _keywordResults(),
    );
  }

  Widget _keywordResults() {
    final platforms = ref.watch(enabledPlatformsProvider);
    if (_keyword.isEmpty) {
      return const MessageView(icon: Icons.search, title: S.searchHint);
    }
    final size = MediaQuery.sizeOf(context);
    final layout = WindowLayout(size);
    // principles §5.2: from the expanded class a filter rail replaces the
    // platform tabs (not on TV, whose canvas has its own rules, nor on
    // landscape phones).
    final wide = !TvScope.of(context).enabled && layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
    final keyword = _keyword;
    final sort = _sort;
    bool Function(RoomCard card)? where;
    if (_liveOnly) where = (card) => card.state == LiveState.live;
    Widget results(String? platform) => platform == null
        ? _CombinedResults(keyword: keyword, liveOnly: _liveOnly, sort: sort, platforms: platforms)
        : RoomGrid(
            query: SearchQuery(platform, keyword),
            where: where,
            arrange: (cards) => sortSearch(cards, sort, platforms: platforms),
            emptyText: S.searchEmpty,
            originLabel: '搜索结果',
          );
    final tools = [
      PopupMenuButton<SearchSort>(
        tooltip: '排序',
        initialValue: sort,
        onSelected: (value) => setState(() => _sort = value),
        itemBuilder: (context) => [
          for (final MapEntry(key: option, value: label) in searchSortLabels.entries)
            CheckedPopupMenuItem(value: option, checked: option == sort, child: Text(label)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
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
      Padding(
        padding: const EdgeInsets.only(right: Space.s2),
        child: FilterChip(
          label: const Text(S.liveOnly),
          selected: _liveOnly,
          onSelected: (value) => setState(() => _liveOnly = value),
        ),
      ),
    ];
    if (wide) {
      final platform = platforms.contains(_platform) ? _platform : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 200,
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
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: layout.margin),
                      child: Text(
                        platform == null ? '综合' : platformName(platform),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Spacer(),
                    ...tools,
                  ],
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
    return DefaultTabController(
      length: platforms.length + 1,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    const Tab(text: '综合'),
                    for (final id in platforms) Tab(text: platformNames[id]),
                  ],
                ),
              ),
              ...tools,
            ],
          ),
          Expanded(child: TabBarView(children: [results(null), for (final id in platforms) results(id)])),
        ],
      ),
    );
  }
}

/// The filter rail of wide windows (principles §5.2): 综合 and each platform
/// with the number of rooms the combined search found there so far.
class _PlatformRail extends ConsumerWidget {
  const new({required this.keyword, required this.platforms, required this.selected, required this.onSelected});

  final String keyword;
  final List<String> platforms;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combined = ref.watch(combinedSearchProvider(keyword)).value;
    final counts = combined?.counts ?? const <String, int>{};
    String? count(int? value) => value == null ? null : '$value';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.s2),
      children: [
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: const Text('综合'),
          trailing: combined == null ? null : Text('${combined.items.length}'),
          selected: selected == null,
          onTap: () => onSelected(null),
        ),
        for (final id in platforms)
          ListTile(
            leading: PlatformLogo(platformId: id, size: Sizes.iconDense),
            title: Text(platformName(id)),
            trailing: combined == null ? null : Text(combined.failed.contains(id) ? '失败' : count(counts[id]) ?? '0'),
            selected: selected == id,
            onTap: () => onSelected(id),
          ),
      ],
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
      if (snapshot.connectionState != ConnectionState.done) return const LoadingView(label: S.resolvingLink);
      if (snapshot.hasError) {
        final text = describeError(snapshot.error!);
        return MessageView.error(title: text.title, message: text.message);
      }
      final room = snapshot.data;
      if (room == null) return const MessageView(title: S.noLinkMatch);
      return ListView(
        padding: const EdgeInsets.all(Space.s4),
        children: [
          Card(
            child: ListTile(
              leading: PlatformLogo(platformId: room.platform, size: Sizes.iconLg),
              title: const Text(S.openRoom),
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
          items: sortSearch(found, sort, platforms: platforms),
          hasMore: state.hasMore,
          moreError: state.moreError,
          emptyText: failed.length == platforms.length ? '搜索失败，检查网络后下拉重试' : S.searchEmpty,
          originLabel: '搜索结果',
          header: failed.isEmpty || failed.length == platforms.length
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
                  child: Text(
                    '${failed.map(platformName).join('、')} 搜索失败，下拉可以重试',
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
