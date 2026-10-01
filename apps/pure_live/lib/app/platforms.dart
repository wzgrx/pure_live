import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';

/// The app proxy settings as live_net's [ProxyPolicy] (3.x
/// `buildProxyDirective` over `enableAppProxy`, `appProxyHost`,
/// `appProxyPort`). Read at every request and handshake, so a change needs
/// no new client (3.x rebuilt dio).
final class SettingsProxyPolicy implements ProxyPolicy {
  /// Creates the policy over [settings].
  new(this.settings);

  /// The settings.
  final SettingsStore settings;

  @override
  ProxyRoute routeFor(String site, Uri url) => proxyRouteFrom(
    enabled: settings.get(Settings.enableAppProxy),
    host: settings.get(Settings.appProxyHost),
    port: settings.get(Settings.appProxyPort),
  );
}

/// The sealed cookies as live_net's [CookieVault] (M9: `cookieFor` and
/// `cookieChanges` of the secret store).
final class StoreCookieVault implements CookieVault {
  /// Creates the vault over [secrets].
  new(this.secrets);

  /// The secrets.
  final SecretStore secrets;

  @override
  String? cookieFor(String site) => secrets.cookieFor(site);

  @override
  Stream<String> get changes => secrets.cookieChanges;
}

/// Douyu's renewable login (3.x kept LTP0, DID and the save time next to
/// the cookie).
final class StoreDouyuLogin implements DouyuLoginStore {
  /// Creates the login over [store].
  new(this.store);

  /// The store.
  final LiveStore store;

  @override
  String? get longTermKey => store.secrets.read(SecretRefs.douyuLtp0);

  @override
  String? get deviceId => store.secrets.read(SecretRefs.douyuDid);

  @override
  DateTime? get savedAt {
    final seconds = store.settings.get(Settings.douyuCookieSavedAt);
    return seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  @override
  Future<void> saveRenewed(String cookie, DateTime renewedAt) async {
    await store.secrets.setCookie(SiteIds.douyu, cookie);
    await store.settings.set(Settings.douyuCookieSavedAt, renewedAt.millisecondsSinceEpoch ~/ 1000);
  }
}

/// What the platform adapters share.
final class PlatformDeps {
  /// Creates the dependencies.
  new({
    required this.http,
    required this.proxy,
    required this.cookies,
    required this.store,
    this.twitchFallbacks = const [],
    this.iptv,
  });

  /// The HTTP client of every adapter (per-platform proxy routes inside).
  final LiveHttp http;

  /// The proxy rules (sockets of the danmaku and FC2/niconico controls).
  final ProxyPolicy proxy;

  /// The user's cookies.
  final CookieVault cookies;

  /// Storage (settings read at each request).
  final LiveStore store;

  /// Extra GraphQL transports of Twitch (Android's system TLS).
  final List<LiveHttp> twitchFallbacks;

