import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/core/web/web_prompt.dart';
import 'package:pure_live_app/features/search/web_search_links.dart';

/// Location of the web search for [keyword] on [platform].
String webSearchLocation(String platform, String keyword) =>
    Uri(path: '/web-search', queryParameters: {'platform': platform, 'q': keyword}).toString();

/// Enabled platforms whose adapter has no native search but a known search
/// page (F-SRC-02), in the user's order.
final webSearchPlatformsProvider = Provider<List<String>>((ref) {
  final sites = ref.watch(sitesProvider);
  return [
    for (final id in ref.watch(enabledPlatformsProvider))
      if (needsWebSearch(id, sites[id]?.raw)) id,
  ];
});

/// The search page's "网页搜索" entry: hidden without a browser on this
/// platform or without a platform that needs it; on Windows without the
/// WebView2 Runtime it explains the install (F-SRC-02).
class WebSearchButton extends ConsumerWidget {
  const new({required this.keyword, super.key});

  /// The search box, read when tapped.
  final TextEditingController keyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platforms = ref.watch(webSearchPlatformsProvider);
    final availability = ref.watch(webAvailabilityProvider).value ?? WebAvailability.unsupported;
    if (platforms.isEmpty || availability == WebAvailability.unsupported) return const SizedBox.shrink();
    return IconButton(
      tooltip: '网页搜索',
      icon: const Icon(Icons.travel_explore),
      onPressed: () => _open(context, ref, platforms),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, List<String> platforms) async {
    final text = keyword.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先输入要搜索的关键词')));
      return;
    }
    if (!await ensureWebAvailable(context, ref) || !context.mounted) return;
    final platform = platforms.length == 1
        ? platforms.single
        : await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('在哪个平台的网页里搜索'),
              children: [
                for (final id in platforms)
                  SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text(platformNames[id] ?? id)),
              ],
            ),
          );
    if (platform != null && context.mounted) await context.push(webSearchLocation(platform, text));
  }
}

/// Searches on the platform's own page in the in-app browser (F-SRC-02): a
/// room link the user opens there is recognised with the app's link resolver
/// and offered as a room; "本页的房间" lists the room links on the page.
class WebSearchPage extends ConsumerStatefulWidget {
  const new({required this.platform, required this.keyword, super.key});

  /// Platform id.
  final String platform;

  /// What to search for.
  final String keyword;

  @override
  ConsumerState<WebSearchPage> createState() => _WebSearchPageState();
}

class _WebSearchPageState extends ConsumerState<WebSearchPage> {
  WebPage? _page;
  Uri? _start;
  StreamSubscription<WebPageEvent>? _events;
  int _progress = 0;
  bool _failed = false;
  // Rooms the user chose to stay on the web page for; not offered again.
  final Set<String> _dismissed = {};
  String? _offered;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(webEngineProvider);
    final start = webSearchUrl(widget.platform, widget.keyword);
    if (engine == null || start == null) return;
    final page = engine.open(filter: _allow);
    _events = page.events.listen(_onEvent);
    _page = page;
    _start = start;
    unawaited(page.load(start));
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_page?.dispose());
    super.dispose();
  }

  Future<RoomRef?> _resolve(Uri url) async {
    try {
      return await ref.read(linkResolverProvider)(url.toString()).timeout(const Duration(seconds: 5));
    } on Object {
      return null;
    }
  }

  /// A navigation to a room link opens the room offer instead of the page.
  Future<bool> _allow(Uri url) async {
    if (url == _start) return true;
    final room = await _resolve(url);
    if (!mounted || room == null || _dismissed.contains(room.key)) return true;
    unawaited(_offer(room, url));
    return false;
  }

  void _onEvent(WebPageEvent event) {
    if (!mounted) return;
    switch (event) {
      case WebPageStarted():
        setState(() {
          _progress = 0;
          _failed = false;
        });
      case WebPageProgress(:final percent):
        setState(() => _progress = percent);
      case WebPageFinished():
        setState(() => _progress = 100);
      case WebPageFailed():
        setState(() => _failed = true);
      case WebUrlChanged(:final url):
        // Single-page sites change the address without a navigation.
        unawaited(() async {
          final room = await _resolve(url);
          if (mounted && room != null && !_dismissed.contains(room.key)) await _offer(room, null);
        }());
    }
  }

  /// Offers [room]; "留在网页" continues to [link] when the navigation was held.
  Future<void> _offer(RoomRef room, Uri? link) async {
    if (_offered == room.key) return;
    _offered = room.key;
    final open = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PlatformLogo(platformId: room.platform, size: Sizes.iconLg),
              title: const Text('识别到直播间'),
              subtitle: Text('${platformNames[room.platform] ?? room.platform} · ${room.roomId}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('留在网页')),
                  const SizedBox(width: Space.s2),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('打开直播间')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    _offered = null;
    if (!mounted) return;
    if (open ?? false) {
      await context.push(roomLocation(room));
      return;
    }
    _dismissed.add(room.key);
    if (link != null) await _page?.load(link);
  }

  Future<void> _listRooms() async {
    final page = _page;
    if (page == null) return;
    final resolve = ref.read(linkResolverProvider);
    final current = await page.currentUrl();
    final found = () async {
      Object? result;
      try {
        result = await page.evaluate(pageLinksScript);
      } on Object {
        result = null;
      }
      return await findRooms(pageLinks(result, base: current), resolve);
    }();
    if (!mounted) return;
    final room = await showModalBottomSheet<RoomRef>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PageRoomsSheet(found: found),
    );
    if (room != null && mounted) await context.push(roomLocation(room));
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final name = platformNames[widget.platform] ?? widget.platform;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (page != null && await page.goBack()) return;
        if (context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('网页搜索 · $name'),
          actions: [
            if (page != null) ...[
              IconButton(tooltip: '本页的房间', icon: const Icon(Icons.format_list_bulleted), onPressed: _listRooms),
              IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: page.reload),
            ],
          ],
          bottom: page != null && _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
                )
              : null,
        ),
        body: page == null
            ? const MessageView(icon: Icons.public_off, title: '这里用不了网页搜索')
            : _failed
            ? MessageView.error(
                title: '网页没有打开',
                message: '检查网络或代理设置后重试。',
                onAction: () {
                  setState(() => _failed = false);
                  unawaited(page.reload());
                },
              )
            : page.build(context),
      ),
    );
  }
}

class _PageRoomsSheet extends StatelessWidget {
  const new({required this.found});

  final Future<List<FoundRoom>> found;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: FutureBuilder<List<FoundRoom>>(
        future: found,
        builder: (context, snapshot) {
          final rooms = snapshot.data;
          if (rooms == null) {
            return const SizedBox(height: 200, child: LoadingView(label: '正在识别本页的直播间'));
          }
          if (rooms.isEmpty) {
            return const SizedBox(height: 200, child: MessageView(title: '本页没有识别出直播间链接'));
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('本页的直播间')),
              for (final (:link, :room) in rooms)
                ListTile(
                  leading: PlatformLogo(platformId: room.platform, size: Sizes.iconLg),
                  title: Text('${platformNames[room.platform] ?? room.platform} · ${room.roomId}'),
                  subtitle: Text(link.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, room),
                ),
            ],
          );
        },
      ),
    ),
  );
}
