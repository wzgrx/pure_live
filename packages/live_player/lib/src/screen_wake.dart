import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any video view asks (F.1a). One count for the
/// app, as media_kit's own keep-on counted: a view that lets go never turns
/// the screen off under another one that still plays.
abstract final class ScreenWake {
  static int _holders = 0;

  /// Turns keep-screen-on on or off (wakelock_plus); tests replace it.
  static Future<void> Function({required bool enabled}) apply = _plugin;

  static Future<void> _plugin({required bool enabled}) => WakelockPlus.toggle(enable: enabled);

  /// Whether the screen is kept on now.
  static bool get held => _holders > 0;

  /// One more view wants the screen on.
  static void hold() {
    if (_holders++ == 0) unawaited(_set(enabled: true));
  }

  /// A view no longer wants it.
  static void release() {
    if (_holders == 0) return;
    if (--_holders == 0) unawaited(_set(enabled: false));
  }

  static Future<void> _set({required bool enabled}) async {
    try {
      await apply(enabled: enabled);
    } on Object {
      // No plugin (tests, a desktop without the service): nothing to keep on.
    }
  }

  /// Forgets every holder (tests).
  @visibleForTesting
  static void reset() {
    _holders = 0;
    apply = _plugin;
  }
}
