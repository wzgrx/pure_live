import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';

/// Builds a platform adapter on [http]; [proxy] is for the sockets some
/// adapters open themselves (niconico seats, FC2 controls).
typedef SiteFactory = LiveSite Function(LiveHttp http, ProxyPolicy proxy);

/// Builds a danmaku connection; [site] is the room's adapter (niconico's
/// connection needs it).
typedef DanmakuFactory = DanmakuConnection Function(LiveHttp http, ProxyPolicy proxy, LiveSite site);

/// The anonymous adapters of the 34 platforms, with the app's constructor
/// arguments (`apps/pure_live/lib/app/platforms.dart`, `buildSiteRegistry`)
/// at their defaults: an empty cookie vault, `preferH264` on, no Twitch
/// fallbacks (no Android TLS on a PC), and Kick's API on dart:io (refused by
/// Cloudflare; the patrol skips Kick).
Map<String, SiteFactory> siteFactories({CookieVault? cookies}) {
  final vault = cookies ?? MemoryCookieVault();
  return {
    SiteIds.bilibili: (http, _) => BilibiliSite(http, cookies: vault),
    SiteIds.douyu: (http, _) => DouyuSite(http, cookies: vault),
    SiteIds.huya: (http, _) => HuyaSite(http, cookies: vault),
    SiteIds.douyin: (http, _) => DouyinSite(http, cookies: vault),
    SiteIds.kuaishou: (http, _) => KuaishouSite(http, cookies: vault),
    SiteIds.cc: (http, _) => CcSite(http),
    SiteIds.twitch: (http, _) => TwitchSite(http, cookies: vault),
    SiteIds.soop: (http, _) => SoopSite(http, cookies: vault),
    SiteIds.yy: (http, _) => YySite(http, cookies: vault),
    SiteIds.acfun: (http, _) => AcfunSite(http),
    SiteIds.picarto: (http, _) => PicartoSite(http),
    SiteIds.twitcasting: (http, _) => TwitcastingSite(http),
    SiteIds.missevan: (http, _) => MissevanSite(http),
    SiteIds.inke: (http, _) => InkeSite(http),
    SiteIds.kilakila: (http, _) => KilakilaSite(http),
    SiteIds.xiaohongshu: (http, _) => XiaohongshuSite(http),
    SiteIds.niconico: (http, proxy) => NiconicoSite(http, proxy: proxy),
    SiteIds.weibo: (http, _) => WeiboSite(http),
    SiteIds.showroom: (http, _) => ShowroomSite(http),
    SiteIds.chzzk: (http, _) => ChzzkSite(http),
    SiteIds.kick: (http, _) => KickSite(http),
    SiteIds.liveMe: (http, _) => LiveMeSite(http),
    SiteIds.tiktok: (http, _) => TikTokSite(http),
    SiteIds.youtube: (http, _) => YouTubeSite(http),
    SiteIds.bigo: (http, _) => BigoSite(http),
    SiteIds.pandaLive: (http, _) => PandaLiveSite(http),
    SiteIds.fc2Live: (http, proxy) => Fc2LiveSite(http, proxy: proxy),
    SiteIds.steamBroadcast: (http, _) => SteamBroadcastSite(http),
    SiteIds.jdLive: (http, _) => JdLiveSite(http),
    SiteIds.kugouLive: (http, _) => KugouLiveSite(http),
    SiteIds.baiduLive: (http, _) => BaiduLiveSite(http),
    SiteIds.sixRoom: (http, _) => SixRoomSite(http),
    SiteIds.lookLive: (http, _) => LookLiveSite(http),
    SiteIds.seventeenLive: (http, _) => SeventeenLiveSite(http),
  };
}

