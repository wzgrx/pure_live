import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// How the page can tell what a stored cookie is worth.
enum AccountCheckKind {
  /// Asks the platform who is signed in (Bilibili, Douyin).
  online,

  /// Douyu's session token, its end and the renewal pair.
  douyu,

  /// Twitch's chat login (`auth-token` and `login`).
  twitch,

  /// Huya's account id (`yyuid`).
  huya,

  /// Nothing to check: the cookie is stored as it is.
  none,
}

/// One platform of the account page (3.x had one cookie page per platform).
final class AccountPlatform {
  /// Creates the entry.
  const new({
    required this.id,
    required this.website,
    this.route,
    this.check = AccountCheckKind.none,
    this.overseas = false,
    this.hintKey,
    this.tipKey,
    this.nameKey,
    this.usedByRequests = true,
  });

  /// Platform id (`SiteIds`).
  final String id;

  /// The cookie page's route; null for a platform 3.x had no page for
  /// (opened as `RoutePath.kSettingsAccount` with the id as argument).
  final String? route;

  /// How the stored cookie is checked.
  final AccountCheckKind check;

  /// Listed under the overseas platforms.
  final bool overseas;

  /// The platform's own input hint; null uses the generic one.
  final String? hintKey;

  /// The platform's own instructions; null uses the generic ones.
  final String? tipKey;

  /// The account pages' own name key (docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览 c5: "SOOP",
  /// "网易CC"); null uses the platform list's `site_<id>`. The words are the
  /// same as the list's since both were unified on 3.x's and the platforms'
  /// own spelling.
  final String? nameKey;

  /// Where the user signs in on the web.
  final Uri website;

  /// Whether the adapters send the cookie today (CC only stores it until
  /// the signed-in danmaku join is verified, UPGRADES C-22).
  final bool usedByRequests;

  /// The platform's name: the account pages' own, else the app's
  /// ([platformName]).
  String get name => nameKey == null ? platformName(id) : i18n(nameKey!);

  /// The input hint.
  String get hint => hintKey == null ? i18n('cookie_hint', args: {'name': name}) : i18n(hintKey!);

  /// The instructions above the input.
  String get tip => tipKey == null ? i18n('cookie_tip', args: {'name': name}) : i18n(tipKey!);
}

/// The platforms with an account entry, in the page's order.
///
/// The cookie is read by these adapters (M12 `buildSiteRegistry`); CC is
/// listed so its cookie can be stored for UPGRADES C-22. Platforms whose
/// adapters take no cookie (CHZZK, AcFun, ...) have no entry.
final List<AccountPlatform> accountPlatforms = [
  AccountPlatform(
    id: SiteIds.bilibili,
    route: RoutePath.kBiliBiliWebLogin,
    check: AccountCheckKind.online,
    hintKey: 'account_bilibili_cookie_hint',
    tipKey: 'account_bilibili_cookie_tip',
    website: Uri.https('passport.bilibili.com', '/login'),
  ),
  AccountPlatform(
    id: SiteIds.douyu,
    route: RoutePath.kDouyuAccountCookie,
    check: AccountCheckKind.douyu,
    hintKey: 'douyu_cookie_hint',
    website: Uri.https('www.douyu.com', '/'),
  ),
  AccountPlatform(
    id: SiteIds.huya,
    route: RoutePath.kHuyaCookie,
    check: AccountCheckKind.huya,
    website: Uri.https('www.huya.com', '/'),
  ),
  AccountPlatform(
    id: SiteIds.douyin,
    route: RoutePath.kDouyinCookie,
    check: AccountCheckKind.online,
    website: Uri.https('live.douyin.com', '/'),
  ),
  AccountPlatform(id: SiteIds.kuaishou, route: RoutePath.kKuaishouCookie, website: Uri.https('live.kuaishou.com', '/')),
  AccountPlatform(id: SiteIds.yy, route: RoutePath.kYyCookie, website: Uri.https('www.yy.com', '/')),
  AccountPlatform(
    id: SiteIds.cc,
    nameKey: 'account_site_cc',
    website: Uri.https('cc.163.com', '/'),
    usedByRequests: false,
  ),
  AccountPlatform(
    id: SiteIds.twitch,
    route: RoutePath.kTwitchCookie,
    check: AccountCheckKind.twitch,
    overseas: true,
    hintKey: 'twitch_cookie_hint',
    tipKey: 'twitch_cookie_tip',
    website: Uri.https('www.twitch.tv', '/'),
  ),
  AccountPlatform(
    id: SiteIds.soop,
    route: RoutePath.kSoop,
    nameKey: 'account_site_soop',
    overseas: true,
    hintKey: 'soop_cookie_hint',
    tipKey: 'soop_cookie_tip',
    website: Uri.https('www.sooplive.co.kr', '/'),
  ),
];

/// The entry of platform [id], or null.
AccountPlatform? accountPlatformOf(String id) {
  final key = id.trim().toLowerCase();
  for (final platform in accountPlatforms) {
    if (platform.id == key) return platform;
  }
  return null;
}

/// The platform whose cookie page [path] is. `RoutePath.kDouyuCookie` is
/// 3.x's misnamed alias of the Douyin page and stays one.
AccountPlatform? accountPlatformForRoute(String path) {
  if (path == RoutePath.kDouyuCookie) return accountPlatformOf(SiteIds.douyin);
  for (final platform in accountPlatforms) {
    if (platform.route == path) return platform;
  }
  return null;
}
