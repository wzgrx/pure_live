import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';

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
    if (ltp0 == null && did == null) return '没有要保存的内容';
    await store.saveDouyu(ltp0: ltp0, did: did);
    return '已保存续期用的 LTP0 和 dy_did';
  }
  if (DouyuSession.isPassportCookie(cookie)) {
    await store.saveDouyu(ltp0: ltp0, did: did);
    return storedLogin
        ? '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did，原来的登录保留'
        : '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did。还要粘贴 www.douyu.com 页面的 Cookie 才算登录';
  }
  if (DouyuSession.sessionToken(cookie) == null && storedLogin) {
    await store.saveDouyu(ltp0: ltp0, did: did);
    return '粘贴的 Cookie 里没有登录信息，原来的登录保留';
  }
  await store.saveDouyu(cookie: cookie, ltp0: ltp0, did: did, savedAt: now);
  return '已保存。${accountSummary('douyu', store, const AccountUnchecked(), now: now)}';
}

/// "立即续期" (spec/sites/douyu.md §8.4): renews the stored login with the
/// stored LTP0 and device id right away, so the user learns now whether they
/// work, and says what happened.
Future<String> renewDouyuNow(AccountStore store, DouyuRenewer renew, {required DateTime now}) async {
  final cookie = store.cookie('douyu');
  if (cookie == null) return '还没有保存斗鱼 Cookie';
  final keys = DouyuSession.credentials(cookie, storedLtp0: store.douyuLtp0, storedDid: store.douyuDid);
  final ltp0 = keys.ltp0;
  final did = keys.did;
  if (ltp0 == null || did == null) return '缺少 LTP0 或 dy_did，没法续期';
  if (DouyuSession.sessionToken(cookie) == null) return 'Cookie 里没有登录信息，没法续期';
  try {
    final renewed = await renew(cookie: cookie, ltp0: ltp0, did: did);
    if (renewed == null) return '斗鱼没有返回新的登录信息，续期没有生效';
    await store.saveDouyu(cookie: renewed, savedAt: now);
    final end = DouyuSession.expiry(renewed, savedAt: now);
    return end == null ? '已续期' : '已续期，新的有效期到 ${formatAccountTime(end)}';
  } on Object catch (error) {
    return '续期失败：${describeError(error).title}';
  }
}

String? _blank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
