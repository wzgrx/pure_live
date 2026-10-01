import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/account/account_services.dart';
import 'package:pure_live/pages/account/account_state.dart';
import 'package:pure_live/pages/account/account_widgets.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

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

/// Bilibili's QR login page (3.x `BiliBiliQRLoginPage`).
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
      _ => i18n('bilibili_user_info_failed'),
    });
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop(true);
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('bilibili_login')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const ValueKey('bilibili-qr-paste-cookie'),
              onPressed: () =>
                  unawaited(AppNavigator.offAndToNamed<void>(RoutePath.kSettingsAccount, arguments: SiteIds.bilibili)),
              icon: const Icon(Remix.file_copy_line, size: 16),
              label: Text(i18n('account_paste_cookie')),
            ),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('bilibili-qr-scroll-view'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          AccountTipBanner(text: i18n('qr_login_tip')),
          const SizedBox(height: 28),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListenableBuilder(listenable: _login, builder: (context, _) => _body(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_login.phase) {
        BilibiliQrPhase.loading => _progress(i18n('qr_loading'), key: const ValueKey('qr-loading')),
        BilibiliQrPhase.verifying => _progress(i18n('account_verifying'), key: const ValueKey('qr-verifying')),
        BilibiliQrPhase.done => AccountStatusCard(
          key: const ValueKey('qr-done'),
          status: AccountStatus(i18n('bilibili_login_verified'), tone: AccountTone.ok),
        ),
        BilibiliQrPhase.failed => Column(
          key: const ValueKey('qr-failed'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Remix.error_warning_line, size: 40, color: theme.hintColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(i18n(_login.errorKey), textAlign: TextAlign.center, style: context.textStyles.t14Muted),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('bilibili-qr-retry'),
              onPressed: () => unawaited(_login.load()),
              icon: const Icon(Remix.refresh_line, size: 18),
              label: Text(i18n('retry')),
            ),
          ],
        ),
        BilibiliQrPhase.waiting || BilibiliQrPhase.scanned || BilibiliQrPhase.expired => _code(context),
      },
    );
  }

  Widget _progress(String message, {required Key key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 56),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 20),
        Text(message, textAlign: TextAlign.center, style: context.textStyles.t14),
      ],
    ),
  );

  /// The code, with the scanned and expired states laid over it (3.x
  /// replaced an expired code by an error text).
  Widget _code(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _login.phase;
    final scanned = phase == BilibiliQrPhase.scanned;
    final expired = phase == BilibiliQrPhase.expired;
    return Column(
      key: const ValueKey('qr-code'),
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = (constraints.maxWidth - 64).clamp(160.0, 220.0);
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrCodeWidget(key: const ValueKey('bilibili-qr-code'), data: '${_login.url}', size: size),
                  if (scanned || expired)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.88),
                        child: Center(
                          child: expired
                              ? FilledButton.tonalIcon(
                                  key: const ValueKey('bilibili-qr-refresh'),
                                  onPressed: () => unawaited(_login.load()),
                                  icon: const Icon(Remix.refresh_line, size: 18),
                                  label: Text(i18n('refresh_qr')),
                                )
                              : Icon(Remix.checkbox_circle_fill, size: 48, color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        AccountStatusCard(
          status: AccountStatus(
            i18n(switch (phase) {
              BilibiliQrPhase.scanned => 'qr_scanned_confirm',
              BilibiliQrPhase.expired => 'qr_expired',
              _ => 'qr_waiting_scan',
            }),
            tone: switch (phase) {
              BilibiliQrPhase.scanned => AccountTone.ok,
              BilibiliQrPhase.expired => AccountTone.warning,
              _ => AccountTone.idle,
            },
          ),
        ),
      ],
    );
  }
}
