import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// Creates the adapter for a platform id, or null when v4 has none yet.
typedef SiteFactory = Object Function(LiveHttp http);

/// Adapters available to the command-line tools; grows as phase 4 lands them.
final Map<String, SiteFactory> siteFactories = {
  'baidulive': BaiduLiveSite.new,
  'bilibili': BilibiliSite.new,
  'douyin': DouyinSite.new,
  'douyu': DouyuSite.new,
  'huya': HuyaSite.new,
  'jdlive': JdLiveSite.new,
  'kuaishou': KuaishouSite.new,
  'kugoulive': KugouLiveSite.new,
  'liveme': LiveMeSite.new,
  'looklive': LookLiveSite.new,
  'sixroom': SixRoomSite.new,
  'steambroadcast': SteamBroadcastSite.new,
  'weibo': WeiboSite.new,
};
