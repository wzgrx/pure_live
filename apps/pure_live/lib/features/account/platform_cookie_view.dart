import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/account_widgets.dart';
import 'package:pure_live/features/account/bilibili_accounts.dart';
import 'package:pure_live/features/account/cookie_editor.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The cookie page of one platform (3.x `HuyaCookiePage`, `DouyinCookiePage`,
/// `KuaishouCookiePage`, `TwitchCookiePage`, `YyCookiePage`,
/// `SoopCookiePage`; new for Bilibili and CC).
///
/// Platforms checked online (Bilibili, Douyin) are asked who the pasted
/// cookie signs in as before it is stored: a cookie that signs in nobody is
/// not stored, one that cannot be checked right now is stored and marked
/// unchecked.
class PlatformCookieView extends ConsumerStatefulWidget {
  /// Creates the page for [platform]; [webLoginFallback] adds the notice
  /// of `RoutePath.kBiliBiliWebLogin` (no in-app browser yet).
  const new({required this.platform, this.webLoginFallback = false, super.key});

  /// The platform.
  final AccountPlatform platform;

  /// Shown in place of 3.x's web login.
  final bool webLoginFallback;

  @override
  ConsumerState<PlatformCookieView> createState() => _PlatformCookieViewState();
}

class _PlatformCookieViewState extends ConsumerState<PlatformCookieView> {
  late final AccountActions _actions = ref.read(accountActionsProvider);
  late final TextEditingController _cookie = TextEditingController(text: _actions.cookieOf(_id));
  StreamSubscription<String>? _changes;
  StreamSubscription<String>? _rosterChanges;
  AccountCheck? _check;
  int _checkRun = 0;
  int _storedRevision = 0;
  bool _accountBusy = false;

  String get _id => widget.platform.id;

  bool get _online => widget.platform.check == AccountCheckKind.online;

  @override
  void initState() {
    super.initState();
    _changes = _actions.store.secrets.cookieChanges.where((site) => site == _id).listen((_) {
      if (mounted) setState(() {});
    });
    if (_id == SiteIds.bilibili) {
      _rosterChanges = _actions.store.accounts.changes.where((site) => site == _id).listen((_) {
        if (mounted) setState(() {});
      });
    }
    if (_online && _actions.cookieOf(_id).isNotEmpty) {
      _check = const AccountChecking();
      unawaited(_runVerify(++_checkRun));
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_rosterChanges?.cancel());
    _cookie.dispose();
    super.dispose();
  }

  /// Asks who the stored cookie signs in as.
  Future<void> _verifyStored() async {
    if (_actions.cookieOf(_id).isEmpty) return;
    setState(() => _check = const AccountChecking());
    await _runVerify(++_checkRun);
  }

  Future<void> _runVerify(int run) async {
    final result = await _verify(_actions.cookieOf(_id));
    if (!mounted || run != _checkRun) return;
    setState(() => _check = result);
  }

  Future<AccountCheck> _verify(String cookie) async {
    try {
      final identity = await ref.read(accountVerifierProvider)(_id, cookie);
      if (identity.uid case final uid? when _id == SiteIds.bilibili && cookie == _actions.cookieOf(_id)) {
        await _actions.rememberBilibili(uid, name: identity.name);
      }
      return AccountVerified(identity.name, uid: identity.uid);
    } on Object catch (error, stack) {
      if (error is! NeedsLogin) log('Account check failed', name: 'AccountPage', error: error, stackTrace: stack);
      return accountCheckFailure(error);
    }
  }

  Future<bool> _save() async {
    final cookie = cleanPastedCookie(_cookie.text);
    if (!_online) {
      await _actions.save(_id, cookie);
      _cookie.text = cookie;
      AppNavigator.toast(i18n('cookie_saved_local'));
      return true;
    }
    final run = ++_checkRun;
    final previous = _check;
    setState(() => _check = const AccountChecking());
    final result = await _verify(cookie);
    if (!mounted) return false;
    if (result is AccountRejected) {
      setState(() => _check = run == _checkRun ? previous : _check);
      AppNavigator.toast(i18n('account_cookie_rejected'));
      return false;
    }
    try {
      await _actions.save(_id, cookie);
    } on Object {
      // The editor says so (K02.2); the card goes back to before.
      if (mounted && run == _checkRun) setState(() => _check = previous);
      rethrow;
    }
    if (result case AccountVerified(:final uid?, :final name) when _id == SiteIds.bilibili) {
      await _actions.rememberBilibili(uid, name: name);
    }
    _cookie.text = cookie;
    if (mounted && run == _checkRun) setState(() => _check = result);
    AppNavigator.toast(switch (result) {
      AccountVerified(:final name) => i18n('account_saved_signed_in', args: {'name': name}),
      _ => i18n('account_saved_unverified'),
    });
    return true;
  }

