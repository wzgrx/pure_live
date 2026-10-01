import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';

/// The interfaces the app has (M14.1): the phone and desktop one (3.x), and
/// the TV one (pure_live_TV's look and remote control).
enum UiMode {
  /// The TV interface on a television, the phone/desktop one elsewhere.
  auto,

  /// The phone and desktop interface everywhere.
  phone,

  /// The TV interface everywhere.
  tv;

  /// The stored value ([Settings.uiMode]); unknown values are [auto].
  static UiMode parse(String value) => values.asNameMap()[value] ?? auto;

  /// Whether this choice shows the TV interface on a device that
  /// [television] or not.
  bool showsTv({required bool television}) => switch (this) {
    auto => television,
    phone => false,
    tv => true,
  };
}

/// Whether this device is a television, asked once at start.
///
/// Android answers through `pure_live/app` `isTelevision` (`UiModeManager`
/// in television mode, or the leanback feature); every other system is not
/// one. The answer is kept for the app's life.
abstract final class TvDevice {
  static bool? _television;

  /// The answer of [detect]; false before it ran.
  static bool get isTelevision => _television ?? false;

  /// The stored answer, null before [detect] (tests).
  @visibleForTesting
  static bool? get debugTelevision => _television;

  /// Sets the answer (tests); null asks again on the next [detect].
  @visibleForTesting
  static set debugTelevision(bool? value) => _television = value;

  /// Asks the system once; later calls return the same answer.
  static Future<bool> detect({MethodChannel channel = const MethodChannel('pure_live/app')}) async {
    if (_television case final known?) return known;
    if (!Platform.isAndroid) return _television = false;
    try {
      return _television = await channel.invokeMethod<bool>('isTelevision') ?? false;
    } on PlatformException {
      return _television = false;
    } on MissingPluginException {
      return _television = false;
    }
  }
}

/// Whether this device is a television ([TvDevice.isTelevision]; tests
/// override it).
final Provider<bool> televisionDeviceProvider = Provider((ref) => TvDevice.isTelevision);

/// Whether [settings] show the TV interface on this device.
bool showsTvInterface(SettingsStore settings, {required bool television}) =>
    UiMode.parse(settings.get(Settings.uiMode)).showsTv(television: television);
