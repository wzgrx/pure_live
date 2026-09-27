import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
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

  @override
  Widget build(BuildContext context) {
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: layout.margin,
        title: SearchBar(
          controller: _controller,
          hintText: S.searchHint,
          elevation: const WidgetStatePropertyAll(0),
          leading: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          trailing: [
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
    if (_keyword.isEmpty) {
      return const MessageView(icon: Icons.search, title: S.searchHint);
    }
    return DefaultTabController(
      length: platformOrder.length,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final id in platformOrder) Tab(text: platformNames[id])],
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
                for (final id in platformOrder)
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
