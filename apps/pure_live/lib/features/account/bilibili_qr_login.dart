import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';

/// Where the QR login is.
enum BilibiliQrPhase {
  /// Getting a code.
  loading,

  /// Showing the code, not scanned yet.
  waiting,

  /// Scanned; the phone has to confirm.
  scanned,

  /// Confirmed; checking the new cookie.
  verifying,

  /// Signed in.
  done,

  /// The code expired; a new one is a tap away.
  expired,

  /// Stopped by an error ([BilibiliQrLogin.errorKey]).
  failed,
}

/// The QR login flow (3.x `BiliBiliQRLoginController`): get a code, poll it
/// every [interval] (longer after failures), and hand the confirmed cookie
/// to the completion. A newer code or [dispose] makes older answers stale.
final class BilibiliQrLogin extends ChangeNotifier {
  /// Creates the flow; `complete` stores the cookie and returns null, or
  /// the translation key of why it was refused; `notice` shows a passing
  /// message.
  new({
    required this._api,
    required this._complete,
    required this._notice,
    this.interval = const Duration(seconds: 3),
    this.maxFailures = 3,
  });

  final BilibiliQrApi _api;
  final Future<String?> Function(String cookie) _complete;
  final void Function(String key) _notice;

  /// The time between polls.
  final Duration interval;

  /// Failed polls in a row that end the flow.
  final int maxFailures;

  BilibiliQrPhase _phase = BilibiliQrPhase.loading;
  Uri? _url;
  String? _key;
  String _errorKey = 'qr_load_failed';
  Timer? _timer;
  int _generation = 0;
  int _failures = 0;
  bool _closed = false;

  /// Where the flow is.
  BilibiliQrPhase get phase => _phase;

  /// The address in the code.
  Uri? get url => _url;

  /// Why the flow stopped ([BilibiliQrPhase.failed]).
  String get errorKey => _errorKey;

  void _set(BilibiliQrPhase phase) {
    if (_closed) return;
    _phase = phase;
    notifyListeners();
  }

