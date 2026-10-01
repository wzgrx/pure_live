import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';

/// Bilibili's sign-in page (3.x `BiliBiliWebLoginController`).
final Uri bilibiliPassportLogin = Uri.parse('https://passport.bilibili.com/login');

/// The phone User-Agent 3.x opened the page with (the SMS form is on the
/// mobile page).
const String bilibiliLoginUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

/// Whether [uri] is where the sign-in lands (the main site, 3.x).
bool isBilibiliHome(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'www.bilibili.com' || host == 'm.bilibili.com' || host == 'bilibili.com';
}

/// The cookie header from the WebView's cookies (names in order, no
/// duplicates).
String cookieHeader(Iterable<({String name, String value})> cookies) {
  final seen = <String>{};
  return [
    for (final cookie in cookies)
      if (cookie.name.isNotEmpty && seen.add(cookie.name)) '${cookie.name}=${cookie.value}',
  ].join('; ');
}

/// Bilibili's web (SMS or password) login in the app (route
/// `RoutePath.kBiliBiliWebLogin`, 3.x `BiliBiliWebLoginPage`): the passport
/// page with a phone User-Agent; when it lands on the main site the
/// WebView's cookies are checked and stored like the QR login's. The title
/// bar switches to the QR code. Earlier Bilibili cookies of the WebView are
/// removed first, so a signed-out account is not picked up again.
class BilibiliWebLoginView extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<BilibiliWebLoginView> createState() => _BilibiliWebLoginViewState();
}

class _BilibiliWebLoginViewState extends ConsumerState<BilibiliWebLoginView> {
  late final Future<void> _cleared = _clearCookies();
  bool _saving = false;

  static final List<WebUri> _domains = [
    WebUri('https://www.bilibili.com'),
    WebUri('https://passport.bilibili.com'),
    WebUri('https://m.bilibili.com'),
  ];

  Future<void> _clearCookies() async {
    final cookies = CookieManager.instance();
    for (final url in _domains) {
      try {
        await cookies.deleteCookies(url: url, domain: '.bilibili.com');
        await cookies.deleteCookies(url: url);
      } on Object {
        // Nothing stored yet.
      }
    }
  }

  Future<void> _page(Uri uri) async {
    if (_saving || !isBilibiliHome(uri)) return;
    setState(() => _saving = true);
    final found = <({String name, String value})>[];
    for (final url in _domains) {
      try {
        for (final cookie in await CookieManager.instance().getCookies(url: url)) {
          found.add((name: cookie.name, value: '${cookie.value}'));
        }
      } on Object {
        // Read what the other domains have.
      }
    }
    final error = await _complete(cookieHeader(found));
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) AppNavigator.toast(i18n(error));
  }

  /// Checks and stores the cookie (the QR login's rules): one the platform
  /// says signs in nobody is not stored; one that cannot be checked now is.
  Future<String?> _complete(String cookie) async {
    final value = cleanPastedCookie(cookie);
    if (!value.contains('SESSDATA=')) return 'qr_cookie_missing';
    final actions = ref.read(accountActionsProvider);
    AccountCheck result;
    try {
      final identity = await ref.read(accountVerifierProvider)(SiteIds.bilibili, value);
      result = AccountVerified(identity.name, uid: identity.uid);
    } on Object catch (error) {
      result = accountCheckFailure(error);
    }
    if (result is AccountRejected) return 'bilibili_login_verification_failed';
    await actions.save(SiteIds.bilibili, value);
    if (result case AccountVerified(:final uid?)) await actions.rememberBilibiliUid(uid);
    AppNavigator.toast(switch (result) {
      AccountVerified(:final name) => i18n('account_saved_signed_in', args: {'name': name}),
      _ => i18n('bilibili_user_info_failed'),
    });
    if (mounted) Navigator.of(context).maybePop(true);
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(i18n('bilibili_login')),
      actions: [
        TextButton(
          onPressed: () => unawaited(AppNavigator.offAndToNamed<void>(RoutePath.kBiliBiliQRLogin)),
          child: Text(i18n('qr_login')),
        ),
      ],
      bottom: _saving
          ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
          : null,
    ),
    body: FutureBuilder<void>(
      future: _cleared,
      builder: (context, snapshot) => snapshot.connectionState != ConnectionState.done
          ? const Center(child: CircularProgressIndicator())
          : InAppWebPage(
              initial: bilibiliPassportLogin,
              userAgent: bilibiliLoginUserAgent,
              onPage: (uri) => unawaited(_page(uri)),
            ),
    ),
  );
}
