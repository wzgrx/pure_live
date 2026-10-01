/// Route paths, unchanged from 3.x (`lib/routes/route_path.dart`), so links
/// and the pages' calls keep working.
abstract final class RoutePath {
  /// Splash page.
  static const kSplash = '/splash';

  /// Home.
  static const kInitial = '/home';

  /// Follows.
  static const kFavorite = '/favorite';

  /// Followed areas.
  static const kFavoriteAreas = '/favoriteAreas';

  /// Popular.
  static const kPopular = '/popular';

  /// Areas.
  static const kAreas = '/areas';

  /// The rooms of an area (arguments: site, area).
  static const kAreaRooms = '/area_rooms';

  /// The live room (argument: the room).
  static const kLivePlay = '/live_play';

  /// Multi-view.
  static const kMultiview = '/multiview';

  /// Search.
  static const kSearch = '/search';

  /// Settings.
  static const kSettings = '/settings';

  /// Backup and restore.
  static const kBackup = '/backup';

  /// LAN sync.
  static const kRemoteSync = '/remote_sync';

  /// About.
  static const kAbout = '/about';

  /// Version history.
  static const kVersionHistory = '/version_history';

  /// Watch history.
  static const kHistory = '/history';

  /// Donate.
  static const kDonate = '/donate';

  /// Mine.
  static const kMine = '/mine';

  /// Sign in.
  static const kSignIn = '/sign_in';

  /// User management.
  static const kUserManage = '/user_manage';

  /// Password change.
  static const kUpdatePassword = '/update_password';

  /// Danmaku block list.
  static const kSettingsDanmuShield = '/shield';

  /// Platform list.
  static const kSettingsHotAreas = '/hot_areas';

  /// Accounts.
  static const kSettingsAccount = '/settings_account';

  /// Bilibili QR login.
  static const kBiliBiliQRLogin = '/bilibili_qr_login';

  /// Bilibili web login.
  static const kBiliBiliWebLogin = '/bilibili_web_login';

  /// Web view.
  static const kWebview = '/webview_all';

  /// Toolbox (open a link).
  static const kToolbox = '/tool_box';

  /// Huya cookie.
  static const kHuyaCookie = '/huya_cookie';

  /// Douyu cookie.
  static const kDouyuAccountCookie = '/douyu_account_cookie';

  /// Douyin cookie.
  static const kDouyinCookie = '/douyin_cookie';

  /// Twitch cookie.
  static const kTwitchCookie = '/twitch_cookie';

  /// YY cookie.
  static const kYyCookie = '/yy_cookie';

  /// SOOP cookie.
  static const kSoop = '/soop';

  /// WebDAV.
  static const kWebDavPage = '/web_dav_page';

  /// Historical alias that opened the Douyin cookie page in older releases.
  static const kDouyuCookie = '/douyu_cookie';

  /// Kuaishou cookie.
  static const kKuaishouCookie = '/kuaishou_cookie';

  /// Version (update) page.
  static const kVersionPage = '/version_page';

  /// Recording centre (3.x spelling kept).
  static const kRecordPage = '/record_mannager';

  /// Recording settings.
  static const kRecordSettings = '/record_settings';

  /// Recording history.
  static const kRecordHistory = '/record_history';

  /// Web search.
  static const kWebSearch = '/web_search';

  /// IPTV.
  static const kIptv = '/iptv';

  /// Follow groups.
  static const kSettingsTags = '/settingTags';

  /// 设置 → 本地用户与互动 (U.2k; 3.x pushed the page without a route).
  static const kLocalInteraction = '/local_interaction';
}
