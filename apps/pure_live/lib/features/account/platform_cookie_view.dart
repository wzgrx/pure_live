import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/account_widgets.dart';
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
  AccountCheck? _check;
  int _checkRun = 0;

  String get _id => widget.platform.id;

  bool get _online => widget.platform.check == AccountCheckKind.online;

  @override
  void initState() {
    super.initState();
    _changes = _actions.store.secrets.cookieChanges.where((site) => site == _id).listen((_) {
      if (mounted) setState(() {});
    });
    if (_online && _actions.cookieOf(_id).isNotEmpty) {
      _check = const AccountChecking();
      unawaited(_runVerify(++_checkRun));
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
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
        await _actions.rememberBilibiliUid(uid);
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
    await _actions.save(_id, cookie);
    if (result case AccountVerified(:final uid?) when _id == SiteIds.bilibili) {
      await _actions.rememberBilibiliUid(uid);
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

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform;
    final stored = _actions.snapshot(_id);
    final status = accountStatus(platform, stored, now: ref.watch(accountClockProvider)(), check: _check);
    final bilibili = _id == SiteIds.bilibili;
    return CookieEditorScaffold(
      title: i18n('account_editor_title', args: {'name': platform.name}),
      name: platform.name,
      banner: widget.webLoginFallback ? const _WebLoginNotice() : null,
      tip: AccountTipBanner(
        text: platform.tip,
        website: platform.website,
        websiteLabel: i18n('account_open_website', args: {'name': platform.name}),
      ),
      status: AccountStatusCard(
        status: status,
        action: _online && stored.cookie.isNotEmpty && _check is! AccountChecking
            ? IconButton(
                key: const ValueKey('account-recheck'),
                tooltip: i18n('account_recheck'),
                onPressed: _verifyStored,
                icon: const Icon(Remix.refresh_line, size: 18),
              )
            : null,
      ),
      inputs: [
        CookieInput(
          controller: _cookie,
          fieldKey: const ValueKey('account-cookie-input'),
          hint: platform.hint,
          multiline: true,
        ),
      ],
      hasStored: stored.cookie.isNotEmpty || stored.unreadable,
      onSave: _save,
      onSignOut: _signOut,
      actions: [
        if (bilibili)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const ValueKey('account-bilibili-qr'),
              onPressed: () => unawaited(AppNavigator.offAndToNamed<void>(RoutePath.kBiliBiliQRLogin)),
              icon: const Icon(Remix.qr_code_line, size: 16),
              label: Text(i18n('qr_login')),
            ),
          ),
      ],
    );
  }
}

/// Why `RoutePath.kBiliBiliWebLogin` shows the cookie page.
class _WebLoginNotice extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) =>
      AccountStatusCard(status: AccountStatus(i18n('account_bilibili_web_unavailable'), tone: AccountTone.warning));
}
