import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';

/// The result of the last "校验" of a platform's stored cookie (F-ACC-01).
@immutable
sealed class AccountCheck {
  const new();
}

/// Not checked in this run, or the cookie changed since.
final class AccountUnchecked extends AccountCheck {
  const new();
}

/// A check is running.
final class AccountChecking extends AccountCheck {
  const new();
}

/// The platform named the account.
final class AccountVerified extends AccountCheck {
  const new(this.identity);

  /// Who is signed in.
  final AccountIdentity identity;
}

/// The platform said the cookie is not signed in. B 站's cookie is then
/// cleared (spec/sites/bilibili.md §8.2, §9).
final class AccountExpired extends AccountCheck {
  const new();
}

/// The check did not get an answer (network, risk control): nothing changed.
final class AccountCheckFailed extends AccountCheck {
  const new(this.reason);

  /// Why, for the user.
  final String reason;
}

/// Checks of one platform's stored cookie. A result only applies to the
/// cookie it was made for: a newer cookie is never overwritten by an older
/// check (spec/sites/bilibili.md §8.2; douyin.md §8).
class AccountCheckNotifier extends Notifier<AccountCheck> {
  new(this.platform);

  /// Platform id.
  final String platform;

  // Set while this notifier clears an expired cookie, so the change it
  // causes keeps the "expired" result instead of resetting it.
  bool _clearing = false;

  @override
  AccountCheck build() {
    final store = ref.watch(accountStoreProvider);
    final subscription = store.changes.where((changed) => changed == platform).listen((_) {
      if (_clearing) return;
      state = const AccountUnchecked();
    });
    ref.onDispose(subscription.cancel);
    return const AccountUnchecked();
  }

  /// Asks the platform who the stored cookie belongs to. Does nothing without
  /// a cookie or a user-info endpoint.
  Future<void> verify() async {
    final verifier = ref.read(accountVerifierProvider(platform));
    final store = ref.read(accountStoreProvider);
    final cookie = store.cookie(platform);
    if (verifier == null || cookie == null || state is AccountChecking) return;
    state = const AccountChecking();
    bool current() => ref.mounted && store.cookie(platform) == cookie;
    try {
      final identity = await verifier();
      if (!current()) return;
      state = AccountVerified(identity);
      final uid = int.tryParse(identity.uid ?? '');
      if (platform == 'bilibili' && uid != null) await ref.read(accountSettingsProvider).setBilibiliUid(uid);
    } on NeedsLogin {
      if (!current()) return;
      state = const AccountExpired();
      // B 站 §8.2: an account check that says "not signed in" clears the
      // stored cookie; other platforms keep it until the user signs out.
      if (platform == 'bilibili') {
        _clearing = true;
        try {
          await store.signOut(platform);
          // The change notification is asynchronous; let it pass first.
          await Future<void>.delayed(Duration.zero);
        } finally {
          _clearing = false;
        }
      }
    } on Object catch (error) {
      if (!current()) return;
      state = AccountCheckFailed(describeError(error).title);
    }
  }
}

/// The last check of each platform's cookie.
final NotifierProviderFamily<AccountCheckNotifier, AccountCheck, String> accountCheckProvider =
    NotifierProvider.family<AccountCheckNotifier, AccountCheck, String>(AccountCheckNotifier.new);

/// `2026-10-05 10:00` in local time.
String formatAccountTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Douyu's session as the accounts page shows it (spec/sites/douyu.md §8.1).
({DouyuSessionState state, DateTime? expiry, bool renewable}) douyuStatus(AccountStore store, DateTime now) {
  final cookie = store.cookie('douyu') ?? '';
  final keys = DouyuSession.credentials(cookie, storedLtp0: store.douyuLtp0, storedDid: store.douyuDid);
  final renewable = keys.ltp0 != null && keys.did != null;
  return (
    state: DouyuSession.state(cookie, now: now, savedAt: store.douyuSavedAt, ltp0: keys.ltp0, did: keys.did),
    expiry: DouyuSession.expiry(cookie, savedAt: store.douyuSavedAt),
    renewable: renewable,
  );
}

/// One line saying what the stored login of [platform] is worth; never the
/// cookie itself (constitution rule 8).
String accountSummary(String platform, AccountStore store, AccountCheck check, {required DateTime now}) {
  final cookie = store.cookie(platform);
  if (cookie == null) return check is AccountExpired ? '登录已失效，请重新登录' : '未登录';
  if (platform == 'douyu') {
    final status = douyuStatus(store, now);
    final end = status.expiry == null ? null : formatAccountTime(status.expiry!);
    return switch (status.state) {
      DouyuSessionState.none => '未登录',
      DouyuSessionState.guest => '已填 Cookie，但里面没有登录信息',
      DouyuSessionState.valid when end == null => '已登录 · 有效期未知',
      DouyuSessionState.valid => '已登录 · 有效期到 $end${status.renewable ? '，到期前可续期' : ''}',
      DouyuSessionState.expiredRefreshable => '已在 $end 过期，可以续期',
      DouyuSessionState.expired => '已过期，请重新登录',
    };
  }
  final uid = platform == 'bilibili' ? cookieField(cookie, 'DedeUserID') : null;
  return switch (check) {
    AccountVerified(:final identity) => '已登录 · ${identity.name}${identity.uid == null ? '' : '（UID ${identity.uid}）'}',
    AccountChecking() => '已登录 · 正在校验',
    AccountExpired() => 'Cookie 已失效，请重新登录',
    AccountCheckFailed(:final reason) => '已登录 · 校验失败：$reason',
    AccountUnchecked() => uid == null ? '已填 Cookie' : '已登录 · UID $uid',
  };
}
