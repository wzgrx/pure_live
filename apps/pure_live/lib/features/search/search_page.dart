import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// First page of every enabled platform for the keyword, merged: live rooms
/// first, then by audience (spec/product.md F-SRC-01 "智能" order). A failing
/// platform is left out instead of failing the whole list.
final FutureProviderFamily<List<RoomCard>, String> combinedSearchProvider = FutureProvider.autoDispose
    .family<List<RoomCard>, String>((ref, keyword) async {
      final sites = ref.watch(sitesProvider);
      final platforms = ref.watch(enabledPlatformsProvider);
      final pages = await Future.wait([
        for (final id in platforms)
          sites[id]!.search.search(keyword).then((page) => page.items).catchError((Object _) => <RoomCard>[]),
      ]);
      int audience(RoomCard card) => card.audience.online ?? card.audience.popularity ?? card.audience.cumulative ?? 0;
      return [for (final items in pages) ...items]..sort((a, b) {
        final live = (b.state == LiveState.live ? 1 : 0) - (a.state == LiveState.live ? 1 : 0);
        return live != 0 ? live : audience(b).compareTo(audience(a));
      });
    });

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

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _keyword = '';
  bool _liveOnly = false;
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: TvScope.of(context).enabled ? Space.s2 : layout.margin,
        title: SearchBar(
          controller: _controller,
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
              Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: FilterChip(
                  label: const Text(S.liveOnly),
                  selected: _liveOnly,
                  onSelected: (value) => setState(() => _liveOnly = value),
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CombinedResults(keyword: _keyword, liveOnly: _liveOnly),
                for (final id in platforms)
                  RoomGrid(
                    query: SearchQuery(id, _keyword),
                    where: _liveOnly ? (card) => card.state == LiveState.live : null,
                    emptyText: S.searchEmpty,
                  ),
              ],
            ),
          ),
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

class _CombinedResults extends ConsumerStatefulWidget {
  const new({required this.keyword, required this.liveOnly});

  final String keyword;
  final bool liveOnly;

  @override
  ConsumerState<_CombinedResults> createState() => _CombinedResultsState();
}

class _CombinedResultsState extends ConsumerState<_CombinedResults> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'search-grid');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(combinedSearchProvider(widget.keyword));
    return async.when(
      loading: () => const LoadingView(),
      error: (error, _) => MessageView.error(title: describeError(error).title),
      data: (cards) {
        final shown = widget.liveOnly ? cards.where((c) => c.state == LiveState.live).toList() : cards;
        if (shown.isEmpty) return const MessageView(title: S.searchEmpty);
        return LayoutBuilder(
          builder: (context, constraints) {
            final grid = CardGridGeometry.of(context, constraints.maxWidth);
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final now = DateTime.now();
            return GridView.builder(
              padding: grid.padding,
              gridDelegate: grid.delegate,
              itemCount: shown.length,
              itemBuilder: (context, index) => RoomCardTile(
                card: shown[index],
                coverWidth: grid.cellWidth,
                devicePixelRatio: dpr,
                now: now,
                origin: () => RoomOrigin.fromCards(shown, label: '搜索结果'),
                focusNode: _focus.node(index),
                onFocusChange: (focused) {
                  if (focused) _focus.focused(index);
                },
                onKeyEvent: (node, event) => _focus.handleKey(
                  index,
                  event,
                  count: shown.length,
                  columns: grid.columns,
                  rowExtent: grid.rowExtent,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
