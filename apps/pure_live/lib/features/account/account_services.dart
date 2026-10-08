import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/bilibili_web_cookies.dart';

/// Who a cookie signs in as.
typedef AccountIdentity = ({String name, int? uid});

/// Asks a platform who [cookie] signs in as; `NeedsLogin` when it signs in
/// nobody (3.x `BiliBiliAccountService.loadUserInfo`,
/// `DouyinSite.getUserInfoByCookie`).
typedef AccountVerifier = Future<AccountIdentity> Function(String site, String cookie);

/// The Bilibili QR login calls (M4.01 `BilibiliSite.qrCode`, `qrPoll`).
abstract interface class BilibiliQrApi {
  /// A new code: the key to poll with and the URL to show.
  Future<({String key, Uri url})> qrCode();

  /// One poll of [key]; the cookie is set once the phone confirmed.
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key);
}

/// Renews a Douyu login with the passport pair (M4.02
/// `DouyuSite.renewSession`); null when nothing was renewed.
typedef DouyuRenewer = Future<String?> Function({required String cookie, required String ltp0, required String did});

/// The account checks of the platforms (tests replace it).
final Provider<AccountVerifier> accountVerifierProvider = Provider<AccountVerifier>((ref) {
  final sites = ref.watch(sitesProvider);
  return (site, cookie) async => switch (sites.of(site)) {
    final BilibiliSite bilibili => await bilibili.account(cookie: cookie).then((a) => (name: a.name, uid: a.uid)),
    final DouyinSite douyin => (name: await douyin.account(cookie: cookie), uid: null),
    _ => throw UnsupportedError('$site has no account check'),
  };
});

/// The Bilibili QR login (tests replace it).
final Provider<BilibiliQrApi> bilibiliQrApiProvider = Provider<BilibiliQrApi>(
  (ref) => _SiteQrApi(ref.watch(sitesProvider).of(SiteIds.bilibili) as BilibiliSite),
);

/// Douyu's renewal (tests replace it).
final Provider<DouyuRenewer> douyuRenewerProvider = Provider<DouyuRenewer>((ref) {
  final douyu = ref.watch(sitesProvider).of(SiteIds.douyu) as DouyuSite;
  return douyu.renewSession;
});

/// The page's clock, for Douyu's session ends (tests replace it).
final Provider<DateTime Function()> accountClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Removes Bilibili's cookies from the in-app browser on sign-out (tests
/// replace it).
final Provider<Future<void> Function()> bilibiliWebCookieClearerProvider = Provider<Future<void> Function()>(
  (ref) => clearBilibiliWebCookies,
);

/// The account writes over the app's store.
final Provider<AccountActions> accountActionsProvider = Provider<AccountActions>(
  (ref) => AccountActions(
    ref.watch(storeProvider),
    now: ref.watch(accountClockProvider),
    clearBilibiliWeb: ref.watch(bilibiliWebCookieClearerProvider),
  ),
);

final class _SiteQrApi implements BilibiliQrApi {
  new(this._site);

  final BilibiliSite _site;

  @override
  Future<({String key, Uri url})> qrCode() => _site.qrCode();

  @override
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key) => _site.qrPoll(key);
}

/// The account writes, all in `LiveStore` (3.x `CookieSettingsController`
/// and `BiliBiliAccountService`).
final class AccountActions {
  /// Creates the writer over [store]; [clearBilibiliWeb] removes Bilibili's
  /// cookies from the in-app browser on sign-out.
  new(this.store, {DateTime Function()? now, Future<void> Function()? clearBilibiliWeb})
    : _now = now ?? DateTime.now,
      _clearBilibiliWeb = clearBilibiliWeb ?? clearBilibiliWebCookies;

  /// The store.
  final LiveStore store;

  final DateTime Function() _now;
  final Future<void> Function() _clearBilibiliWeb;

  /// The stored cookie of [site] ('' when none).
  String cookieOf(String site) => store.secrets.cookieFor(site) ?? '';

  /// Whether the stored cookie of [site] could not be opened on this device.
  bool unreadable(String site) => store.secrets.unreadable.contains(SecretRefs.cookie(site));

  /// What is stored for [site].
  AccountSnapshot snapshot(String site) {
    if (site != SiteIds.douyu) return AccountSnapshot(cookie: cookieOf(site), unreadable: unreadable(site));
    final login = douyuLogin;
    return AccountSnapshot(
      cookie: cookieOf(site),
      unreadable: unreadable(site),
      douyuLtp0: login.ltp0,
      douyuDid: login.did,
      douyuSavedAt: login.savedAt,
    );
  }

