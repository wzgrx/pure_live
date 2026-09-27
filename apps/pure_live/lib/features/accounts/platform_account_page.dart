import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/core/web/web_prompt.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/bilibili_qr_panel.dart';
import 'package:pure_live_app/features/accounts/cookie_editor.dart';
import 'package:pure_live_app/features/accounts/douyu_account.dart';
import 'package:pure_live_app/features/accounts/web_login.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Location of one platform's account page.
String accountLocation(String platform) => '/me/accounts/${Uri.encodeComponent(platform)}';

/// Location of a platform's web sign-in (full screen, outside the shell).
String webLoginLocation(String platform) => '/web-login/${Uri.encodeComponent(platform)}';

/// Asks before signing out; true when the user confirmed.
Future<bool> confirmSignOut(BuildContext context, String platform, {required bool clearsBrowser}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.accounts.signOutTitle(name: platformNames[platform] ?? platform)),
        content: Text(clearsBrowser ? t.accounts.signOutBodyBrowser : t.accounts.signOutBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.accounts.signOut)),
        ],
      ),
    ) ??
    false;

/// One platform's account (F-ACC-01): status, 校验, 退出 (confirmed), and the
/// ways to sign in: B 站 QR code and web page, Douyu's cookie with its
/// renewal keys, a pasted cookie everywhere.
class PlatformAccountPage extends ConsumerStatefulWidget {
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  ConsumerState<PlatformAccountPage> createState() => _PlatformAccountPageState();
}

class _PlatformAccountPageState extends ConsumerState<PlatformAccountPage> {
  bool _qr = false;
  bool _renewing = false;

  String get _platform => widget.platform;

  @override
  void initState() {
    super.initState();
    // The account's name comes from the platform; ask once on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final check = ref.read(accountCheckProvider(_platform));
      if (check is AccountUnchecked && ref.read(accountStoreProvider).cookie(_platform) != null) {
        unawaited(ref.read(accountCheckProvider(_platform).notifier).verify());
      }
    });
  }

  // A new message replaces the one on screen instead of queueing behind it.
  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut() async {
    final engine = ref.read(webEngineProvider);
    final clearsBrowser = webLoginSpecs.containsKey(_platform) && engine != null;
    if (!await confirmSignOut(context, _platform, clearsBrowser: clearsBrowser)) return;
    await ref.read(accountStoreProvider).signOut(_platform);
    // spec/sites/bilibili.md §8.2: signing out also clears the browser's
    // cookies, so the web sign-in does not come back as the old account.
    if (clearsBrowser) {
      try {
        await engine.clearCookies();
      } on Object {
        // The stored cookie is gone either way.
      }
    }
    if (mounted) _toast(t.accounts.signedOutToast);
  }

  Future<void> _renew() async {
    setState(() => _renewing = true);
    final message = await renewDouyuNow(
      ref.read(accountStoreProvider),
      ref.read(douyuRenewerProvider),
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() => _renewing = false);
    _toast(message);
  }

  Future<void> _webLogin() async {
    if (!await ensureWebAvailable(context, ref) || !mounted) return;
    final done = await context.push<bool>(webLoginLocation(_platform));
    if (done ?? false) setState(() => _qr = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRevisionProvider);
    final store = ref.watch(accountStoreProvider);
    final check = ref.watch(accountCheckProvider(_platform));
    final signedIn = store.cookie(_platform) != null;
    final verifiable = ref.watch(accountVerifierProvider(_platform)) != null;
    final douyu = _platform == 'douyu' ? douyuStatus(store, DateTime.now()) : null;
    final web = webLoginSpecs.containsKey(_platform)
        ? ref.watch(webAvailabilityProvider).value ?? WebAvailability.unsupported
        : WebAvailability.unsupported;
    final name = platformNames[_platform] ?? _platform;
    return Scaffold(
      appBar: AppBar(title: Text(t.accounts.accountTitle(name: name))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              ListTile(
                leading: PlatformLogo(platformId: _platform, size: Sizes.iconLg),
                title: Text(name),
                subtitle: Text(accountSummary(_platform, store, check, now: DateTime.now())),
              ),
              if (signedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  child: Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s2,
                    children: [
                      if (verifiable)
                        OutlinedButton(
                          onPressed: check is AccountChecking
                              ? null
                              : () => ref.read(accountCheckProvider(_platform).notifier).verify(),
                          child: Text(t.accounts.verify),
                        ),
                      if (douyu != null && douyu.renewable)
                        OutlinedButton(onPressed: _renewing ? null : _renew, child: Text(t.accounts.renewNow)),
                      TextButton(onPressed: _signOut, child: Text(t.accounts.signOutAction)),
                    ],
                  ),
                ),
              if (_platform == 'bilibili') ...[
                SettingsHeader(signedIn ? t.accounts.switchAccount : t.accounts.signIn),
                if (_qr)
                  // Keyed: the list above it grows when the sign-in lands.
                  BilibiliQrPanel(key: const ValueKey('bilibili-qr'), onDone: () => _toast(t.accounts.signedInToast))
                else
                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(t.accounts.qrSignIn),
                    subtitle: Text(t.accounts.qrSignInSubtitle),
                    onTap: () => setState(() => _qr = true),
                  ),
                if (web != WebAvailability.unsupported)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(t.accounts.webSignIn),
                    subtitle: Text(t.accounts.webSignInSubtitle),
                    onTap: _webLogin,
                  ),
              ],
              SettingsHeader(
                _platform == 'bilibili'
                    ? t.accounts.manualCookie
                    : (signedIn ? t.accounts.replaceCookie : t.accounts.enterCookie),
              ),
              CookieEditor(platform: _platform),
              Padding(padding: const EdgeInsets.all(Space.s4), child: Text(t.accounts.storageNoteFull)),
            ],
          ),
        ),
      ),
    );
  }
}
