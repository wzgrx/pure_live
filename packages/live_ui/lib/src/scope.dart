import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The words the shared widgets show (3.x translation keys in brackets).
///
/// The package has no translations of its own: the app passes the current
/// language's words through [LiveUiScope]. [zh] and [en] are 3.x's texts.
@immutable
final class LiveUiStrings {
  /// Creates the words.
  const new({
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.errorTitle,
    required this.errorSubtitle,
    required this.retry,
    required this.audiencePopularity,
    required this.audienceOnline,
    required this.audienceTotal,
    required this.audienceFollowers,
    required this.audienceCount,
    required this.audienceWaiting,
    required this.replay,
    required this.verifying,
    required this.delete,
    this.offline = '未开播',
    this.cancel = '取消',
    this.close = '关闭',
    this.gotIt = '知道了',
    this.refreshPull = '下拉刷新',
    this.refreshRelease = '松开刷新',
    this.refreshRefreshing = '正在刷新...',
    this.refreshSucceeded = '刷新成功',
    this.refreshFailed = '刷新失败',
    this.refreshLastTime = '上次刷新时间 {time}',
    this.loading = '加载中...',
    this.loadFailed = '加载失败',
    this.offlineTitle = '没有网络连接',
    this.offlineSubtitle = '检查网络后重试；连上网络后会自动刷新',
    this.restrictedTitle = '需要登录账号',
    this.restrictedSubtitle = '该平台数据已被风控隐藏，请登录账号后重试',
    this.login = '前往登录',
    this.details = '详情',
    this.copy = '复制',
    this.copied = '已复制到剪贴板',
  });

  /// Simplified Chinese (3.x `zh.json`).
  static const zh = LiveUiStrings(
    emptyTitle: '暂无数据',
    emptySubtitle: '这里空空如也，什么都没有发现。',
    errorTitle: '网络请求错误',
    errorSubtitle: '请检查您的网络连接或稍后再试',
    retry: '重新加载',
    audiencePopularity: '热度',
    audienceOnline: '在线',
    audienceTotal: '累计观看',
    audienceFollowers: '粉丝',
    audienceCount: '观看',
    audienceWaiting: '待刷新',
    replay: '录播',
    verifying: '正在核验',
    delete: '删除',
  );

  /// English (3.x `en.json`).
  static const en = LiveUiStrings(
    emptyTitle: 'No Data Available',
    emptySubtitle: 'It looks quite empty here, nothing was found.',
    errorTitle: 'Network Request Error',
    errorSubtitle: 'Please check your network connection or try again later',
    retry: 'Retry',
    audiencePopularity: 'Heat',
    audienceOnline: 'Online',
    audienceTotal: 'Total views',
    audienceFollowers: 'Followers',
    audienceCount: 'Views',
    audienceWaiting: 'Pending',
    replay: 'REPLAY',
    verifying: 'Verifying',
    delete: 'Delete',
    offline: 'Offline',
    cancel: 'Cancel',
    close: 'Close',
    gotIt: 'Got it',
    refreshPull: 'Pull to refresh',
    refreshRelease: 'Release to refresh',
    refreshRefreshing: 'Refreshing...',
    refreshSucceeded: 'Refreshed',
    refreshFailed: 'Refresh failed',
    refreshLastTime: 'Last refreshed {time}',
    loading: 'Loading...',
    loadFailed: 'Loading failed',
    offlineTitle: 'No network connection',
    offlineSubtitle: 'Check the network and retry; it reloads by itself once connected',
    restrictedTitle: 'Login Required',
    restrictedSubtitle: 'This platform data is hidden, please log in to your account and try again',
    login: 'Go to Login',
    details: 'Details',
    copy: 'Copy',
    copied: 'Copied to clipboard',
  );

  /// Empty state title (`status_empty_title`).
  final String emptyTitle;

  /// Empty state text (`status_empty_subtitle`).
  final String emptySubtitle;

  /// Error state title (`status_error_title`).
  final String errorTitle;

  /// Error state text (`status_error_subtitle`).
  final String errorSubtitle;

  /// Retry button (`status_retry_button`).
  final String retry;

  /// Audience: popularity (`audience_popularity`).
  final String audiencePopularity;

  /// Audience: viewers online (`audience_online`).
  final String audienceOnline;

  /// Audience: total views (`audience_total`).
  final String audienceTotal;

  /// Audience: followers (`audience_followers`).
  final String audienceFollowers;

  /// Audience of unknown meaning (`audience_count`).
  final String audienceCount;

  /// Audience not known yet (`audience_waiting`).
  final String audienceWaiting;

  /// Replay badge (`replay`).
  final String replay;

  /// Live status being checked (`favorite_status_verifying`).
  final String verifying;

  /// Delete (`delete`).
  final String delete;

  /// The mark of a room that is not live, on its cover (U.4a c4,
  /// `offline_room_title`).
  final String offline;

  /// The dialogs' "取消" (`cancel`).
  final String cancel;

  /// "关闭": a panel's ✕, a toast's ✕ (`close`).
  final String close;