  /// Stores [cookie] for [site]. A new Bilibili cookie forgets the uid of
  /// the old one until it is verified (3.x `_clearLocalAccountState`).
  Future<void> save(String site, String cookie) async {
    final value = normalizeCookie(cookie);
    final changed = value != cookieOf(site);
    await store.secrets.setCookie(site, value);
    if (changed && site == SiteIds.bilibili) await store.settings.set(Settings.bilibiliUid, 0);
  }

  /// Remembers the verified Bilibili uid (the danmaku uid when the cookie
  /// has no `DedeUserID`).
  Future<void> rememberBilibiliUid(int uid) async {
    if (store.settings.get(Settings.bilibiliUid) != uid) await store.settings.set(Settings.bilibiliUid, uid);
  }

  /// Signs out of [site]: the cookie and what belongs to it (the Bilibili
  /// uid and the in-app browser's Bilibili cookies, 3.x `logout`; Douyu's
  /// save time and renewal pair).
  Future<void> signOut(String site) async {
    await store.secrets.writeAll({
      SecretRefs.cookie(site): null,
      if (site == SiteIds.douyu) ...{SecretRefs.douyuLtp0: null, SecretRefs.douyuDid: null},
    });
    if (site == SiteIds.bilibili) {
      await store.settings.set(Settings.bilibiliUid, 0);
      try {
        await _clearBilibiliWeb();
      } on Object catch (error) {
        // Signed out all the same (3.x only said so).
        log('Clearing the Bilibili web login failed: $error', name: 'AccountPage');
      }
    }
    if (site == SiteIds.douyu) await store.settings.set(Settings.douyuCookieSavedAt, 0);
  }

  /// Douyu's renewal key, device id and save time.
  ({String? ltp0, String? did, DateTime? savedAt}) get douyuLogin {
    final seconds = store.settings.get(Settings.douyuCookieSavedAt);
    return (
      ltp0: store.secrets.read(SecretRefs.douyuLtp0),
      did: store.secrets.read(SecretRefs.douyuDid),
      savedAt: seconds > 0 ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000) : null,
    );
  }

  /// Stores Douyu's login [cookie] with the pair, and the save time when the
  /// cookie changed (3.x reset it on every save, which moved the assumed
  /// seven-day end of an unchanged cookie).
  Future<void> saveDouyu({required String cookie, required String? ltp0, required String? did}) async {
    final changed = cookie != cookieOf(SiteIds.douyu);
    await store.secrets.writeAll({
      SecretRefs.cookie(SiteIds.douyu): cookie,
      SecretRefs.douyuLtp0: ltp0,
      SecretRefs.douyuDid: did,
    });
    if (changed) {
      await store.settings.set(Settings.douyuCookieSavedAt, cookie.isEmpty ? 0 : _now().millisecondsSinceEpoch ~/ 1000);
    }
  }

  /// Stores Douyu's renewal pair only.
  Future<void> saveDouyuPair({required String? ltp0, required String? did}) =>
      store.secrets.writeAll({SecretRefs.douyuLtp0: ltp0, SecretRefs.douyuDid: did});

  /// Stores a renewed Douyu login and its new save time.
  Future<void> saveDouyuRenewed(String cookie) async {
    await store.secrets.setCookie(SiteIds.douyu, cookie);
    await store.settings.set(Settings.douyuCookieSavedAt, _now().millisecondsSinceEpoch ~/ 1000);
  }
}

/// Checks a cookie a Bilibili login (QR code, web page) just issued and
/// stores it: one the platform says signs in nobody is not stored, one that
/// cannot be checked right now is (the passport just issued it). `refused`
/// is the translation key of why nothing was stored, also when the device's
/// secure storage failed (K02.2: the pages stop instead of waiting forever).
Future<({AccountCheck check, String? refused})> storeBilibiliLogin(
  AccountActions actions,
  AccountVerifier verify,
  String cookie,
) async {
  AccountCheck result;
  try {
    final identity = await verify(SiteIds.bilibili, cookie);
    result = AccountVerified(identity.name, uid: identity.uid);
  } on Object catch (error) {
    result = accountCheckFailure(error);
  }
  if (result is AccountRejected) return (check: result, refused: 'bilibili_login_verification_failed');
  try {
    await actions.save(SiteIds.bilibili, cookie);
  } on Object catch (error, stack) {
    // The error is the cipher's, never the cookie.
    log('Storing the Bilibili login failed', name: 'AccountPage', error: error, stackTrace: stack);
    return (check: result, refused: secretSaveFailedKey);
  }
  if (result case AccountVerified(:final uid?)) await actions.rememberBilibiliUid(uid);
  return (check: result, refused: null);
}

/// What the pages say when the device's secure storage could not store a
/// login (K02.2).
const String secretSaveFailedKey = 'account_secret_save_failed';
