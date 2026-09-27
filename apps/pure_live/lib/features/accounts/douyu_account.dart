import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Saves what the Douyu editor holds (spec/sites/douyu.md §8.4) and says what
/// happened. [pasted] is a page cookie or the passport request's cookie;
/// [typedLtp0] and [typedDid] are the two extra fields (blank: taken from
/// the paste).
///
/// - A passport cookie (renewal fields, no session) only stores LTP0 and the
///   device id: it is not a login, and its fields make play requests fail.
/// - A cookie without a session never replaces a stored login.
/// - A login cookie is stored with the time it was saved (§8.1 seven days).
Future<String> saveDouyuInput(
  AccountStore store, {
  required String pasted,
  required String typedLtp0,
  required String typedDid,
  required DateTime now,
}) async {
  final cookie = normalizeCookie(pasted);
  final ltp0 = _blank(typedLtp0) ?? DouyuSession.field(cookie, DouyuSession.longTermName);
  final did = _blank(typedDid) ?? DouyuSession.field(cookie, DouyuSession.deviceIdName);
  final stored = store.cookie('douyu');
  final storedLogin = stored != null && DouyuSession.sessionToken(stored) != null;
  if (cookie.isEmpty) {
    if (ltp0 == null && did == null) return t.accounts.nothingToSave;
    await store.saveDouyu(ltp0: ltp0, did: did);
    return t.accounts.douyuKeysSaved;
  }
  if (DouyuSession.isPassportCookie(cookie)) {
    await store.saveDouyu(ltp0: ltp0, did: did);
    return storedLogin ? t.accounts.passportKept : t.accounts.passportNeedsLogin;
  }
  if (DouyuSession.sessionToken(cookie) == null && storedLogin) {
    await store.saveDouyu(ltp0: ltp0, did: did);
    return t.accounts.noLoginKept;
  }
  await store.saveDouyu(cookie: cookie, ltp0: ltp0, did: did, savedAt: now);
  return t.accounts.savedWith(summary: accountSummary('douyu', store, const AccountUnchecked(), now: now));
}

/// "立即续期" (spec/sites/douyu.md §8.4): renews the stored login with the
/// stored LTP0 and device id right away, so the user learns now whether they
/// work, and says what happened.
Future<String> renewDouyuNow(AccountStore store, DouyuRenewer renew, {required DateTime now}) async {
  final cookie = store.cookie('douyu');
  if (cookie == null) return t.accounts.noDouyuCookie;
  final keys = DouyuSession.credentials(cookie, storedLtp0: store.douyuLtp0, storedDid: store.douyuDid);
  final ltp0 = keys.ltp0;
  final did = keys.did;
  if (ltp0 == null || did == null) return t.accounts.renewMissingKeys;
  if (DouyuSession.sessionToken(cookie) == null) return t.accounts.renewNoLogin;
  try {
    final renewed = await renew(cookie: cookie, ltp0: ltp0, did: did);
    if (renewed == null) return t.accounts.renewNoResult;
    await store.saveDouyu(cookie: renewed, savedAt: now);
    final end = DouyuSession.expiry(renewed, savedAt: now);
    return end == null ? t.accounts.renewed : t.accounts.renewedUntil(end: formatAccountTime(end));
  } on Object catch (error) {
    return t.accounts.renewFailed(reason: describeError(error).title);
  }
}

String? _blank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
