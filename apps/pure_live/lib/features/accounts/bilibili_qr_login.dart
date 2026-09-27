import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Where a B 站 QR sign-in stands (spec/sites/bilibili.md §8.3).
enum QrLoginPhase {
  /// Asking for a code.
  loading,

  /// Shown, not scanned (86101).
  waiting,

  /// Scanned, waiting for the confirmation on the phone (86090).
  scanned,

  /// The code expired (86038); refresh for a new one.
  expired,

  /// Confirmed; checking the cookie before it is stored (§8.2).
  verifying,

  /// Signed in and stored.
  done,

  /// Stopped; [BilibiliQrLogin.message] says why.
  failed,
}

/// The QR sign-in state machine (spec/sites/bilibili.md §8.3): one poll at a
/// time, the next [interval] after the previous one finished; a poll that
/// gets no answer (network, rate limit, risk control) waits 2, then 3 times
/// the interval, and the third failure in a row stops. A refresh voids every
/// poll of the old code. The confirmed cookie is verified before [save]
/// stores it.
final class BilibiliQrLogin extends ChangeNotifier {
  /// Creates the flow; call [start].
  new({required this.api, required this.save, this.interval = const Duration(seconds: 3), this.maxFailures = 3});

  /// The platform calls.
  final BilibiliLoginApi api;

  /// Stores a verified cookie.
  final Future<void> Function(String cookie, AccountIdentity identity) save;

  /// Pause between polls.
  final Duration interval;

  /// Unanswered polls in a row that stop the flow.
  final int maxFailures;

  QrLoginPhase _phase = QrLoginPhase.loading;
  Uri? _code;
  String? _message;
  AccountIdentity? _identity;
  String? _key;
  int _generation = 0;
  int _failures = 0;
  Timer? _timer;
  bool _disposed = false;

  /// The current phase.
  QrLoginPhase get phase => _phase;

  /// The address to show as a QR code, while there is one.
  Uri? get code => _code;

  /// Why the flow failed.
  String? get message => _message;

  /// Who signed in, once [phase] is [QrLoginPhase.done].
  AccountIdentity? get identity => _identity;

  bool _current(int generation) => !_disposed && generation == _generation;

  void _set(QrLoginPhase phase, {String? message}) {
    _phase = phase;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  /// Gets a new code and starts polling; also the refresh after expiry or
  /// failure. Polls of the previous code are void from here on.
  Future<void> start() async {
    final generation = ++_generation;
    _timer?.cancel();
    _key = null;
    _code = null;
    _failures = 0;
    _set(QrLoginPhase.loading);
    try {
      final code = await api.qrCode();
      if (!_current(generation)) return;
      _key = code.key;
      _code = code.url;
      _set(QrLoginPhase.waiting);
      _schedule(generation);
    } on Object catch (error) {
      if (_current(generation)) {
        _set(QrLoginPhase.failed, message: t.accounts.qrFetchFailed(reason: describeError(error).title));
      }
    }
  }

  void _schedule(int generation) {
    // §8.3 back-off: 1×, then 2× and 3× after one and two unanswered polls.
    _timer = Timer(interval * (_failures + 1), () => unawaited(_poll(generation)));
  }

  static bool _unanswered(Object error) =>
      error is NetworkFailure || error is TransportFailure || error is RateLimited || error is RiskControl;

  Future<void> _poll(int generation) async {
    final key = _key;
    if (key == null || !_current(generation)) return;
    ({BilibiliQrState state, String? cookie}) result;
    try {
      result = await api.qrPoll(key);
    } on Object catch (error) {
      if (!_current(generation)) return;
      _failures++;
      if (_unanswered(error) && _failures < maxFailures) {
        _schedule(generation);
      } else {
        _key = null;
        _set(QrLoginPhase.failed, message: t.accounts.qrPollFailed(reason: describeError(error).title));
      }
      return;
    }
    if (!_current(generation)) return;
    _failures = 0;
    switch (result.state) {
      case BilibiliQrState.waiting:
        _set(QrLoginPhase.waiting);
        _schedule(generation);
      case BilibiliQrState.scanned:
        _set(QrLoginPhase.scanned);
        _schedule(generation);
      case BilibiliQrState.expired:
        _key = null;
        _set(QrLoginPhase.expired);
      case BilibiliQrState.confirmed:
        _key = null;
        await _verify(result.cookie ?? '', generation);
    }
  }

  Future<void> _verify(String cookie, int generation) async {
    _set(QrLoginPhase.verifying);
    try {
      final identity = await api.account(cookie);
      if (!_current(generation)) return;
      await save(cookie, identity);
      if (!_current(generation)) return;
      _identity = identity;
      _set(QrLoginPhase.done);
    } on NeedsLogin {
      if (_current(generation)) _set(QrLoginPhase.failed, message: t.accounts.qrVerifyRejected);
    } on Object catch (error) {
      if (_current(generation)) {
        _set(QrLoginPhase.failed, message: t.accounts.qrVerifyFailed(reason: describeError(error).title));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
