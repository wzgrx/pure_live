import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/i18n/i18n.dart';

/// How a status reads: its colour and icon.
enum AccountTone {
  /// Nothing stored.
  idle,

  /// Signed in, or stored and usable.
  ok,

  /// A check is running.
  busy,

  /// Stored, but something is missing or could not be checked.
  warning,

  /// Stored, but it signs in nobody.
  error,
}

/// What the page says about one platform's login.
@immutable
final class AccountStatus {
  /// Creates the status.
  const new(this.text, {this.tone = AccountTone.idle, this.signedIn = false});

  /// The sentence shown.
  final String text;

  /// How it reads.
  final AccountTone tone;

  /// Whether the login counts as signed in (the sign-out button shows).
  final bool signedIn;

  @override
  bool operator ==(Object other) =>
      other is AccountStatus && other.text == text && other.tone == tone && other.signedIn == signedIn;

  @override
  int get hashCode => Object.hash(text, tone, signedIn);

  @override
  String toString() => 'AccountStatus($text, $tone, signedIn: $signedIn)';
}

/// The result of asking a platform who a cookie signs in as.
sealed class AccountCheck {
  const new();
}

/// The question is out.
final class AccountChecking extends AccountCheck {
  /// Creates the state.
  const new();
}

/// The cookie signs in [name] ([uid] on Bilibili).
final class AccountVerified extends AccountCheck {
  /// Creates the result.
  const new(this.name, {this.uid});

  /// The account's name.
  final String name;

  /// The account id, when the platform gives one.
  final int? uid;
}

/// The platform said the cookie signs in nobody (`NeedsLogin`).
final class AccountRejected extends AccountCheck {
  /// Creates the result.
  const new();
}

/// The question failed (network, a changed answer); the cookie stays.
final class AccountCheckFailed extends AccountCheck {
  /// Creates the result.
  const new();
}

/// What a check that ended with [error] means.
AccountCheck accountCheckFailure(Object error) =>
    error is NeedsLogin ? const AccountRejected() : const AccountCheckFailed();

/// The stored values one platform's status depends on.
@immutable
final class AccountSnapshot {
  /// Creates the snapshot.
  const new({this.cookie = '', this.unreadable = false, this.douyuLtp0, this.douyuDid, this.douyuSavedAt});

  /// The stored cookie ('' when none).
  final String cookie;

  /// The stored cookie could not be opened on this device.
  final bool unreadable;

  /// Douyu's separately stored renewal key.
  final String? douyuLtp0;

  /// Douyu's separately stored device id.
  final String? douyuDid;

  /// When Douyu's cookie was saved.
  final DateTime? douyuSavedAt;
}

/// The status of [platform] from what is stored and, for the platforms
/// checked online, the last [check] (3.x showed "logged in" for any
/// stored cookie).
AccountStatus accountStatus(
  AccountPlatform platform,
  AccountSnapshot stored, {
  required DateTime now,
  AccountCheck? check,
}) {
  final cookie = stored.cookie;
  if (cookie.isEmpty) {
    if (stored.unreadable) return AccountStatus(i18n('account_status_unreadable'), tone: AccountTone.error);
    // 3.x: "设置cookie", and "未登录" for Bilibili (docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览 c5).
    return AccountStatus(i18n('account_status_none'));
  }
  switch (platform.check) {
    case AccountCheckKind.online:
      return switch (check) {
        null || AccountChecking() => AccountStatus(i18n('account_verifying'), tone: AccountTone.busy, signedIn: true),
        AccountVerified(:final name) => AccountStatus(
          i18n('account_status_signed_in', args: {'name': name}),
          tone: AccountTone.ok,
          signedIn: true,
        ),
        AccountRejected() => AccountStatus(i18n('account_status_rejected'), tone: AccountTone.error, signedIn: true),
        AccountCheckFailed() => AccountStatus(
          i18n('account_status_check_failed'),
          tone: AccountTone.warning,
          signedIn: true,
        ),
      };
    case AccountCheckKind.douyu:
      final state = douyuSessionState(stored, now: now);
      return switch (state) {
        DouyuSessionState.none => AccountStatus(i18n('account_status_none')),
        DouyuSessionState.valid => AccountStatus(_douyuValid(stored), tone: AccountTone.ok, signedIn: true),
        DouyuSessionState.expiredRefreshable => AccountStatus(
          i18n('douyu_session_renewable'),
          tone: AccountTone.warning,
          signedIn: true,
        ),
        DouyuSessionState.guest ||
        DouyuSessionState.expired => AccountStatus(i18n('douyu_session_needs_cookie'), tone: AccountTone.error),
      };
    case AccountCheckKind.twitch:
      final chat = TwitchApi.chatLogin(cookie);
      return chat == null
          ? AccountStatus(i18n('account_status_twitch_no_chat'), tone: AccountTone.warning, signedIn: true)
          : AccountStatus(
              i18n('account_status_twitch_chat', args: {'login': chat.login}),
              tone: AccountTone.ok,
              signedIn: true,
            );
    case AccountCheckKind.huya:
      final uid = HuyaApi.viewerUidFromCookie(cookie);
      return uid == null
          ? AccountStatus(i18n('account_status_huya_no_uid'), tone: AccountTone.warning, signedIn: true)
          : AccountStatus(i18n('account_status_huya_uid', args: {'uid': '$uid'}), tone: AccountTone.ok, signedIn: true);
    case AccountCheckKind.none:
      return platform.usedByRequests
          ? AccountStatus(i18n('account_status_saved'), tone: AccountTone.ok, signedIn: true)
          : AccountStatus(i18n('account_status_stored_unused'), tone: AccountTone.warning, signedIn: true);
  }
}