  Future<void> _signOut() async {
    _checkRun++;
    await _actions.signOut(_id);
    if (mounted) setState(() => _check = null);
    AppNavigator.toast(i18n('account_signed_out', args: {'name': widget.platform.name}));
  }

  /// Puts the stored login into the box (it changed: a switch, a login on
  /// the QR page) and checks it again.
  Future<void> _reloadStored() async {
    _cookie.text = _actions.cookieOf(_id);
    setState(() {
      _storedRevision++;
      _check = null;
    });
    await _verifyStored();
  }

  /// Switches to a remembered Bilibili sign-in after asking (K01.2), then
  /// checks it: one the platform says signs in nobody is signed out (and
  /// forgotten) as the accounts list does with an expired login.
  Future<void> _switchTo(SavedAccount account) async {
    if (_accountBusy) return;
    final name = savedAccountName(account);
    final confirmed = await confirmAccountAction(
      context,
      title: i18n('account_switch_title'),
      message: i18n(
        _actions.bilibiliCurrentUnremembered ? 'account_switch_confirm_unremembered' : 'account_switch_confirm',
        args: {'name': name},
      ),
      action: i18n('account_switch'),
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _accountBusy = true);
    _checkRun++;
    SavedAccount? switched;
    try {
      switched = await _actions.switchBilibili(account.uid);
    } on Object catch (error, stack) {
      // The error is the cipher's, never the cookie.
      log('Switching the Bilibili account failed', name: 'AccountPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n(secretSaveFailedKey));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
    if (switched == null || !mounted) return;
    AppNavigator.toast(i18n('account_switched', args: {'name': name}));
    await _reloadStored();
    if (!mounted || _check is! AccountRejected || _actions.cookieOf(_id) != switched.cookie) return;
    AppNavigator.toast(i18n('bilibili_login_expired'));
    await _actions.signOut(_id);
    if (mounted) await _reloadStored();
  }

  /// Forgets a remembered Bilibili sign-in after asking (K01.2).
  Future<void> _forget(SavedAccount account) async {
    if (_accountBusy) return;
    final name = savedAccountName(account);
    final confirmed = await confirmAccountAction(
      context,
      title: i18n('account_forget_title'),
      message: i18n('account_forget_confirm', args: {'name': name}),
      action: i18n('delete'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _accountBusy = true);
    try {
      await _actions.forgetBilibili(account.uid);
      AppNavigator.toast(i18n('account_forgotten', args: {'name': name}));
    } on Object catch (error, stack) {
      log('Forgetting the Bilibili account failed', name: 'AccountPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('account_save_failed'));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  /// Signs another account in on the QR page; back here, the box and the
  /// card show the login stored then.
  Future<void> _addAccount() async {
    final before = _actions.cookieOf(_id);
    await AppNavigator.toNamed<Object?>(RoutePath.kBiliBiliQRLogin);
    if (mounted && _actions.cookieOf(_id) != before) await _reloadStored();
  }

  /// The remembered sign-ins (Bilibili with a login or a remembered one).
  Widget? _accounts(AccountSnapshot stored) {
    if (_id != SiteIds.bilibili) return null;
    final accounts = _actions.bilibiliAccounts;
    if (accounts.isEmpty && !accountStored(stored)) return null;
    return BilibiliAccountsGroup(
      accounts: accounts,
      isCurrent: _actions.isCurrentBilibili,
      busy: _accountBusy,
      onSwitch: (account) => unawaited(_switchTo(account)),
      onForget: (account) => unawaited(_forget(account)),
      onAdd: () => unawaited(_addAccount()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform;
    final stored = _actions.snapshot(_id);
    final status = accountStatus(platform, stored, now: ref.watch(accountClockProvider)(), check: _check);
    return CookieEditorScaffold(
      platform: platform,
      banner: widget.webLoginFallback ? AccountNotice(text: i18n('account_bilibili_web_unavailable')) : null,
      tip: AccountTipBanner(
        text: platform.tip,
        website: platform.website,
        websiteLabel: i18n('account_open_website', args: {'name': platform.name}),
      ),
      status: accountPageStatus(status, stored),
      accounts: _accounts(stored),
      storedRevision: _storedRevision,
      statusAction: _online && stored.cookie.isNotEmpty && _check is! AccountChecking
          ? TextButton.icon(
              key: const ValueKey('account-recheck'),
              onPressed: _verifyStored,
              icon: const Icon(AppIcons.recheck, size: 18),
              label: Text(i18n('account_recheck')),
            )
          : null,
      cookie: CookieInput(
        controller: _cookie,
        fieldKey: const ValueKey('account-cookie-input'),
        hint: platform.hint,
        multiline: true,
      ),
      verifiesOnSave: _online,
      hasStored: accountStored(stored),
      onSave: _save,
      onSignOut: _signOut,
    );
  }
}
