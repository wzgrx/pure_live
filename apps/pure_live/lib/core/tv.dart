import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';

/// What the platform says about the device (principles §5.1 rule 1). Android
/// answers on the `purelive/tv` channel (`TvSupport.kt`); elsewhere nothing
/// is a TV.
@immutable
final class TvDevice {
  const new({this.television = false, this.leanback = false, this.touchscreen = true, this.voiceSearch = false});

  /// Nothing reported: not a TV.
  static const TvDevice none = TvDevice();

  /// `UiModeManager` reports `UI_MODE_TYPE_TELEVISION`.
  final bool television;

  /// The leanback (or television) feature is present.
  final bool leanback;

  /// A touchscreen is present.
  final bool touchscreen;

  /// A speech recognizer can be started for search (principles §5.3).
  final bool voiceSearch;

  /// Whether TV mode starts on by itself.
  bool get isTv => television || leanback;

  static const _channel = MethodChannel('purelive/tv');

  /// Asks the platform; never throws (a missing channel means not a TV).
  static Future<TvDevice> detect() async {
    if (kIsWeb || !Platform.isAndroid) return none;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('device') ?? const {};
      bool flag(String key, {bool fallback = false}) => map[key] is bool ? map[key]! as bool : fallback;
      return TvDevice(
        television: flag('television'),
        leanback: flag('leanback'),
        touchscreen: flag('touchscreen', fallback: true),
        voiceSearch: flag('voiceSearch'),
      );
    } on Object catch (error) {
      debugPrint('tv: $error');
      return none;
    }
  }

  /// Starts the platform speech recognizer and returns what was said, or
  /// null when it was cancelled or is unavailable.
  static Future<String?> recognizeSpeech({String prompt = '说出主播名或直播间'}) async {
    try {
      final text = await _channel.invokeMethod<String>('recognizeSpeech', {'prompt': prompt});
      final trimmed = text?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on Object catch (error) {
      debugPrint('tv speech: $error');
      return null;
    }
  }
}

/// The device as detected before the first frame; main() overrides it.
final tvDeviceProvider = Provider<TvDevice>((ref) => TvDevice.none);

/// Whether TV mode is on for the [mode] setting on [device]: 自动 follows
/// the device, 开启 and 关闭 force it (projectors, boxes that misreport).
bool resolveTvMode(TvMode mode, TvDevice device) => switch (mode) {
  TvMode.on => true,
  TvMode.off => false,
  TvMode.auto => device.isTv,
};

/// The TV presentation the app runs with (read by `TvRoot`; widgets read
/// `TvScope.of`).
final tvConfigProvider = Provider<TvConfig>((ref) {
  final enabled = resolveTvMode(ref.watch(tvModeSetting), ref.watch(tvDeviceProvider));
  return TvConfig(enabled: enabled, focusGrowth: !ref.watch(tvPerformanceSetting));
});
