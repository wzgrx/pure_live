import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/pages/account/account_list_view.dart';
import 'package:pure_live/pages/account/account_platforms.dart';
import 'package:pure_live/pages/account/bilibili_qr_login.dart';
import 'package:pure_live/pages/account/bilibili_web_login.dart';
import 'package:pure_live/pages/account/douyu_cookie_view.dart';
import 'package:pure_live/pages/account/platform_cookie_view.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';

/// Accounts, the Bilibili login and the platform cookies (3.x
/// `lib/modules/account`).
///
/// Routes: `RoutePath.kSettingsAccount` (the list; with a platform id as
/// argument, that platform's cookie page), `RoutePath.kBiliBiliQRLogin`,
/// `RoutePath.kBiliBiliWebLogin`, `RoutePath.kHuyaCookie`,
/// `RoutePath.kDouyuAccountCookie`, `RoutePath.kDouyinCookie`,
/// `RoutePath.kDouyuCookie` (3.x's alias of the Douyin page),
/// `RoutePath.kTwitchCookie`, `RoutePath.kYyCookie`, `RoutePath.kSoop`,
/// `RoutePath.kKuaishouCookie`.
///
/// Cookies are sealed in `LiveStore.secrets` (M9); the adapters read them
/// through the app's `CookieVault`, so a change applies to the next request.
class AccountPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    final path = route.path;
    if (path == RoutePath.kBiliBiliQRLogin) return const BilibiliQrLoginView();
    // The web (SMS) login needs the in-app browser; without it the route
    // shows the cookie page with the explanation.
    if (path == RoutePath.kBiliBiliWebLogin && InAppWeb.available) return const BilibiliWebLoginView();
    final platform = path == RoutePath.kSettingsAccount
        ? switch (route.arguments) {
            final String id => accountPlatformOf(id),
            _ => null,
          }
        : accountPlatformForRoute(path);
    if (platform == null) return const AccountListView();
    if (platform.id == SiteIds.douyu) return const DouyuCookieView();
    return PlatformCookieView(platform: platform, webLoginFallback: path == RoutePath.kBiliBiliWebLogin);
  }
}
