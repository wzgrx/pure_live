import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone held sideways for a landscape fullscreen (issue #36). Flutter's
/// landscapeLeft + landscapeRight (what 3.x asked for) is Android's
/// USER_LANDSCAPE, which stays put while auto-rotate is off; on Android the
/// picture then follows the phone over (SENSOR_LANDSCAPE), as video apps
/// do. The next [SystemChrome.setPreferredOrientations] replaces it.
abstract final class ScreenOrientation {
  static const MethodChannel _channel = MethodChannel('pure_live/system_access');

  /// Sideways, either way round, turning over with the phone.
  static Future<void> landscape() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('sensorLandscape');
    } on PlatformException {
      // Sideways as asked above, without turning over.
    } on MissingPluginException {
      // Same.
    }
  }
}
