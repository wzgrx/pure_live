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

/// The playback proxy settings as live_net's [ProxyPolicy] (3.x
/// `PlaybackProxyPolicy` over `enableProxy`, `proxyHost`, `proxyPort`; F.0a):
/// the route of the live room's video streams (mpv's `http-proxy`, the
/// playback relay's upstream requests). Separate from the app proxy
/// ([SettingsProxyPolicy]) as in 3.x: switched off, streams go direct even
/// when the app proxy is on. Recording keeps the app proxy (3.x routed its
/// relays through `enableAppProxy`). Read at every request.
final class PlaybackProxyPolicy implements ProxyPolicy {
  /// Creates the policy over [settings].
  new(this.settings);

  /// The settings.
  final SettingsStore settings;

  @override
  ProxyRoute routeFor(String site, Uri url) => proxyRouteFrom(
    enabled: settings.get(Settings.enableProxy),
    host: settings.get(Settings.proxyHost),
    port: settings.get(Settings.proxyPort),
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

/// Whether YY plays stream-manager's FLV first, mobile HLS standing in
/// (UPGRADES 6-1, E06.3): lower latency, the platform's names (蓝光, 高清,
/// 流畅), two CDN lines per quality, URLs renewed by their lease. Not a
/// setting (E02.1); `--dart-define=YY_FLV_FIRST=false` builds the mobile
/// HLS order for a side-by-side check on the phone.
const bool yyFlvFirst = bool.fromEnvironment('YY_FLV_FIRST', defaultValue: true);

/// What the platform adapters share.
final class PlatformDeps {
  /// Creates the dependencies.
  new({
    required this.http,
    required this.proxy,
    required this.cookies,
    required this.store,
    this.twitchFallbacks = const [],
    this.kickApi,
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

  /// Extra GraphQL transports of Twitch (Android's system TLS, then the
  /// headless WebView).
  final List<LiveHttp> twitchFallbacks;

  /// The transport of Kick's API (Android's system TLS): Cloudflare refuses
  /// dart:io's TLS on kick.com. Null where there is none (Windows, until a
  /// WinHTTP channel exists): Kick is then not registered (UPGRADES X-1).
  final LiveHttp? kickApi;

  /// The IPTV platform; null leaves IPTV out.
  final IptvSite? iptv;
}

/// The 33 platforms of 3.x, Kick (where [PlatformDeps.kickApi] exists) and
/// IPTV (3.x `Sites.supportSites`), each built on first use and then kept
/// (M3 `SiteRegistry`).
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
    SiteIds.yy: () => YySite(http, cookies: cookies, flvFirst: yyFlvFirst),
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
    if (deps.kickApi case final kickApi?) SiteIds.kick: () => KickSite(http, apiHttp: kickApi),
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
  final generic = danmakuHandshake();
  // Only the platforms on dart:io's handshake take the plain one (Q03.1).
  SocketConnector? connector(String site) => genericDanmakuHandshakeSites.contains(site) ? generic : null;
  return DanmakuRegistry({
    SiteIds.bilibili: () => BilibiliDanmakuConnection(proxy: proxy, connector: connector(SiteIds.bilibili)),
    SiteIds.douyu: () => DouyuDanmakuConnection(
      proxy: proxy,
      connector: connector(SiteIds.douyu),
      filterSuspectedAutomatedMessages: () => settings.get(Settings.filterDouyuSuspectedAutomatedMessages),
    ),
    SiteIds.huya: () => HuyaDanmakuConnection(proxy: proxy, connector: connector(SiteIds.huya)),
    // The room's DouyinDanmakuArgs carry `refresh` (B-5), set by DouyinSite.
    SiteIds.douyin: () => DouyinDanmakuConnection(proxy: proxy, connector: connector(SiteIds.douyin)),
    SiteIds.kuaishou: () => KuaishouDanmakuConnection(http: http),
    SiteIds.twitch: () => TwitchDanmakuConnection(proxy: proxy, connector: connector(SiteIds.twitch)),
    // B-6: SOOP's chat follows the app proxy (CONNECT tunnel). Its own
    // case-preserving handshake: its edge does not answer dart:io's
    // lower-case headers (Q03.1), so never the generic connector.
    SiteIds.soop: () => SoopDanmakuConnection(proxy: proxy),
    SiteIds.yy: YyDanmakuConnection.new,
    SiteIds.acfun: () => AcfunDanmakuConnection(proxy: proxy, connector: connector(SiteIds.acfun)),
    SiteIds.picarto: () => PicartoDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.picarto)),
    SiteIds.twitcasting: () =>
        TwitcastingDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.twitcasting)),
    SiteIds.missevan: () => MissevanDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.missevan)),
    SiteIds.kilakila: () => KilakilaDanmakuConnection(proxy: proxy, connector: connector(SiteIds.kilakila)),
    SiteIds.niconico: () => NiconicoDanmakuConnection(site: sites.of(SiteIds.niconico) as NiconicoSite),
    SiteIds.showroom: () => ShowroomDanmakuConnection(proxy: proxy, connector: connector(SiteIds.showroom)),
    SiteIds.chzzk: () => ChzzkDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.chzzk)),
    // M5.34: Kick's Pusher socket is not behind Kick's Cloudflare; dart:io works.
    SiteIds.kick: () => KickDanmakuConnection(proxy: proxy, connector: connector(SiteIds.kick)),
    // B-13: "显示全部聊天" is read at every connect (C01.6: a change reconnects).
    SiteIds.youtube: () =>
        YouTubeDanmakuConnection(http: http, allChatOf: () => settings.get(Settings.youtubeShowAllChat)),
    SiteIds.bigo: () => BigoDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.bigo)),
    SiteIds.pandaLive: () =>
        PandaLiveDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.pandaLive)),
    SiteIds.fc2Live: () => Fc2LiveDanmakuConnection(http: http, proxy: proxy),
    SiteIds.steamBroadcast: () => SteamBroadcastDanmakuConnection(http: http),
    SiteIds.jdLive: () => JdLiveDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.jdLive)),
    SiteIds.kugouLive: () =>
        KugouLiveDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.kugouLive)),
    SiteIds.baiduLive: () => BaiduLiveDanmakuConnection(http: http),
    SiteIds.sixRoom: () => SixRoomDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.sixRoom)),
    SiteIds.lookLive: () => LookLiveDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.lookLive)),
    SiteIds.seventeenLive: () =>
        SeventeenLiveDanmakuConnection(http: http, proxy: proxy, connector: connector(SiteIds.seventeenLive)),
  });
}

