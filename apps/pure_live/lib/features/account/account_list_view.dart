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

/// "平台账号" (3.x `AccountPage` "三方认证", docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览): every
/// platform's login state in two groups; a tap opens the platform's page,
/// the trailing button signs out after asking.
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
    if (result case AccountVerified(:final uid?, :final name) when site == SiteIds.bilibili) {
      await _actions.rememberBilibili(uid, name: name);
    }
    if (result is AccountRejected && site == SiteIds.bilibili) {
      // 3.x `BiliBiliAccountService`: an expired login is signed out.
      AppNavigator.toast(i18n('bilibili_login_expired'));
      await _actions.signOut(site);
      return;
    }
    if (mounted) setState(() => _checks[site] = result);
  }

  /// Opens [platform]'s page (c1; 3.x signed out on a tap of a stored
  /// login): Bilibili without a login goes straight to the QR code (K2 A).
  void _open(AccountPlatform platform, bool stored) {
    final String path;
    Object? arguments;
    if (platform.id == SiteIds.bilibili) {
      // Signed out with remembered sign-ins: the page where they switch
      // back (K01.2); with none, straight to the QR code as before.
      if (stored || _actions.bilibiliAccounts.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(accountClockProvider)();
    final statuses = {
      for (final platform in accountPlatforms)
        platform.id: accountStatus(platform, _actions.snapshot(platform.id), now: now, check: _checks[platform.id]),
    };
    final unreadable = [
      for (final platform in accountPlatforms)
        if (_actions.unreadable(platform.id)) platform.name,
    ];
    Widget group(String title, {required bool overseas}) => SettingsGroup(
      title: title,
      first: !overseas,
      children: [
        for (final platform in accountPlatforms)
          if (platform.overseas == overseas) _tile(context, platform, statuses[platform.id]!),
      ],
    );
    final children = <Widget>[
      if (unreadable.isNotEmpty) ...[
        AccountNotice(text: i18n('account_unreadable_notice', args: {'names': unreadable.join('、')})),
        const SizedBox(height: 16),
      ] else
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Text(
            i18n('account_intro'),
            key: const ValueKey('account-intro'),
            style: context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.55),
          ),
        ),
      group(i18n('account_group_domestic'), overseas: false),
      group(i18n('account_group_overseas'), overseas: true),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(i18n('account_title'))),
      body: ListView(
        key: const ValueKey('account-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          for (final child in children)
            ReadableContent(
              child: SizedBox(width: double.infinity, child: child),
            ),
        ],
      ),
    );
  }

  /// One platform (3.x `_buildAccountTile`): logo 24, name 15, the status
  /// (wraps, never cut), the sign-out button when something is stored,
  /// else the chevron.
  Widget _tile(BuildContext context, AccountPlatform platform, AccountStatus status) {
    final theme = Theme.of(context);
    final color = accountToneColor(theme, status.tone);
    final busy = _signingOut.contains(platform.id);
    final stored = accountStored(_actions.snapshot(platform.id));
    return ListTile(
      key: ValueKey('account-${platform.id}'),
      minTileHeight: 72,
      horizontalTitleGap: 16,
      leading: PlatformLogo(platform.id, size: 24),
      title: Text(platform.name, style: context.textStyles.t15.regular),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          status.text,
          key: ValueKey('account-${platform.id}-status'),
          style: context.textStyles.t12.copyWith(
            color: color,
            fontWeight: status.tone == AccountTone.ok ? FontWeight.w600 : FontWeight.w400,
            height: 1.4,
          ),
        ),
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: 48,
              child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : stored
          ? IconButton(
              key: ValueKey('account-${platform.id}-sign-out'),
              tooltip: i18n('logout'),
              onPressed: () => unawaited(_signOut(platform)),
              icon: Icon(AppIcons.signOut, color: theme.colorScheme.error.withValues(alpha: 0.8), size: 18),
            )
          : SizedBox.square(dimension: 48, child: Icon(AppIcons.navigate, color: theme.colorScheme.outline, size: 20)),
      onTap: () => _open(platform, stored),
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
    );
  }
}
