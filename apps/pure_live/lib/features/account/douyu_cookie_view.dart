import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/account_widgets.dart';
import 'package:pure_live/features/account/cookie_editor.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Where the renewal key and the device id are found.
final Uri _passport = Uri.https('passport.douyu.com', '/');

/// Douyu's cookie page (3.x `DouyuCookiePage`): the page cookie, the two
/// values the renewal needs, "renew now" and the forced renewal switch
/// (UPGRADES 2-1).
///
/// The cookie box takes either cookie and they are not interchangeable
/// (3.x `DouyuCookieController.setCookie`): the page cookie carries the
/// login (`dy_auth`), the passport cookie carries `LTP0`/`dy_did`. Pasting
/// the passport one fills the two fields and never replaces a stored login.
class DouyuCookieView extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<DouyuCookieView> createState() => _DouyuCookieViewState();
}

class _DouyuCookieViewState extends ConsumerState<DouyuCookieView> {
  late final AccountActions _actions = ref.read(accountActionsProvider);
  late final AccountPlatform _platform = accountPlatformOf(SiteIds.douyu)!;
  late final TextEditingController _cookie;
  late final TextEditingController _ltp0;
  late final TextEditingController _did;
  StreamSubscription<String>? _changes;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    final login = _actions.douyuLogin;
    _cookie = TextEditingController(text: _actions.cookieOf(SiteIds.douyu));
    _ltp0 = TextEditingController(text: login.ltp0 ?? '');
    _did = TextEditingController(text: login.did ?? '');
    _cookie.addListener(_absorbPasted);
    _changes = _actions.store.secrets.cookieChanges.where((site) => site == SiteIds.douyu).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _cookie
      ..removeListener(_absorbPasted)
      ..dispose();
    _ltp0.dispose();
    _did.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(accountClockProvider)();

  /// Copies `LTP0` and `dy_did` out of the pasted cookie into their fields;
  /// never empties a field (a page cookie has neither).
  void _absorbPasted() {
    final text = _cookie.text;
    if (text.trim().isEmpty) return;
    final ltp0 = pastedCookieField(text, DouyuApi.longTermKeyName);
    if (ltp0 != null && ltp0 != _ltp0.text) _ltp0.text = ltp0;
    final did = pastedCookieField(text, DouyuApi.deviceIdName);
    if (did != null && did != _did.text) _did.text = did;
  }

  static String? _clean(String text) {
    final value = normalizeCookie(text);
    return value.isEmpty ? null : value;
  }

  Future<bool> _save() async {
    final pasted = DouyuApi.normalizeCookie(cleanPastedCookie(_cookie.text));
    final stored = _actions.cookieOf(SiteIds.douyu);
    final pastedIsSession = DouyuApi.sessionToken(pasted) != null;
    final storedIsSession = DouyuApi.sessionToken(stored) != null;
    final ltp0 = _clean(_ltp0.text);
    final did = _clean(_did.text);

    if (!pastedIsSession && DouyuApi.isPassportCookie(pasted)) {
      // The passport request's cookie: its fields would make the play edge
      // answer 403, so it is never stored as the login.
      if (storedIsSession) {
        await _actions.saveDouyuPair(ltp0: ltp0, did: did);
      } else {
        await _actions.saveDouyu(cookie: '', ltp0: ltp0, did: did);
      }
      _cookie.text = storedIsSession ? stored : '';
      AppNavigator.toast(i18n(storedIsSession ? 'douyu_cookie_credentials_absorbed' : 'douyu_cookie_credentials_only'));
      return true;
    }

    // A cookie without a login next to a stored login only brings the pair.
    final keep = storedIsSession && !pastedIsSession;
    final effective = keep ? stored : pasted;
    await _actions.saveDouyu(cookie: effective, ltp0: ltp0, did: did);
    _cookie.text = effective;
    AppNavigator.toast(
      keep ? i18n('douyu_cookie_credentials_absorbed') : douyuSummary(_actions.snapshot(SiteIds.douyu), now: _now()),
    );
    return true;
  }