/// The danmaku connections of the app's table (`buildDanmakuRegistry`) at
/// their default settings. Not listed (no danmaku): CC, Inke, Xiaohongshu,
/// Weibo, LiveMe, TikTok.
final Map<String, DanmakuFactory> danmakuFactories = {
  SiteIds.bilibili: (_, proxy, _) => BilibiliDanmakuConnection(proxy: proxy),
  SiteIds.douyu: (_, proxy, _) => DouyuDanmakuConnection(proxy: proxy),
  SiteIds.huya: (_, proxy, _) => HuyaDanmakuConnection(proxy: proxy),
  SiteIds.douyin: (_, proxy, _) => DouyinDanmakuConnection(proxy: proxy),
  SiteIds.kuaishou: (http, _, _) => KuaishouDanmakuConnection(http: http),
  SiteIds.twitch: (_, proxy, _) => TwitchDanmakuConnection(proxy: proxy),
  SiteIds.soop: (_, proxy, _) => SoopDanmakuConnection(proxy: proxy),
  SiteIds.yy: (_, _, _) => YyDanmakuConnection(),
  SiteIds.acfun: (_, proxy, _) => AcfunDanmakuConnection(proxy: proxy),
  SiteIds.picarto: (http, proxy, _) => PicartoDanmakuConnection(http: http, proxy: proxy),
  SiteIds.twitcasting: (http, proxy, _) => TwitcastingDanmakuConnection(http: http, proxy: proxy),
  SiteIds.missevan: (http, proxy, _) => MissevanDanmakuConnection(http: http, proxy: proxy),
  SiteIds.kilakila: (_, proxy, _) => KilakilaDanmakuConnection(proxy: proxy),
  SiteIds.niconico: (_, _, site) => NiconicoDanmakuConnection(site: site as NiconicoSite),
  SiteIds.showroom: (_, proxy, _) => ShowroomDanmakuConnection(proxy: proxy),
  SiteIds.chzzk: (http, proxy, _) => ChzzkDanmakuConnection(http: http, proxy: proxy),
  SiteIds.kick: (_, proxy, _) => KickDanmakuConnection(proxy: proxy),
  SiteIds.youtube: (http, _, _) => YouTubeDanmakuConnection(http: http),
  SiteIds.bigo: (http, proxy, _) => BigoDanmakuConnection(http: http, proxy: proxy),
  SiteIds.pandaLive: (http, proxy, _) => PandaLiveDanmakuConnection(http: http, proxy: proxy),
  SiteIds.fc2Live: (http, proxy, _) => Fc2LiveDanmakuConnection(http: http, proxy: proxy),
  SiteIds.steamBroadcast: (http, _, _) => SteamBroadcastDanmakuConnection(http: http),
  SiteIds.jdLive: (http, proxy, _) => JdLiveDanmakuConnection(http: http, proxy: proxy),
  SiteIds.kugouLive: (http, proxy, _) => KugouLiveDanmakuConnection(http: http, proxy: proxy),
  SiteIds.baiduLive: (http, _, _) => BaiduLiveDanmakuConnection(http: http),
  SiteIds.sixRoom: (http, proxy, _) => SixRoomDanmakuConnection(http: http, proxy: proxy),
  SiteIds.lookLive: (http, proxy, _) => LookLiveDanmakuConnection(http: http, proxy: proxy),
  SiteIds.seventeenLive: (http, proxy, _) => SeventeenLiveDanmakuConnection(http: http, proxy: proxy),
};

/// The proxy rules of a patrol: domestic platforms always direct, overseas
/// ones through [overseasProxy] when given (`FixedProxyPolicy(perSite: …)`).
FixedProxyPolicy patrolProxyPolicy({required Iterable<String> overseas, ProxyRoute? overseasProxy}) => FixedProxyPolicy(
  perSite: {
    if (overseasProxy != null)
      for (final site in overseas) site: overseasProxy,
  },
);

/// `host:port` as a proxy route; throws [FormatException] otherwise.
HttpProxyRoute parseProxy(String value) {
  final text = normalizeProxyHost(value);
  final colon = text.lastIndexOf(':');
  if (colon <= 0 || colon == text.length - 1) throw FormatException('Expected host:port', value);
  var host = text.substring(0, colon);
  if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);
  final port = int.tryParse(text.substring(colon + 1));
  if (port == null || !isValidProxyPort(port) || host.isEmpty) throw FormatException('Expected host:port', value);
  return HttpProxyRoute(host, port);
}
