import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';

/// The account a platform says the stored cookie belongs to (F-ACC-01).
@immutable
final class AccountIdentity {
  /// Creates an identity.
  const new({required this.name, this.uid});

  /// Display name.
  final String name;

  /// Platform user id, when the platform reports one.
  final String? uid;

  @override
  bool operator ==(Object other) => other is AccountIdentity && other.name == name && other.uid == uid;

  @override
  int get hashCode => Object.hash(name, uid);
}

/// Checks the stored cookie with the platform's user-info endpoint; throws
/// `NeedsLogin` when it is not signed in.
typedef AccountVerifier = Future<AccountIdentity> Function();

/// The verifier of a platform from the adapters' existing user-info
/// endpoints (F-ACC-01): B 站 `x/member/web/account` (spec/sites/bilibili.md
/// §8.2) and 抖音 `webcast/user/me/` (spec/sites/douyin.md §8). Null for the
/// others, whose accounts show "已填 Cookie".
final ProviderFamily<AccountVerifier?, String> accountVerifierProvider = Provider.family<AccountVerifier?, String>((
  ref,
  platform,
) {
  final site = ref.watch(sitesProvider)[platform]?.raw;
  return switch (site) {
    final BilibiliSite bilibili => () async {
      final account = await bilibili.account();
      return AccountIdentity(name: account.name, uid: '${account.uid}');
    },
    final DouyinSite douyin => () async => AccountIdentity(name: await douyin.accountName()),
    _ => null,
  };
});

/// What B 站 sign-in needs (spec/sites/bilibili.md §8.2–§8.4).
abstract interface class BilibiliLoginApi {
  /// §8.3 a new QR code: the key to poll and the https address to encode.
  Future<({String key, Uri url})> qrCode();

  /// §8.3 one poll of [key]; the cookie comes with `confirmed`.
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key);

  /// §8.2 who [cookie] belongs to; `NeedsLogin` when it is not signed in.
  Future<AccountIdentity> account(String cookie);
}

final class _SiteBilibiliLogin implements BilibiliLoginApi {
  const new(this._site);

  final BilibiliSite _site;

  @override
  Future<({String key, Uri url})> qrCode() => _site.qrCode();

  @override
  Future<({BilibiliQrState state, String? cookie})> qrPoll(String key) => _site.qrPoll(key);

  @override
  Future<AccountIdentity> account(String cookie) async {
    final account = await _site.account(cookie: cookie);
    return AccountIdentity(name: account.name, uid: '${account.uid}');
  }
}

/// B 站 sign-in through the adapter.
final bilibiliLoginProvider = Provider<BilibiliLoginApi>(
  (ref) => _SiteBilibiliLogin(ref.watch(sitesProvider)['bilibili']!.raw as BilibiliSite),
);

/// Renews a Douyu login cookie at the passport (spec/sites/douyu.md §8.2);
/// null when nothing was renewed.
typedef DouyuRenewer = Future<String?> Function({required String cookie, required String ltp0, required String did});

/// Douyu renewal through the adapter.
final douyuRenewerProvider = Provider<DouyuRenewer>(
  (ref) => (ref.watch(sitesProvider)['douyu']!.raw as DouyuSite).renewSession,
);

/// The two account values that are settings rather than secrets
/// (live_store registry "Accounts").
abstract interface class AccountSettings {
  /// When the Douyu cookie was saved; null when unknown.
  DateTime? get douyuSavedAt;

  /// Records when the Douyu cookie was saved; null clears it.
  Future<void> setDouyuSavedAt(DateTime? at);

  /// Records the verified B 站 uid; 0 when signed out.
  Future<void> setBilibiliUid(int uid);
}

final class _StoreAccountSettings implements AccountSettings {
  const new(this._settings);

  final SettingsStore _settings;

  @override
  DateTime? get douyuSavedAt {
    final seconds = _settings.get(Settings.douyuCookieSavedAt);
    return seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  @override
  Future<void> setDouyuSavedAt(DateTime? at) =>
      _settings.set(Settings.douyuCookieSavedAt, at == null ? 0 : at.millisecondsSinceEpoch ~/ 1000);

  @override
  Future<void> setBilibiliUid(int uid) => _settings.set(Settings.bilibiliUid, uid);
}

/// Account settings in the store.
final accountSettingsProvider = Provider<AccountSettings>(
  (ref) => _StoreAccountSettings(ref.watch(storeProvider).settings),
);

/// Cookies and renewal keys of every platform, always through the encrypted
/// secret store (constitution rule 8); values never reach the interface.
final class AccountStore {
  /// Creates the store.
  const new(this._secrets, this._settings);

  final SecretStore _secrets;
  final AccountSettings _settings;

  /// The stored cookie of [platform], or null when signed out.
  String? cookie(String platform) => _secrets.cookieFor(platform);

  /// Emits a platform id when its cookie or renewal keys change.
  Stream<String> get changes => _secrets.cookieChanges;

  /// Douyu's separately stored LTP0 (spec/sites/douyu.md §8.4).
  String? get douyuLtp0 => _secrets.read(SecretRefs.douyuLtp0);

  /// Douyu's separately stored device id.
  String? get douyuDid => _secrets.read(SecretRefs.douyuDid);

  /// When the Douyu cookie was saved.
  DateTime? get douyuSavedAt => _settings.douyuSavedAt;

  /// Stores [cookie] (normalised) for [platform]; [uid] is B 站's verified id.
  Future<void> saveCookie(String platform, String cookie, {int? uid}) async {
    await _secrets.write(SecretRefs.cookie(platform), normalizeCookie(cookie));
    if (platform == 'bilibili' && uid != null) await _settings.setBilibiliUid(uid);
  }

  /// Stores Douyu's login [cookie] with its save time, and the renewal keys
  /// when given (§8.4); a null [cookie] keeps the stored login.
  Future<void> saveDouyu({String? cookie, String? ltp0, String? did, DateTime? savedAt}) async {
    // The save time first: watchers rebuild on the cookie change.
    if (cookie != null) await _settings.setDouyuSavedAt(savedAt);
    await _secrets.writeAll({
      if (cookie != null) SecretRefs.cookie('douyu'): normalizeCookie(cookie),
      if (ltp0 != null) SecretRefs.douyuLtp0: ltp0.trim(),
      if (did != null) SecretRefs.douyuDid: did.trim(),
    });
  }

  /// Signs [platform] out: its cookie and every renewal key go.
  Future<void> signOut(String platform) async {
    if (platform == 'douyu') await _settings.setDouyuSavedAt(null);
    if (platform == 'bilibili') await _settings.setBilibiliUid(0);
    await _secrets.writeAll({
      SecretRefs.cookie(platform): null,
      if (platform == 'douyu') ...{SecretRefs.douyuLtp0: null, SecretRefs.douyuDid: null},
    });
  }
}

/// Counts account changes, so widgets that show account state rebuild when
/// a cookie or renewal key is saved or removed.
class AccountRevision extends Notifier<int> {
  @override
  int build() {
    final subscription = ref.watch(accountStoreProvider).changes.listen((_) => state++);
    ref.onDispose(subscription.cancel);
    return 0;
  }
}

/// The account change counter.
final accountRevisionProvider = NotifierProvider<AccountRevision, int>(AccountRevision.new);

/// The account store of this run.
final accountStoreProvider = Provider<AccountStore>(
  (ref) => AccountStore(ref.watch(secretStoreProvider), ref.watch(accountSettingsProvider)),
);
