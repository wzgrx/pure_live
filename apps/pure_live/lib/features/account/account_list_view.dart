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
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The accounts list (3.x `AccountPage`): every platform's login state,
/// sign in, open its cookie page, sign out.
///
/// Bilibili and Douyin are asked who their cookie signs in as when the page
/// opens and whenever the cookie changes (3.x checked Bilibili in a global
/// service at start and only fetched Douyin's nickname). An expired
/// Bilibili cookie is removed with a message, as in 3.x.
class AccountListView extends ConsumerStatefulWidget {
  /// Creates the list.
  const new({super.key});

  @override
  ConsumerState<AccountListView> createState() => _AccountListViewState();
}

class _AccountListViewState extends ConsumerState<AccountListView> {
  late final AccountActions _actions = ref.read(accountActionsProvider);
  final Map<String, AccountCheck> _checks = {};
  final Map<String, String> _checkedCookies = {};
  StreamSubscription<String>? _changes;
  final Set<String> _signingOut = {};

  @override
  void initState() {
    super.initState();
    _changes = _actions.store.secrets.cookieChanges.listen((site) {
      if (!mounted) return;
      setState(() {});
      unawaited(_check(site));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final platform in accountPlatforms) {
        unawaited(_check(platform.id));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  /// Checks [site]'s cookie online once per cookie value.
  Future<void> _check(String site, {bool again = false}) async {
    final platform = accountPlatformOf(site);
    if (platform == null || platform.check != AccountCheckKind.online) return;
    final cookie = _actions.cookieOf(site);
    if (cookie.isEmpty) {
      _checkedCookies.remove(site);
      _checks.remove(site);
      return;
    }
    if (!again && _checkedCookies[site] == cookie) return;
    _checkedCookies[site] = cookie;
    setState(() => _checks[site] = const AccountChecking());
    AccountCheck result;
    try {
      final identity = await ref.read(accountVerifierProvider)(site, cookie);
      result = AccountVerified(identity.name, uid: identity.uid);
    } on Object catch (error, stack) {
      if (error is! NeedsLogin) log('Account check failed', name: 'AccountPage', error: error, stackTrace: stack);
      result = accountCheckFailure(error);
    }
    if (!mounted || _checkedCookies[site] != cookie || _actions.cookieOf(site) != cookie) return;
    if (result case AccountVerified(:final uid?) when site == SiteIds.bilibili) {
      await _actions.rememberBilibiliUid(uid);
    }
    if (result is AccountRejected && site == SiteIds.bilibili) {
      // 3.x `BiliBiliAccountService`: an expired login is signed out.
      AppNavigator.toast(i18n('bilibili_login_expired'));
      await _actions.signOut(site);
      return;
    }
    if (mounted) setState(() => _checks[site] = result);
  }

  void _open(AccountPlatform platform, AccountStatus status) {
    final String path;
    Object? arguments;
    if (platform.id == SiteIds.bilibili) {
      // Signed out: the QR code; signed in: the account's cookie page.
      if (status.signedIn) {
        path = RoutePath.kSettingsAccount;
        arguments = SiteIds.bilibili;
      } else {
        path = RoutePath.kBiliBiliQRLogin;
      }
    } else if (platform.route case final route?) {
      path = route;
    } else {
      path = RoutePath.kSettingsAccount;
      arguments = platform.id;
    }
    unawaited(AppNavigator.toNamed<void>(path, arguments: arguments));
  }

  Future<void> _signOut(AccountPlatform platform) async {
    if (_signingOut.contains(platform.id)) return;
    if (!await confirmSignOut(context, platform.name) || !mounted) return;
    setState(() => _signingOut.add(platform.id));
    try {
      await _actions.signOut(platform.id);
      AppNavigator.toast(i18n('account_signed_out', args: {'name': platform.name}));
    } on Object catch (error, stack) {
      log('Sign out failed', name: 'AccountPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('account_save_failed'));
    } finally {
      if (mounted) setState(() => _signingOut.remove(platform.id));
    }
  }

  Future<void> _signOutAll() async {
    final confirmed = await confirmAccountAction(
      context,
      title: i18n('account_sign_out_all'),
      message: i18n('account_sign_out_all_confirm'),
      action: i18n('account_sign_out_all'),
    );
    if (!confirmed || !mounted) return;
    try {
      await _actions.signOutAll();
      _checks.clear();
      _checkedCookies.clear();
      if (mounted) setState(() {});
      AppNavigator.toast(i18n('account_signed_out_all'));
    } on Object catch (error, stack) {
      log('Sign out of all failed', name: 'AccountPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('account_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(accountClockProvider)();
    final statuses = {
      for (final platform in accountPlatforms)
        platform.id: accountStatus(platform, _actions.snapshot(platform.id), now: now, check: _checks[platform.id]),
    };
    final anyStored = statuses.values.any((status) => status.signedIn) || _actions.store.secrets.unreadable.isNotEmpty;
    final unreadable = [
      for (final platform in accountPlatforms)
        if (_actions.unreadable(platform.id)) platform.name,
    ];
    Widget group(String title, {required bool overseas}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        context.buildGroupTitle(title),
        context.buildModernCard([
          for (final platform in accountPlatforms)
            if (platform.overseas == overseas) _tile(context, platform, statuses[platform.id]!),
        ]),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('third_party_auth')),
        actions: [
          if (anyStored)
            PopupMenuButton<void>(
              key: const ValueKey('account-menu'),
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: const ValueKey('account-sign-out-all'),
                  onTap: () => unawaited(_signOutAll()),
                  child: Text(i18n('account_sign_out_all')),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          AccountTipBanner(text: i18n('account_intro')),
          if (unreadable.isNotEmpty) ...[
            const SizedBox(height: 12),
            AccountStatusCard(
              status: AccountStatus(
                i18n('account_unreadable_notice', args: {'names': unreadable.join('、')}),
                tone: AccountTone.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          group(i18n('account_group_domestic'), overseas: false),
          const SizedBox(height: 20),
          group(i18n('account_group_overseas'), overseas: true),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, AccountPlatform platform, AccountStatus status) {
    final theme = Theme.of(context);
    final color = accountToneColor(theme, status.tone);
    final busy = _signingOut.contains(platform.id);
    return ListTile(
      key: ValueKey('account-${platform.id}'),
      leading: PlatformLogo(platform.id),
      title: Text(platform.name, style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          status.text,
          key: ValueKey('account-${platform.id}-status'),
          style: context.textStyles.t12.copyWith(
            color: color,
            fontWeight: status.tone == AccountTone.idle ? FontWeight.normal : FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : status.signedIn
          ? IconButton(
              key: ValueKey('account-${platform.id}-sign-out'),
              tooltip: i18n('logout'),
              onPressed: () => unawaited(_signOut(platform)),
              icon: Icon(Remix.logout_box_r_line, color: theme.colorScheme.error.withValues(alpha: 0.8), size: 18),
            )
          : Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
      onTap: () => _open(platform, status),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
