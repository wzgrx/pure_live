import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/core/sites.dart';

/// What to tell the user about a failure: the UI decides by type, never by
/// message text (ADR 0010, rule 6; principles rule 3).
({String title, String message, bool retryable}) describeError(Object error) => switch (error) {
  NotFound(site: 'iptv') => (title: '频道不存在', message: '播放列表里已经没有这个频道，可能改名或被删除了。', retryable: false),
  NotFound() => (title: '直播间不存在', message: '房间号可能已经失效，或者主播换了房间。', retryable: false),
  NeedsLogin() => (title: '需要登录', message: '这个内容要登录平台账号后才能看，平台账号登录会在后续预览版开放。', retryable: false),
  RateLimited() => (title: '请求太频繁', message: '平台限制了访问频率，等一会儿再试。', retryable: true),
  RiskControl() => (title: '被平台风控拦截', message: '平台暂时拒绝了请求，稍后重试，或换个网络。', retryable: true),
  RegionBlocked() => (title: '当前地区看不了', message: '平台限制了这个地区的访问，可以在设置里给这个平台配置代理。', retryable: false),
  StreamUnavailable() => (title: '拿不到直播流', message: '平台暂时没有给出可以播放的线路，稍后再试。', retryable: true),
  UnsupportedLink() => (title: '不支持这个链接', message: '目前支持斗鱼、虎牙、哔哩哔哩、抖音和快手的直播间链接。', retryable: false),
  ApiChanged() => (title: '平台接口变了', message: '需要更新应用才能继续使用这个平台。', retryable: true),
  NetworkFailure() || TransportFailure() => (title: '网络连接失败', message: '检查网络或代理设置后重试。', retryable: true),
  // F-FAV-08: follows and history of other platforms stay; they just cannot open.
  PlatformUnsupported(:final platform) => (
    title: '平台暂不支持',
    message: '${platformName(platform)}已下线或这个版本还不支持，关注和观看历史会一直保留。',
    retryable: false,
  ),
  _ => (title: '出错了', message: '$error', retryable: true),
};