  /// Gets a new code and starts polling it.
  Future<void> load() async {
    if (_closed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _failures = 0;
    _key = null;
    _url = null;
    _set(BilibiliQrPhase.loading);
    try {
      final code = await _api.qrCode();
      if (_closed || generation != _generation) return;
      _key = code.key;
      _url = code.url;
      _set(BilibiliQrPhase.waiting);
      _schedule(generation);
    } on Object catch (error, stack) {
      if (_closed || generation != _generation) return;
      log('QR code failed', name: 'AccountPage', error: error, stackTrace: stack);
      _fail('qr_load_failed');
    }
  }

  void _schedule(int generation) {
    _timer?.cancel();
    final factor = _failures <= 0 ? 1 : (_failures + 1).clamp(2, 4);
    _timer = Timer(interval * factor, () => unawaited(_poll(generation)));
  }

  Future<void> _poll(int generation) async {
    final key = _key;
    if (_closed || generation != _generation || key == null) return;
    try {
      final answer = await _api.qrPoll(key);
      if (_closed || generation != _generation) return;
      _failures = 0;
      switch (answer.state) {
        case BilibiliQrState.waiting:
          if (_phase != BilibiliQrPhase.waiting) _set(BilibiliQrPhase.waiting);
          _schedule(generation);
        case BilibiliQrState.scanned:
          if (_phase != BilibiliQrPhase.scanned) _set(BilibiliQrPhase.scanned);
          _schedule(generation);
        case BilibiliQrState.expired:
          _key = null;
          _set(BilibiliQrPhase.expired);
        case BilibiliQrState.confirmed:
          _key = null;
          _set(BilibiliQrPhase.verifying);
          final refused = await _complete(answer.cookie ?? '');
          if (_closed || generation != _generation) return;
          if (refused == null) {
            _set(BilibiliQrPhase.done);
          } else {
            _fail(refused, notify: false);
          }
      }
    } on ApiChanged catch (error) {
      if (_closed || generation != _generation) return;
      log('QR poll answer changed: $error', name: 'AccountPage');
      _fail('qr_poll_failed');
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      log('QR poll failed: $error', name: 'AccountPage');
      _failures++;
      if (_failures == 1) _notice('qr_poll_failed');
      if (_failures >= maxFailures) {
        _fail('qr_poll_failed', notify: false);
      } else {
        _schedule(generation);
      }
    }
  }

  void _fail(String key, {bool notify = true}) {
    _timer?.cancel();
    _key = null;
    _errorKey = key;
    _set(BilibiliQrPhase.failed);
    if (notify) _notice(key);
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

/// Bilibili's QR login page (3.x `BiliBiliQRLoginPage`,
/// docs/A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie): the code with its state laid over it, the line under it,
/// and "扫不了？" with the web login (phones) and the cookie.
class BilibiliQrLoginView extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<BilibiliQrLoginView> createState() => _BilibiliQrLoginViewState();
}

class _BilibiliQrLoginViewState extends ConsumerState<BilibiliQrLoginView> {
  late final AccountActions _actions = ref.read(accountActionsProvider);
  late final BilibiliQrLogin _login = BilibiliQrLogin(
    api: ref.read(bilibiliQrApiProvider),
    complete: _complete,
    notice: (key) => AppNavigator.toast(i18n(key)),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_login.load());
  }

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  /// Checks the confirmed cookie, stores it and closes the page. A cookie
  /// the platform says signs in nobody is not stored; one that cannot be
  /// checked right now is stored (the passport just issued it).
  Future<String?> _complete(String cookie) async {
    final value = cleanPastedCookie(cookie);
    if (value.isEmpty) return 'qr_cookie_missing';
    AccountCheck result;
    try {
      final identity = await ref.read(accountVerifierProvider)(SiteIds.bilibili, value);
      result = AccountVerified(identity.name, uid: identity.uid);
    } on Object catch (error) {
      result = accountCheckFailure(error);
    }
    if (result is AccountRejected) return 'bilibili_login_verification_failed';
    await _actions.save(SiteIds.bilibili, value);
    if (result case AccountVerified(:final uid?)) await _actions.rememberBilibiliUid(uid);
    AppNavigator.toast(switch (result) {
      AccountVerified(:final name) => i18n('account_saved_signed_in', args: {'name': name}),
      // The passport just issued it: stored, marked unchecked (c13).
      _ => i18n('account_saved_unverified'),
    });
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop(true);
      });
    }
    return null;
  }

  /// Whether this device offers the web (SMS, password) login: phones with
  /// the in-app browser (3.x showed it on Android and iOS only).
  bool get _webLogin =>
      InAppWeb.available &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('bilibili_login'))),
      body: ListView(
        key: const ValueKey('bilibili-qr-scroll-view'),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          ReadableContent(
            child: LayoutBuilder(
              // 200 on phones, 220 on wide screens (c11; 3.x 140-180).
              builder: (context, constraints) => ListenableBuilder(
                listenable: _login,
                builder: (context, _) => _QrCard(login: _login, size: constraints.maxWidth >= 600 ? 220 : 200),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ListenableBuilder(
              listenable: _login,
              builder: (context, _) => _QrMessage(login: _login),
            ),
          ),
          const SizedBox(height: 28),
          // "扫不了？" (c12): the web login on phones, the cookie everywhere.
          Text(
            i18n('account_qr_cannot_scan'),
            textAlign: TextAlign.center,
            style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_webLogin)
                TextButton.icon(
                  key: const ValueKey('bilibili-qr-web-login'),
                  onPressed: () => unawaited(AppNavigator.offAndToNamed<void>(RoutePath.kBiliBiliWebLogin)),
                  icon: const Icon(AppIcons.webLogin, size: 18),
                  label: Text(i18n('account_web_login_option')),
                ),
              TextButton.icon(
                key: const ValueKey('bilibili-qr-paste-cookie'),
                onPressed: () =>
                    unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsAccount, arguments: SiteIds.bilibili)),
                icon: const Icon(AppIcons.pasteText, size: 18),
                label: Text(i18n('account_paste_cookie')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The code in live_ui's [QrCodeCard] (U.1c c11): loading, scanned,
/// expired, failed and checking are laid over it, so it never moves (3.x
/// swapped it for text).
class _QrCard extends StatelessWidget {
  const new({required this.login, required this.size});

  final BilibiliQrLogin login;
  final double size;

  @override
  Widget build(BuildContext context) {
    final retry = login.phase == BilibiliQrPhase.failed;
    return QrCodeCard(
      key: const ValueKey('bilibili-qr-card'),
      data: login.url?.toString(),
      size: size,
      status: switch (login.phase) {
        BilibiliQrPhase.loading => QrCodeStatus.loading,
        BilibiliQrPhase.waiting => QrCodeStatus.ready,
        BilibiliQrPhase.scanned => QrCodeStatus.scanned,
        BilibiliQrPhase.expired => QrCodeStatus.expired,
        BilibiliQrPhase.failed => QrCodeStatus.failed,
        BilibiliQrPhase.verifying => QrCodeStatus.working,
        BilibiliQrPhase.done => QrCodeStatus.done,
      },
      message: switch (login.phase) {
        BilibiliQrPhase.loading => i18n('qr_loading'),
        BilibiliQrPhase.waiting => null,
        BilibiliQrPhase.scanned => i18n('qr_scanned'),
        BilibiliQrPhase.expired => i18n('qr_expired'),
        BilibiliQrPhase.failed => i18n(login.errorKey == 'qr_load_failed' ? 'qr_load_failed' : 'account_qr_stopped'),
        BilibiliQrPhase.verifying => i18n('account_verifying'),
        BilibiliQrPhase.done => i18n('bilibili_login_verified'),
      },
      actionLabel: i18n(retry ? 'retry' : 'refresh_qr'),
      actionKey: ValueKey(retry ? 'bilibili-qr-retry' : 'bilibili-qr-refresh'),
      onAction: () => unawaited(login.load()),
    );
  }
}

/// The line under the code (3.x's status row): what to do now; tinted
/// once the code was scanned.
class _QrMessage extends StatelessWidget {
  const new({required this.login});

  final BilibiliQrLogin login;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phase = login.phase;
    final scanned = phase == BilibiliQrPhase.scanned;
    final text = switch (phase) {
      BilibiliQrPhase.loading => i18n('qr_loading'),
      BilibiliQrPhase.waiting => i18n('qr_waiting_scan'),
      BilibiliQrPhase.scanned => i18n('qr_scanned_confirm'),
      BilibiliQrPhase.expired => i18n('qr_expired_hint'),
      BilibiliQrPhase.failed => i18n(login.errorKey),
      BilibiliQrPhase.verifying => i18n('account_verifying'),
      BilibiliQrPhase.done => i18n('bilibili_login_verified'),
    };
    final color = scanned ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      key: const ValueKey('bilibili-qr-message'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scanned ? scheme.primary.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(scanned ? AppIcons.qrScanned : AppIcons.qrCode, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: context.textStyles.t13.copyWith(
                color: color,
                fontWeight: scanned ? FontWeight.w600 : FontWeight.w400,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
