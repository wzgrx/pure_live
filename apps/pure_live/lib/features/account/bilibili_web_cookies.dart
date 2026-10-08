import 'dart:developer';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/shared/in_app_web.dart';

/// The Bilibili addresses whose in-app browser cookies make up a login.
final List<WebUri> bilibiliWebDomains = [
  WebUri('https://www.bilibili.com'),
  WebUri('https://passport.bilibili.com'),
  WebUri('https://m.bilibili.com'),
];

/// Removes Bilibili's cookies from the in-app browser, so a signed-out
/// account is not picked up again by the web login (3.x
/// `BiliBiliAccountService._clearBrowserCookies` removed every site's;
/// only Bilibili's here). Nothing happens without a WebView; failures are
/// logged and never thrown.
Future<void> clearBilibiliWebCookies() async {
  if (!InAppWeb.available) return;
  for (final url in bilibiliWebDomains) {
    try {
      final cookies = CookieManager.instance();
      await cookies.deleteCookies(url: url, domain: '.bilibili.com');
      await cookies.deleteCookies(url: url);
    } on Object catch (error) {
      // The other domains are still cleared.
      log('Clearing the Bilibili web cookies of ${url.host} failed: $error', name: 'AccountPage');
    }
  }
}