  /// The one button of a message dialog, "知道了" (`got_it`, U.1d c14).
  final String gotIt;

  /// The refresh header while pulled (`refresh_pull_to_refresh`; 3.x's
  /// header said "上拉刷新", U.1c P19).
  final String refreshPull;

  /// The refresh header once releasing refreshes
  /// (`refresh_release_to_refresh`).
  final String refreshRelease;

  /// The refresh header while refreshing (`refresh_refreshing`).
  final String refreshRefreshing;

  /// The refresh header after a refresh (`refresh_succeeded`).
  final String refreshSucceeded;

  /// The refresh header after a failed refresh (`refresh_failed`).
  final String refreshFailed;

  /// The refresh header's second line; `{time}` is the last refresh's
  /// `H:mm` (`refresh_last_updated_at`).
  final String refreshLastTime;

  /// The line under a loading spinner (`refresh_loading`).
  final String loading;

  /// The title of a failed load (`refresh_load_failed`, U.1c c4).
  final String loadFailed;

  /// The offline state's title (`status_offline_title`).
  final String offlineTitle;

  /// The offline state's text (`status_offline_subtitle`).
  final String offlineSubtitle;

  /// The restricted state's title (`login_required_title`).
  final String restrictedTitle;

  /// The restricted state's text (`login_required_subtitle`).
  final String restrictedSubtitle;

  /// The restricted state's button (`go_to_login`).
  final String login;

  /// The button and the title of a failure's raw text (`details`).
  final String details;

  /// Copies a text (`copy`).
  final String copy;

  /// Said after a copy (`copied_to_clipboard`).
  final String copied;
}

/// Request headers for an image address (3.x `networkImageHeaders`: some
/// image hosts refuse requests without the platform's Referer).
typedef ImageHeadersResolver = Map<String, String>? Function(String url);

/// What the app tells the shared widgets (3.x read these from the settings
/// singleton): words, the loading style, and how network images load.
@immutable
final class LiveUiConfig {
  /// Creates the configuration.
  const new({
    this.strings = LiveUiStrings.zh,
    this.loadingStyle = 'default',
    this.loadingColor,
    this.imageCacheManager,
    this.imageHeaders,
    this.imageCacheEpoch = 0,
  });

  /// The words.
  final LiveUiStrings strings;

  /// The loading animation's key (`loadingStyle`, see `LoadingStyles.keys`);
  /// an unknown key shows the default.
  final String loadingStyle;

  /// The loading animation's colour (`loadingStyleColorSwitch`); null takes
  /// the widget's icon colour, then the theme's primary colour.
  final Color? loadingColor;

  /// Disk cache of covers and avatars; null uses cached_network_image's
  /// default manager.
  final BaseCacheManager? imageCacheManager;

  /// Request headers per image address.
  final ImageHeadersResolver? imageHeaders;

  /// Bumped when the user clears the image cache, so cached entries are
  /// fetched again under a new key (`imageCacheEpoch`).
  final int imageCacheEpoch;

  /// The cache key of [url]: the address itself, plus `#epoch` once the
  /// cache has been cleared.
  String imageCacheKey(String url) => imageCacheEpoch == 0 ? url : '$url#$imageCacheEpoch';

  /// A copy with the given fields replaced.
  LiveUiConfig copyWith({
    LiveUiStrings? strings,
    String? loadingStyle,
    Color? loadingColor,
    BaseCacheManager? imageCacheManager,
    ImageHeadersResolver? imageHeaders,
    int? imageCacheEpoch,
  }) => LiveUiConfig(
    strings: strings ?? this.strings,
    loadingStyle: loadingStyle ?? this.loadingStyle,
    loadingColor: loadingColor ?? this.loadingColor,
    imageCacheManager: imageCacheManager ?? this.imageCacheManager,
    imageHeaders: imageHeaders ?? this.imageHeaders,
    imageCacheEpoch: imageCacheEpoch ?? this.imageCacheEpoch,
  );

  @override
  bool operator ==(Object other) =>
      other is LiveUiConfig &&
      other.strings == strings &&
      other.loadingStyle == loadingStyle &&
      other.loadingColor == loadingColor &&
      other.imageCacheManager == imageCacheManager &&
      other.imageHeaders == imageHeaders &&
      other.imageCacheEpoch == imageCacheEpoch;

  @override
  int get hashCode =>
      Object.hash(strings, loadingStyle, loadingColor, imageCacheManager, imageHeaders, imageCacheEpoch);
}

/// Hands a [LiveUiConfig] to the shared widgets below it; put it once above
/// the app's navigator (or in its `builder`).
class LiveUiScope extends InheritedWidget {
  /// Provides [config] to [child].
  const new({required this.config, required super.child, super.key});

  /// The configuration.
  final LiveUiConfig config;

  /// The configuration in scope, or the defaults (Chinese words, default
  /// loading style) when there is none.
  static LiveUiConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiveUiScope>()?.config ?? const LiveUiConfig();

  @override
  bool updateShouldNotify(LiveUiScope oldWidget) => config != oldWidget.config;
}
