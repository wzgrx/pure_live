import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// Creates the adapter for a platform id, or null when v4 has none yet.
typedef SiteFactory = Object Function(LiveHttp http);

/// Adapters available to the command-line tools; grows as phase 4 lands them.
final Map<String, SiteFactory> siteFactories = {
  'bilibili': BilibiliSite.new,
  'cc': CcSite.new,
  'douyin': DouyinSite.new,
  'douyu': DouyuSite.new,
  'huya': HuyaSite.new,
  'kuaishou': KuaishouSite.new,
};
