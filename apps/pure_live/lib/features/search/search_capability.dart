import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';

/// What a platform's search can find (3.x `NativeSearchCoverage`).
enum SearchCoverage {
  /// Keywords find rooms that are live now.
  liveOnly,

  /// Keywords find live rooms and some offline ones.
  liveAndOffline,

  /// Only an exact channel id or link; finds offline channels too.
  channelLookup,

  /// Only an exact room id or live link.
  roomLookup,

  /// Exact ids and links, otherwise a nickname filter over the platform's
  /// current showcase.
  showcaseSnapshot,

  /// The channels imported on this device.
  localChannels,

  /// No search in the app; the platform's web search only.
  webOnly,

  /// No search at all.
  unavailable,
}

/// One platform's search abilities (3.x `LiveSearchCapability`).
final class SearchCapability {
  /// Creates the abilities.
  const new({required this.coverage, required this.paged, this.webSearch = false, this.anchors = false, this.noteKey});

  /// What keywords find.
  final SearchCoverage coverage;

  /// Whether a keyword can have more than one page (the adapter can still
  /// refuse per keyword through `LiveSearchPaginationPolicy`).
  final bool paged;

  /// Whether the platform's web search can be opened ([webSearchUrl]).
  final bool webSearch;

  /// Whether the adapter searches streamers (`LiveSite.searchAnchors`).
  final bool anchors;

  /// The text key of a platform-specific explanation, replacing the one of
  /// [coverage].
  final String? noteKey;

  /// Whether the app can search the platform itself.
  bool get native => coverage != SearchCoverage.webOnly && coverage != SearchCoverage.unavailable;

  /// Whether results can include offline rooms.
  bool get mayIncludeOffline =>
      coverage == SearchCoverage.liveAndOffline ||
      coverage == SearchCoverage.channelLookup ||
      coverage == SearchCoverage.roomLookup;
}

/// The abilities of every platform (3.x `LiveSearchCapabilities`), checked
/// against the adapters of M4/M4.U:
///
/// - YY and TwitCasting keyword searches answer live rooms only (UPGRADES
///   A-5; 3.x said "live and offline"). A TwitCasting channel link still
///   finds an offline channel.
/// - YouTube searches keywords with the live filter and pages (23-2); exact
///   references (links, `@handle`, channel ids) find offline channels.
/// - Anchor search is offered where the adapter implements it.
abstract final class SearchCapabilities {
  static const Map<String, SearchCapability> _byPlatform = {
    SiteIds.bilibili: SearchCapability(
      coverage: SearchCoverage.liveAndOffline,
      paged: true,
      webSearch: true,
      anchors: true,
    ),
    SiteIds.douyu: SearchCapability(
      coverage: SearchCoverage.liveAndOffline,
      paged: true,
      webSearch: true,
      anchors: true,
    ),
    SiteIds.huya: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, webSearch: true, anchors: true),
    SiteIds.douyin: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, webSearch: true),
    SiteIds.kuaishou: SearchCapability(
      coverage: SearchCoverage.liveAndOffline,
      paged: true,
      webSearch: true,
      anchors: true,
    ),
    SiteIds.cc: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true, webSearch: true, anchors: true),
    SiteIds.twitch: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true, webSearch: true),
    SiteIds.soop: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, webSearch: true),
    SiteIds.yy: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, webSearch: true, anchors: true),
    SiteIds.acfun: SearchCapability(
      coverage: SearchCoverage.liveAndOffline,
      paged: true,
      webSearch: true,
      anchors: true,
      noteKey: 'search_coverage_acfun',
    ),
    SiteIds.picarto: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true, webSearch: true),
    SiteIds.twitcasting: SearchCapability(
      coverage: SearchCoverage.liveOnly,
      paged: true,
      webSearch: true,
      noteKey: 'search_scope_twitcasting',
    ),
    SiteIds.missevan: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.inke: SearchCapability(coverage: SearchCoverage.showcaseSnapshot, paged: true),
    SiteIds.kilakila: SearchCapability(
      coverage: SearchCoverage.liveAndOffline,
      paged: true,
      webSearch: true,
      noteKey: 'search_scope_kilakila',
    ),
    SiteIds.xiaohongshu: SearchCapability(coverage: SearchCoverage.roomLookup, paged: false),
    SiteIds.niconico: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, webSearch: true),
    SiteIds.weibo: SearchCapability(coverage: SearchCoverage.roomLookup, paged: false, noteKey: 'search_scope_weibo'),
    SiteIds.showroom: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true),
    SiteIds.chzzk: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    // M4.34: one page of channels (live or not), then tagged live broadcasts.
    SiteIds.kick: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: false),
    SiteIds.liveMe: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.tiktok: SearchCapability(coverage: SearchCoverage.channelLookup, paged: false),
    SiteIds.youtube: SearchCapability(coverage: SearchCoverage.liveOnly, paged: true, noteKey: 'search_scope_youtube'),
    SiteIds.bigo: SearchCapability(coverage: SearchCoverage.showcaseSnapshot, paged: false),
    SiteIds.pandaLive: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.fc2Live: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.steamBroadcast: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.jdLive: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.kugouLive: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: true),
    SiteIds.baiduLive: SearchCapability(coverage: SearchCoverage.roomLookup, paged: false),
    SiteIds.sixRoom: SearchCapability(coverage: SearchCoverage.liveAndOffline, paged: false),
    SiteIds.lookLive: SearchCapability(coverage: SearchCoverage.roomLookup, paged: false),
    SiteIds.seventeenLive: SearchCapability(coverage: SearchCoverage.liveOnly, paged: false),
    SiteIds.iptv: SearchCapability(coverage: SearchCoverage.localChannels, paged: false),
  };

  static const SearchCapability _unknown = SearchCapability(coverage: SearchCoverage.unavailable, paged: false);

  /// The abilities of [platform] (case ignored); unknown platforms cannot be
  /// searched.
  static SearchCapability of(String platform) => _byPlatform[platform.trim().toLowerCase()] ?? _unknown;
}