  /// Renews right now (3.x `refreshNow`): proves the pair works instead of
  /// waiting up to a week to find out.
  Future<void> _renewNow() async {
    if (_renewing) return;
    final cookie = DouyuApi.normalizeCookie(cleanPastedCookie(_cookie.text));
    if (cookie.isEmpty) {
      AppNavigator.toast(i18n('douyu_cookie_refresh_no_cookie'));
      return;
    }
    final stored = _actions.douyuLogin;
    final credentials = DouyuApi.renewalCredentials(
      cookie,
      typedLtp0: _ltp0.text,
      typedDid: _did.text,
      storedLtp0: stored.ltp0,
      storedDid: stored.did,
    );
    final ltp0 = credentials.ltp0;
    final did = credentials.did;
    if (ltp0 == null || did == null) {
      AppNavigator.toast(i18n('douyu_cookie_refresh_no_credentials'));
      return;
    }
    if (DouyuApi.sessionToken(cookie) == null) {
      AppNavigator.toast(i18n('douyu_cookie_refresh_no_session'));
      return;
    }
    setState(() => _renewing = true);
    try {
      // The button means "use these values": store them first.
      await _actions.saveDouyuPair(ltp0: ltp0, did: did);
      final renewed = await ref.read(douyuRenewerProvider)(cookie: cookie, ltp0: ltp0, did: did);
      if (renewed == null) {
        AppNavigator.toast(i18n('douyu_cookie_refresh_no_change'));
        return;
      }
      await _actions.saveDouyuRenewed(renewed);
      if (mounted) _cookie.text = renewed;
      final expiry = DouyuApi.sessionExpiry(renewed, savedAt: _now()) ?? _now().add(DouyuApi.webCookieLifetime);
      AppNavigator.toast(i18n('douyu_cookie_refresh_ok', args: {'time': accountTime(expiry)}));
    } on Object catch (error, stack) {
      log('Douyu renewal failed', name: 'AccountPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('account_douyu_renew_failed'));
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  Future<void> _signOut() async {
    await _actions.signOut(SiteIds.douyu);
    AppNavigator.toast(i18n('account_signed_out', args: {'name': _platform.name}));
  }

  @override
  Widget build(BuildContext context) {
    final stored = _actions.snapshot(SiteIds.douyu);
    final now = ref.watch(accountClockProvider)();
    final status = accountStatus(_platform, stored, now: now);
    final forceRenew = watchSetting(ref, Settings.douyuForceRenew);
    return CookieEditorScaffold(
      title: i18n('account_editor_title', args: {'name': _platform.name}),
      name: _platform.name,
      tip: const AccountTipBanner(body: _DouyuTip()),
      status: AccountStatusCard(
        status: stored.cookie.isEmpty ? status : AccountStatus(douyuSummary(stored, now: now), tone: status.tone),
      ),
      inputs: [
        CookieInput(
          controller: _cookie,
          fieldKey: const ValueKey('account-cookie-input'),
          hint: i18n('douyu_cookie_hint'),
          multiline: true,
        ),
        CookieInput(
          controller: _ltp0,
          fieldKey: const ValueKey('douyu-ltp0-input'),
          label: i18n('douyu_ltp0_label'),
          hint: i18n('douyu_ltp0_hint'),
        ),
        CookieInput(
          controller: _did,
          fieldKey: const ValueKey('douyu-did-input'),
          label: i18n('douyu_did_label'),
          hint: i18n('douyu_did_hint'),
        ),
      ],
      hasStored: stored.cookie.isNotEmpty || stored.unreadable || stored.douyuLtp0 != null,
      onSave: _save,
      onSignOut: _signOut,
      extra: [
        context.buildGroupTitle(i18n('account_douyu_renewal')),
        context.buildModernCard([
          context.buildTile(
            icon: Remix.refresh_line,
            title: i18n('douyu_cookie_refresh_now'),
            subtitle: i18n('account_douyu_renew_now_desc'),
            isLong: true,
            trailing: _renewing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _renewing ? null : _renewNow,
          ),
          context.buildSwitchTile(
            icon: Remix.timer_flash_line,
            title: i18n('account_douyu_force_renew'),
            subtitle: i18n('account_douyu_force_renew_desc'),
            isLong: true,
            value: forceRenew,
            onChanged: (value) => unawaited(ref.read(storeProvider).settings.set(Settings.douyuForceRenew, value)),
          ),
        ]),
      ],
    );
  }
}

/// How to get the two cookies (3.x `_DouyuCookieTip`): the steps, the
/// passport link and the lifetime.
class _DouyuTip extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final style = accountTipStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n('douyu_cookie_tip_step1'), style: style),
        const SizedBox(height: 8),
        Text(i18n('douyu_cookie_tip_step2'), style: style),
        TextButton.icon(
          key: const ValueKey('douyu-open-passport'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => openAccountWebsite(_passport),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('https://passport.douyu.com/'),
        ),
        Text(i18n('douyu_cookie_tip_lifetime'), style: style),
      ],
    );
  }
}