/// UPGRADES B-2: send the danmaku handshake's User-Agent without dart:io's
/// `Dart/<version> (dart:io)` prefix. Off until verified on an Android
/// phone (3.x saw a custom direct client stall the handshake there); build
/// with `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` to try it.
const bool plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA');

/// The platforms whose danmaku sockets shake hands through dart:io and so
/// take [danmakuHandshake]. Not here: SOOP and YY (their own case-preserving
/// handshake, `exact_websocket.dart`), FC2 (its own socket), and Kuaishou,
/// niconico, YouTube, Steam and Baidu (no WebSocket of ours to shake).
const Set<String> genericDanmakuHandshakeSites = {
  SiteIds.bilibili,
  SiteIds.douyu,
  SiteIds.huya,
  SiteIds.douyin,
  SiteIds.twitch,
  SiteIds.acfun,
  SiteIds.picarto,
  SiteIds.twitcasting,
  SiteIds.missevan,
  SiteIds.kilakila,
  SiteIds.showroom,
  SiteIds.chzzk,
  SiteIds.kick,
  SiteIds.bigo,
  SiteIds.pandaLive,
  SiteIds.jdLive,
  SiteIds.kugouLive,
  SiteIds.sixRoom,
  SiteIds.lookLive,
  SiteIds.seventeenLive,
};

/// The handshake of the danmaku sockets that use dart:io: null (the
/// default) unless [plainDanmakuUserAgent] is on; only for
/// [genericDanmakuHandshakeSites].
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
