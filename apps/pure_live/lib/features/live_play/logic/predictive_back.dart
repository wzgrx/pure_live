import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The live room's hold on Android's back (3.x
/// `AndroidPredictiveBackService`, F.1c): while a room page holds it,
/// `MainActivity` takes every back (Android 13+'s gesture at overlay
/// priority, and the key some vendor builds still deliver to
/// `onBackPressed`) and hands it here before Flutter could pop the room
/// (`pure_live/predictive_back`).
///
/// One holder at a time: a room page that opens over or instead of another
/// takes it, and the old page closing afterwards does not give it up (3.x
/// kept one set of callbacks, which the old page's `dispose` cleared). The
/// system's back animation is not shown (3.x ignored its progress too).
final class RoomBackChannel {
  new _();

  /// The app's channel.
  static final RoomBackChannel instance = RoomBackChannel._();

  static const MethodChannel _channel = MethodChannel('pure_live/predictive_back');

  Object? _holder;
  Future<void> Function()? _onBack;
  bool _listening = false;

  /// Whether a room holds the back.
  bool get held => _holder != null;

  /// [holder] takes the back: [onBack] runs for each one.
  Future<void> hold(Object holder, Future<void> Function() onBack) async {
    _holder = holder;
    _onBack = onBack;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_handle);
    }
    await _setEnabled(enabled: true);
  }

  /// [holder] gives the back up; nothing happens when another holds it now.
  Future<void> release(Object holder) async {
    if (!identical(_holder, holder)) return;
    _holder = null;
    _onBack = null;
    await _setEnabled(enabled: false);
  }

  /// Forgets the holder and the handler (tests).
  @visibleForTesting
  void reset() {
    _holder = null;
    _onBack = null;
    _listening = false;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _setEnabled({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on PlatformException {
      // The route's PopScope stays the fallback.
    } on MissingPluginException {
      // Tests and other embeddings: the same.
    }
  }

  Future<void> _handle(MethodCall call) async {
    // backStarted, backProgress and backCancelled drive no animation (3.x).
    if (call.method == 'backInvoked') await _onBack?.call();
  }
}
