import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';

/// Platform search pages for the web-search fallback (F-SRC-02; addresses
/// from the 3.x `buildSearchUrl`). `{q}` is the percent-encoded keyword.
const _searchPages = {
  'bilibili': 'https://search.bilibili.com/live?keyword={q}',
  'douyu': 'https://www.douyu.com/search?kw={q}',
  'huya': 'https://www.huya.com/search?hsk={q}',
  'douyin': 'https://www.douyin.com/search/{q}?type=live',
  'kuaishou': 'https://live.kuaishou.com/search?keyword={q}',
  'cc': 'https://cc.163.com/search/all/?query={q}&only=all',
  'yy': 'https://www.yy.com/search-{q}',
  'soop': 'https://www.sooplive.co.kr/?szKeyword={q}',
  'acfun': 'https://www.acfun.cn/search?keyword={q}&type=user',
  'twitch': 'https://www.twitch.tv/search?term={q}',
  'niconico': 'https://live.nicovideo.jp/search?keyword={q}&status=onair',
  'kilakila': 'https://live.kilakila.cn/aboutus/serach/kw/{q}',
  'picarto': 'https://picarto.tv/search?q={q}',
  'twitcasting': 'https://twitcasting.tv/search/text/?tw_search_query={q}',
};

/// The platform's own search page for [keyword], or null when the platform
/// has none this app knows.
Uri? webSearchUrl(String platform, String keyword) {
  final template = _searchPages[platform];
  final text = keyword.trim();
  if (template == null || text.isEmpty) return null;
  return Uri.parse(template.replaceAll('{q}', Uri.encodeComponent(text)));
}

/// Whether [site] needs the web fallback: its adapter has no native search
/// (F-SRC-02) and the platform has a known search page.
bool needsWebSearch(String platform, Object? site) => site is! SearchSource && _searchPages.containsKey(platform);

/// The script that lists the page's links (absolute, as the browser resolved
/// them), at most 500.
const pageLinksScript = 'JSON.stringify(Array.from(document.querySelectorAll("a[href]"), (a) => a.href).slice(0, 500))';

/// The links in [result] of [pageLinksScript]: web addresses only, without
/// fragments or duplicates, in page order, at most [limit]. Engines return
/// the script's string as is (Windows) or JSON-quoted once more (Android);
/// both are accepted. Relative links resolve against [base].
List<Uri> pageLinks(Object? result, {Uri? base, int limit = 60}) {
  var value = result;
  for (var i = 0; i < 3 && value is String; i++) {
    final text = value.trim();
    if (!text.startsWith('[') && !text.startsWith('"')) break;
    try {
      value = jsonDecode(text);
    } on FormatException {
      break;
    }
  }
  if (value is! List) return const [];
  final seen = <String>{};
  final links = <Uri>[];
  for (final item in value) {
    if (item is! String) continue;
    var url = Uri.tryParse(item.trim());
    if (url == null) continue;
    if (!url.hasScheme && base != null) url = base.resolveUri(url);
    if (!(url.isScheme('http') || url.isScheme('https')) || url.host.isEmpty || url.userInfo.isNotEmpty) continue;
    final clean = url.removeFragment();
    if (base != null && clean == base.removeFragment()) continue;
    if (!seen.add(clean.toString())) continue;
    links.add(clean);
    if (links.length >= limit) break;
  }
  return links;
}

/// A room link found on a page.
typedef FoundRoom = ({Uri link, RoomRef room});

/// Resolves [links] with [resolve] (the app's `linkResolverProvider`), a few
/// at a time, and keeps the rooms: one entry per room, in link order.
/// Failures and links that are not rooms are skipped; [timeout] bounds each.
Future<List<FoundRoom>> findRooms(
  List<Uri> links,
  Future<RoomRef?> Function(String input) resolve, {
  int concurrency = 4,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final results = List<RoomRef?>.filled(links.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < links.length) {
      final index = next++;
      try {
        results[index] = await resolve(links[index].toString()).timeout(timeout);
      } on Object {
        results[index] = null;
      }
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  final seen = <String>{};
  return [
    for (final (index, room) in results.indexed)
      if (room != null && seen.add(room.key)) (link: links[index], room: room),
  ];
}
