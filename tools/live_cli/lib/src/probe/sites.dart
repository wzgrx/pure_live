import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// Creates the adapter for a platform id, or null when v4 has none yet.
typedef SiteFactory = Object Function(LiveHttp http);

/// Adapters available to the command-line tools; grows as phase 4 lands them.
final Map<String, SiteFactory> siteFactories = {
  '17live': SeventeenliveSite.new,
  'acfun': AcfunSite.new,
  'baidulive': BaiduLiveSite.new,
  'bigo': BigoSite.new,
  'bilibili': BilibiliSite.new,
  'cc': CcSite.new,
  'chzzk': ChzzkSite.new,
  'douyin': DouyinSite.new,
  'douyu': DouyuSite.new,
  'fc2live': Fc2LiveSite.new,
  'huya': HuyaSite.new,
  'inke': InkeSite.new,
  'jdlive': JdLiveSite.new,
  'kilakila': KilakilaSite.new,
  'kuaishou': KuaishouSite.new,
  'kugoulive': KugouLiveSite.new,
  'liveme': LiveMeSite.new,
  'looklive': LookLiveSite.new,
  'missevan': MissevanSite.new,
  'niconico': NiconicoSite.new,
  'pandalive': PandaliveSite.new,
  'picarto': PicartoSite.new,
  'showroom': ShowroomSite.new,
  'sixroom': SixRoomSite.new,
  'soop': SoopSite.new,
  'steambroadcast': SteamBroadcastSite.new,
  'tiktok': TikTokSite.new,
  'twitcasting': TwitcastingSite.new,
  'twitch': TwitchSite.new,
  'weibo': WeiboSite.new,
  'xiaohongshu': XiaohongshuSite.new,
  'youtube': YouTubeSite.new,
  'yy': YySite.new,
};