/// The status card of a platform's own page: the list's [status], but an
/// empty one says what to do ("未设置：粘贴登录后的 Cookie", docs/TASKS.md/
/// U.10b c2).
AccountStatus accountPageStatus(AccountStatus status, AccountSnapshot stored) =>
    stored.cookie.isEmpty && !stored.unreadable && status.tone == AccountTone.idle
    ? AccountStatus(i18n('account_status_none_hint'))
    : status;

/// Whether anything of the login is stored on this device (the list shows
/// the sign-out button; an unreadable cookie can be removed too).
bool accountStored(AccountSnapshot stored) => stored.cookie.isNotEmpty || stored.unreadable;

/// The short line of a valid Douyu login: renews itself, or ends then.
String _douyuValid(AccountSnapshot stored) {
  final credentials = douyuCredentials(stored);
  if (credentials.ltp0 != null && credentials.did != null) return i18n('account_status_douyu_renews');
  final expiry = DouyuApi.sessionExpiry(stored.cookie, savedAt: stored.douyuSavedAt);
  return expiry == null
      ? i18n('account_status_saved')
      : i18n('account_status_douyu_until', args: {'time': accountTime(expiry)});
}

/// Douyu's renewal pair for [stored]: the cookie's own fields, else the
/// separately stored ones (M4.02 `DouyuApi.renewalCredentials`).
({String? ltp0, String? did}) douyuCredentials(AccountSnapshot stored, {String? typedLtp0, String? typedDid}) =>
    DouyuApi.renewalCredentials(
      stored.cookie,
      typedLtp0: typedLtp0,
      typedDid: typedDid,
      storedLtp0: stored.douyuLtp0,
      storedDid: stored.douyuDid,
    );

/// What Douyu's stored login is worth at [now].
DouyuSessionState douyuSessionState(AccountSnapshot stored, {required DateTime now}) {
  final credentials = douyuCredentials(stored);
  return DouyuApi.sessionState(
    stored.cookie,
    now: now,
    savedAt: stored.douyuSavedAt,
    ltp0: credentials.ltp0,
    did: credentials.did,
  );
}

/// What Douyu's login is worth, in words (3.x `_sessionSummary`): the
/// session, when it ends and whether it renews itself.
String douyuSummary(AccountSnapshot stored, {required DateTime now}) {
  final expiry = DouyuApi.sessionExpiry(stored.cookie, savedAt: stored.douyuSavedAt);
  final at = expiry == null ? '' : accountTime(expiry);
  final credentials = douyuCredentials(stored);
  return switch (douyuSessionState(stored, now: now)) {
    DouyuSessionState.none => i18n('douyu_cookie_cleared'),
    DouyuSessionState.guest => i18n('douyu_cookie_guest'),
    DouyuSessionState.valid when expiry == null => i18n('douyu_cookie_valid_no_expiry'),
    DouyuSessionState.valid when credentials.ltp0 != null && credentials.did != null => i18n(
      'douyu_cookie_valid_auto_renew',
      args: {'time': at},
    ),
    DouyuSessionState.valid => i18n('douyu_cookie_valid_needs_repaste', args: {'time': at}),
    DouyuSessionState.expiredRefreshable => i18n('douyu_cookie_expired_refreshable', args: {'time': at}),
    DouyuSessionState.expired => i18n('douyu_cookie_expired', args: {'time': at}),
  };
}

/// [time] in local time as `yyyy-MM-dd HH:mm`.
String accountTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

final RegExp _cookieHeaderPrefix = RegExp(r'^\s*cookie\s*:\s*', caseSensitive: false);
final RegExp _cookiePair = RegExp(r'(?:^|;)\s*[^\s=;]+\s*=');

/// A pasted cookie as stored: control characters, outer blanks and a
/// copied `Cookie:` header name removed (3.x removed the name only on
/// Douyu's page).
String cleanPastedCookie(String text) => normalizeCookie(normalizeCookie(text).replaceFirst(_cookieHeaderPrefix, ''));

/// Whether [cookie] has at least one `name=value` field.
bool looksLikeCookie(String cookie) => _cookiePair.hasMatch(cookie);

/// Field [name] of a pasted cookie, or null.
String? pastedCookieField(String text, String name) => DouyuApi.cookieField(cleanPastedCookie(text), name);