/// The platform's web search address for [keyword] (3.x `buildSearchUrl`),
/// or null when the platform has none.
Uri? webSearchUrl(String platform, String keyword) {
  final q = Uri.encodeComponent(keyword.trim());
  final url = switch (platform) {
    SiteIds.bilibili => 'https://search.bilibili.com/live?keyword=$q',
    SiteIds.douyu => 'https://www.douyu.com/search?kw=$q',
    SiteIds.huya => 'https://www.huya.com/search?hsk=$q',
    SiteIds.douyin => 'https://www.douyin.com/search/$q?type=live',
    SiteIds.kuaishou => 'https://live.kuaishou.com/search?keyword=$q',
    SiteIds.cc => 'https://cc.163.com/search/all/?query=$q&only=all',
    SiteIds.twitch => 'https://www.twitch.tv/search?term=$q',
    SiteIds.soop => 'https://www.sooplive.co.kr/?szKeyword=$q',
    SiteIds.yy => 'https://www.yy.com/search-$q',
    SiteIds.acfun => 'https://www.acfun.cn/search?keyword=$q&type=user',
    SiteIds.picarto => 'https://picarto.tv/search?q=$q',
    SiteIds.twitcasting => 'https://twitcasting.tv/search/text/?tw_search_query=$q',
    SiteIds.niconico => 'https://live.nicovideo.jp/search?keyword=$q&status=onair',
    SiteIds.kilakila => 'https://live.kilakila.cn/aboutus/serach/kw/$q',
    _ => null,
  };
  return url == null || q.isEmpty ? null : Uri.parse(url);
}

/// The words explaining what [capability] finds on [siteName].
String searchCoverageText(SearchCapability capability, String siteName) {
  final key =
      capability.noteKey ??
      switch (capability.coverage) {
        SearchCoverage.liveOnly => 'search_scope_live_only',
        SearchCoverage.liveAndOffline => 'search_scope_live_and_offline',
        SearchCoverage.channelLookup => 'search_scope_channel_lookup',
        SearchCoverage.roomLookup => 'search_scope_room_lookup',
        SearchCoverage.showcaseSnapshot => 'search_scope_showcase',
        SearchCoverage.localChannels => 'search_scope_local',
        SearchCoverage.webOnly || SearchCoverage.unavailable => 'search_scope_unavailable',
      };
  return i18n(key, args: {'site': siteName});
}

/// What [capability] finds, without the platform's name: one line of the
/// scope panel (docs/T07/T07f/T07f.2 c6), such as "只能搜到正在直播的房间".
String searchCoverageShortText(SearchCapability capability) {
  final note = capability.noteKey;
  if (note != null) return i18n('${note}_short');
  return i18n(switch (capability.coverage) {
    SearchCoverage.liveOnly => 'search_scope_short_live_only',
    SearchCoverage.liveAndOffline => 'search_scope_short_live_and_offline',
    SearchCoverage.channelLookup => 'search_scope_short_channel_lookup',
    SearchCoverage.roomLookup => 'search_scope_short_room_lookup',
    SearchCoverage.showcaseSnapshot => 'search_scope_short_showcase',
    SearchCoverage.localChannels => 'search_scope_short_local',
    SearchCoverage.webOnly || SearchCoverage.unavailable => 'search_scope_short_unavailable',
  });
}