  /// The IPTV platform; null leaves IPTV out.
  final IptvSite? iptv;
}

/// The 33 platforms and IPTV (3.x `Sites.supportSites`), each built on first
/// use and then kept (M3 `SiteRegistry`).
SiteRegistry buildSiteRegistry(PlatformDeps deps) {
  final http = deps.http;
  final cookies = deps.cookies;
  final settings = deps.store.settings;
  bool preferH264() => settings.get(Settings.preferH264);
  return SiteRegistry({
    SiteIds.bilibili: () => BilibiliSite(http, cookies: cookies, storedUid: () => settings.get(Settings.bilibiliUid)),
    SiteIds.douyu: () => DouyuSite(
      http,
      cookies: cookies,
      login: StoreDouyuLogin(deps.store),
      forceRenewal: () => settings.get(Settings.douyuForceRenew),
    ),
    SiteIds.huya: () => HuyaSite(http, cookies: cookies, preferH264: preferH264),
    SiteIds.douyin: () => DouyinSite(http, cookies: cookies),
    SiteIds.kuaishou: () => KuaishouSite(http, cookies: cookies, preferH264: preferH264),
    SiteIds.cc: () => CcSite(http),
    SiteIds.twitch: () => TwitchSite(
      http,
      cookies: cookies,
      gqlFallbacks: deps.twitchFallbacks,
      languages: () => settings.get(Settings.twitchLanguages),
      preferH264: preferH264,
    ),
    SiteIds.soop: () => SoopSite(http, cookies: cookies),
    SiteIds.yy: () => YySite(http, cookies: cookies),
    SiteIds.acfun: () => AcfunSite(http),
    SiteIds.picarto: () => PicartoSite(http),
    SiteIds.twitcasting: () => TwitcastingSite(http),
    SiteIds.missevan: () => MissevanSite(http),
    SiteIds.inke: () => InkeSite(http, preferH264: preferH264),
    SiteIds.kilakila: () => KilakilaSite(http),
    SiteIds.xiaohongshu: () => XiaohongshuSite(http),
    SiteIds.niconico: () => NiconicoSite(http, proxy: deps.proxy),
    SiteIds.weibo: () => WeiboSite(http),
    SiteIds.showroom: () => ShowroomSite(http),
    SiteIds.chzzk: () => ChzzkSite(http),
    SiteIds.liveMe: () => LiveMeSite(http),
    SiteIds.tiktok: () => TikTokSite(http, preferH264: preferH264),
    SiteIds.youtube: () => YouTubeSite(http),
    SiteIds.bigo: () => BigoSite(http),
    SiteIds.pandaLive: () => PandaLiveSite(http),
    SiteIds.fc2Live: () => Fc2LiveSite(http, proxy: deps.proxy),
    SiteIds.steamBroadcast: () => SteamBroadcastSite(http),
    SiteIds.jdLive: () => JdLiveSite(http),
    SiteIds.kugouLive: () => KugouLiveSite(http, preferH264: preferH264),
    SiteIds.baiduLive: () => BaiduLiveSite(http, preferH264: preferH264),
    SiteIds.sixRoom: () => SixRoomSite(http),
    SiteIds.lookLive: () => LookLiveSite(http),
    SiteIds.seventeenLive: () => SeventeenLiveSite(http, preferH264: preferH264),
    if (deps.iptv case final iptv?) SiteIds.iptv: () => iptv,
  });
}

/// The danmaku connections (M5 "登记方式" of every platform).
///
/// Not registered, so the room shows 3.x's "not connected" notice once:
/// CC (anonymous joins get no answer, UPGRADES C-22), Inke, Xiaohongshu,
/// Weibo (no chat in 3.x or M5), LiveMe and TikTok (blocked: login and
/// signing, M5.17/M5.18), IPTV.
DanmakuRegistry buildDanmakuRegistry(PlatformDeps deps, SiteRegistry sites) {
  final http = deps.http;
  final proxy = deps.proxy;
  final settings = deps.store.settings;
  final connector = danmakuHandshake();
  return DanmakuRegistry({
    SiteIds.bilibili: () => BilibiliDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.douyu: () => DouyuDanmakuConnection(
      proxy: proxy,
      connector: connector,
      filterSuspectedAutomatedMessages: () => settings.get(Settings.filterDouyuSuspectedAutomatedMessages),
    ),
    SiteIds.huya: () => HuyaDanmakuConnection(proxy: proxy, connector: connector),
    // The room's DouyinDanmakuArgs carry `refresh` (B-5), set by DouyinSite.
    SiteIds.douyin: () => DouyinDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.kuaishou: () => KuaishouDanmakuConnection(http: http),
    SiteIds.twitch: () => TwitchDanmakuConnection(proxy: proxy, connector: connector),
    // B-6: SOOP's chat follows the app proxy (CONNECT tunnel).
    SiteIds.soop: () => SoopDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.yy: YyDanmakuConnection.new,
    SiteIds.acfun: () => AcfunDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.picarto: () => PicartoDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.twitcasting: () => TwitcastingDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.missevan: () => MissevanDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.kilakila: () => KilakilaDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.niconico: () => NiconicoDanmakuConnection(site: sites.of(SiteIds.niconico) as NiconicoSite),
    SiteIds.showroom: () => ShowroomDanmakuConnection(proxy: proxy, connector: connector),
    SiteIds.chzzk: () => ChzzkDanmakuConnection(http: http, proxy: proxy, connector: connector),
    // B-13: "显示全部聊天" is read when the room connects.
    SiteIds.youtube: () => YouTubeDanmakuConnection(http: http, allChat: settings.get(Settings.youtubeShowAllChat)),
    SiteIds.bigo: () => BigoDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.pandaLive: () => PandaLiveDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.fc2Live: () => Fc2LiveDanmakuConnection(http: http, proxy: proxy),
    SiteIds.steamBroadcast: () => SteamBroadcastDanmakuConnection(http: http),
    SiteIds.jdLive: () => JdLiveDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.kugouLive: () => KugouLiveDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.baiduLive: () => BaiduLiveDanmakuConnection(http: http),
    SiteIds.sixRoom: () => SixRoomDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.lookLive: () => LookLiveDanmakuConnection(http: http, proxy: proxy, connector: connector),
    SiteIds.seventeenLive: () => SeventeenLiveDanmakuConnection(http: http, proxy: proxy, connector: connector),
  });
}

/// UPGRADES B-2: send the danmaku handshake's User-Agent without dart:io's
/// `Dart/<version> (dart:io)` prefix. Off until verified on an Android
/// phone (3.x saw a custom direct client stall the handshake there); build
/// with `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` to try it.
const bool plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA');

/// The handshake of the danmaku sockets that use dart:io: null (the
/// default) unless [plainDanmakuUserAgent] is on. YY and FC2 keep their own.
SocketConnector? danmakuHandshake({bool plain = plainDanmakuUserAgent}) => plain
    ? (endpoint, {required headers, required protocols, required route, required connectTimeout}) => connectIoSocket(
        endpoint,
        headers: headers,
        protocols: protocols,
        route: route,
        connectTimeout: connectTimeout,
        plainUserAgent: true,
      )
    : null;

/// Moves 3.x's per-broadcast follows to the streamer (M9
/// `IdentityMigration`; UPGRADES 17-1, 23-1, Douyin room_id → web_rid):
/// niconico and YouTube resolve the streamer, Douyin re-reads the room by
/// its long room id. A failure keeps the room as it is and is retried on the
/// next start.
RoomIdentityResolver identityResolver(SiteRegistry sites) => (room) async {
  LiveRoom moved(String roomId, String link) => LiveRoom(platform: room.platform, roomId: roomId, link: link);
  switch (room.platform) {
    case SiteIds.niconico:
      final id = await (sites.of(SiteIds.niconico) as NiconicoSite).resolveRoomId(room.roomId);
      return moved(id, NiconicoApi.watchUrl(id));
    case SiteIds.youtube:
      final id = await (sites.of(SiteIds.youtube) as YouTubeSite).resolveRoomId(room.roomId);
      return moved(id, YouTubeApi.roomLink(id));
    case SiteIds.douyin:
      return await (sites.of(SiteIds.douyin) as DouyinSite).getRoomDetailForRefresh(roomId: room.roomId);
  }
  return null;
};
