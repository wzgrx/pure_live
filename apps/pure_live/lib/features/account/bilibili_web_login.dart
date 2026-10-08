import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/bilibili_web_cookies.dart';
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
  late final Future<void> _cleared = clearBilibiliWebCookies();
  bool _saving = false;

  /// Why the last sign-in did not finish (the red bar, 3.x).
  String? _error;

  Future<void> _page(Uri uri) async {
    if (_saving || !isBilibiliHome(uri)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final found = <({String name, String value})>[];
    for (final url in bilibiliWebDomains) {
      try {
        for (final cookie in await CookieManager.instance().getCookies(url: url)) {
          found.add((name: cookie.name, value: '${cookie.value}'));
        }
      } on Object {
        // Read what the other domains have.
      }
    }
    String? error;
    try {
      error = await _complete(cookieHeader(found));
    } on Object catch (failure, stack) {
      // Never left at verifying (K02.2).
      log('Bilibili web login failed', name: 'AccountPage', error: failure, stackTrace: stack);
      error = secretSaveFailedKey;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  /// Checks and stores the cookie (the QR login's rules): one the platform
  /// says signs in nobody is not stored; one that cannot be checked now is.
  /// A failed store comes back as the red bar's reason (K02.2), so the page
  /// never stays at verifying.
  Future<String?> _complete(String cookie) async {
    final value = cleanPastedCookie(cookie);
    if (!value.contains('SESSDATA=')) return 'qr_cookie_missing';
    final stored = await storeBilibiliLogin(ref.read(accountActionsProvider), ref.read(accountVerifierProvider), value);
    if (stored.refused case final refused?) return refused;
    AppNavigator.toast(switch (stored.check) {
      AccountVerified(:final name) => i18n('account_saved_signed_in', args: {'name': name}),
      _ => i18n('account_saved_unverified'),
    });
    // `pop`, not `maybePop`: the in-app web page's PopScope refuses
    // `maybePop` and turns it into a step back in the page's history.
    if (mounted) Navigator.of(context).pop(true);
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      void toQr() => unawaited(AppNavigator.offAndToNamed<void>(RoutePath.kBiliBiliQRLogin));
      final error = _error;
      return Scaffold(
        appBar: AppBar(
          title: Text(i18n('bilibili_login')),
          actions: [
            // 3.x: the words, only the icon when narrow.
            if (constraints.maxWidth < 520)
              IconButton(
                key: const ValueKey('bilibili-web-qr'),
                tooltip: i18n('qr_login'),
                onPressed: toQr,
                icon: const Icon(AppIcons.qrCode),
              )
            else
              TextButton.icon(
                key: const ValueKey('bilibili-web-qr'),
                onPressed: toQr,
                icon: const Icon(AppIcons.qrCode, size: 18),
                label: Text(i18n('qr_login')),
              ),
          ],
        ),
        body: Stack(
          children: [
            FutureBuilder<void>(
              future: _cleared,
              builder: (context, snapshot) => snapshot.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : InAppWebPage(
                      initial: bilibiliPassportLogin,
                      userAgent: bilibiliLoginUserAgent,
                      onPage: (uri) => unawaited(_page(uri)),
                    ),
            ),
            if (_saving)
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('bilibili-web-verifying'),
                  color: scheme.scrim.withValues(alpha: 0.32),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                          const SizedBox(height: 12),
                          Text(i18n('account_verifying'), style: context.textStyles.t14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (error != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 28,
                child: Material(
                  key: const ValueKey('bilibili-web-error'),
                  color: scheme.errorContainer,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      children: [
                        Icon(AppIcons.failed, size: 20, color: scheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            i18n(error),
                            style: context.textStyles.t13.copyWith(color: scheme.onErrorContainer, height: 1.35),
                          ),
                        ),
                        IconButton(
                          tooltip: i18n('close'),
                          color: scheme.onErrorContainer,
                          onPressed: () => setState(() => _error = null),
                          icon: const Icon(AppIcons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
