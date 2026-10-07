import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The orientations the live room and the multi-view ask for around their
/// fullscreens; every such request goes through here, so a release still
/// pending from leaving one fullscreen never undoes the next.
///
/// Sideways (issue #36): Flutter's landscapeLeft + landscapeRight (what 3.x
/// asked for) is Android's USER_LANDSCAPE, which stays put while auto-rotate
/// is off; on Android the picture then follows the phone over
/// (SENSOR_LANDSCAPE), as video apps do. The next
/// [SystemChrome.setPreferredOrientations] replaces it.
///
/// Leaving (O05.3): with auto-rotate off, Android's unspecified orientation
/// is the locked rotation, which HyperOS moved to landscape while
/// SENSOR_LANDSCAPE turned the screen (the K90: `user_rotation` 0 to 3), so
/// letting go at once left the whole app, and other apps, sideways. The phone
/// is turned upright first and let go once that has settled.
abstract final class ScreenOrientation {
  static const MethodChannel _channel = MethodChannel('pure_live/system_access');

  /// How long an upright phone is held before it is let go: the turn and the
  /// system's own rotation bookkeeping finish first.
  static const Duration settle = Duration(seconds: 3);

  static Timer? _release;

  /// Bumped by every request; a [restore] still asking about auto-rotate
  /// stands down when another request came meanwhile.
  static int _turn = 0;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Sideways, either way round, turning over with the phone.
  static Future<void> landscape() async {
    _claim();
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!_android) return;
    try {
      await _channel.invokeMethod<bool>('sensorLandscape');
    } on PlatformException {
      // Sideways as asked above, without turning over.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Upright (the portrait fullscreen).
  static Future<void> portrait() async {
    _claim();
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  /// Whatever the system says (the "跟随系统" fullscreen).
  static Future<void> free() async {
    _claim();
    await SystemChrome.setPreferredOrientations(const []);
  }

  /// Back from a fullscreen. On Android with auto-rotate off (or unknown) the
  /// phone is turned upright and let go [settle] later; with auto-rotate on
  /// it is let go at once and follows the phone, as before. [upright] turns
  /// it upright whatever ("横屏全屏", 3.x
  /// `exitFullscreenWithOrientationRestore`, UI.md appendix A 11).
  static Future<void> restore({bool upright = false}) async {
    final turn = _claim();
    if (!upright) {
      if (!_android || await _autoRotate()) {
        if (turn == _turn) await SystemChrome.setPreferredOrientations(const []);
        return;
      }
      if (turn != _turn) return;
    }
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    if (turn != _turn) return;
    _release = Timer(settle, () {
      _release = null;
      unawaited(SystemChrome.setPreferredOrientations(const []));
    });
  }

  /// Drops a pending release; the caller's request is the latest.
  static int _claim() {
    _release?.cancel();
    _release = null;
    return ++_turn;
  }

  /// Whether the system's auto-rotate is on; false when it cannot tell.
  static Future<bool> _autoRotate() async {
    try {
      return await _channel.invokeMethod<bool>('autoRotate') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
