import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// How long the splash page waits for the first follow check before home
/// (3.x `app_pages.dart`: a bounded part of the launch transition).
const Duration splashFollowWait = Duration(milliseconds: 350);

/// How long after start the Bilibili login is checked (3.x
/// `BiliBiliAccountService.initialLoadDelay`).
const Duration bilibiliCheckDelay = Duration(seconds: 1);

/// What the app starts once its first frame is up (3.x started these with
/// its services, in every window): the first check of every follow, the
/// exit timer, the timed cover refresh, Android 17's local-network
/// permission for a LAN proxy, the display mode, and one second later the
/// Bilibili login check.
final class AppStartup {
  /// Creates the start-up over [_ref]'s providers.
  new(this._ref);

  final Ref _ref;
  Timer? _bilibili;
  CoverRefreshTimer? _covers;
  LocalNetworkGuard? _localNetwork;
  bool _started = false;

  /// The first check of every follow once started; the splash page waits for
  /// it, at most [splashFollowWait].
  static Future<void>? followCheck;

  /// Starts the work once.
  void start() {
    if (_started) return;
    _started = true;
    final store = _ref.read(storeProvider);
    AutoExitTimer.instance.attach(store.settings);
    _covers = CoverRefreshTimer(store.settings)..start();
    if (Platform.isAndroid) _localNetwork = LocalNetworkGuard(store.settings)..start();
    unawaited(DisplayMode.refresh());
    followCheck = _ref.read(favoriteControllerProvider).firstCheck;
    _bilibili = Timer(
      bilibiliCheckDelay,
      () => unawaited(
        verifyBilibiliLogin(actions: _ref.read(accountActionsProvider), verify: _ref.read(accountVerifierProvider)),
      ),
    );
  }

  /// Stops what is still waiting.
  void dispose() {
    _bilibili?.cancel();
    unawaited(_covers?.dispose());
    unawaited(_localNetwork?.dispose());
    if (_started) {
      AutoExitTimer.instance.detach();
      followCheck = null;
    }
  }
}

/// The app's start-up (one per app).
final Provider<AppStartup> appStartupProvider = Provider((ref) {
  final startup = AppStartup(ref);
  ref.onDispose(startup.dispose);
  return startup;
});

/// Checks the stored Bilibili login (3.x `BiliBiliAccountService.loadUserInfo`,
/// the account page's check): remembers the uid of a valid one, signs an
/// expired one out and says so, and says when the check failed. Nothing
/// happens without a cookie, or when the cookie changed meanwhile.
Future<void> verifyBilibiliLogin({required AccountActions actions, required AccountVerifier verify}) async {
  final cookie = actions.cookieOf(SiteIds.bilibili);
  if (cookie.isEmpty) return;
  try {
    final identity = await verify(SiteIds.bilibili, cookie);
    if (actions.cookieOf(SiteIds.bilibili) != cookie) return;
    if (identity.uid case final uid?) await actions.rememberBilibiliUid(uid);
  } on NeedsLogin {
    if (actions.cookieOf(SiteIds.bilibili) != cookie) return;
    AppNavigator.toast(i18n('bilibili_login_expired'));
    await actions.signOut(SiteIds.bilibili);
  } on Object catch (error, stack) {
    log('Bilibili login check failed', name: 'Startup', error: error, stackTrace: stack);
    if (actions.cookieOf(SiteIds.bilibili) == cookie) AppNavigator.toast(i18n('bilibili_user_info_failed'));
  }
}
