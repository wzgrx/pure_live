import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The display the window is on (3.x `DisplayModeInfo`): refresh rates and
/// size, from `pure_live/display_mode` (Android's activity, Windows' runner).
@immutable
final class DisplayModeInfo {
  /// Creates the info.
  const new({
    required this.currentRefreshRate,
    required this.maxRefreshRate,
    required this.supportedRefreshRates,
    this.requestedRefreshRate,
    this.width,
    this.height,
  });

  /// Reads the channel's map; missing numbers are 0.
  factory fromMap(Map<Object?, Object?> map) {
    double number(String key) => switch (map[key]) {
      final num value => value.toDouble(),
      _ => 0,
    };
    final rates = [
      for (final value in map['supportedRefreshRates'] as List<Object?>? ?? const [])
        if (value is num) value.toDouble(),
    ];
    return DisplayModeInfo(
      currentRefreshRate: number('currentRefreshRate'),
      maxRefreshRate: number('maxRefreshRate'),
      supportedRefreshRates: List.unmodifiable(rates),
      requestedRefreshRate: map['requestedRefreshRate'] is num ? number('requestedRefreshRate') : null,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
    );
  }

  /// The rate the display runs at now.
  final double currentRefreshRate;

  /// The highest rate at the current resolution.
  final double maxRefreshRate;

  /// Every rate at the current resolution, ascending.
  final List<double> supportedRefreshRates;

  /// The rate the app asked for (0 = the system decides).
  final double? requestedRefreshRate;

  /// Physical width.
  final int? width;

  /// Physical height.
  final int? height;

  /// "60 / 120 Hz".
  String get rateLabel => '${currentRefreshRate.round()} / ${maxRefreshRate.round()} Hz';

  /// "60, 90, 120 Hz", or empty.
  String get supportedLabel =>
      supportedRefreshRates.isEmpty ? '' : '${supportedRefreshRates.map((rate) => rate.round()).join(', ')} Hz';

  @override
  bool operator ==(Object other) =>
      other is DisplayModeInfo &&
      other.currentRefreshRate == currentRefreshRate &&
      other.maxRefreshRate == maxRefreshRate &&
      other.requestedRefreshRate == requestedRefreshRate &&
      other.width == width &&
      other.height == height &&
      listEquals(other.supportedRefreshRates, supportedRefreshRates);

  @override
  int get hashCode => Object.hash(
    currentRefreshRate,
    maxRefreshRate,
    requestedRefreshRate,
    width,
    height,
    Object.hashAll(supportedRefreshRates),
  );
}

/// The display mode of the window (3.x `DisplayModeService`): applies the
/// refresh-rate hint (Android) and keeps [info] current from the answers and
/// the native `displayModeChanged` reports (Android display changes; Windows
/// moves to another monitor or a mode switch).
abstract final class DisplayMode {
  static const MethodChannel _channel = MethodChannel('pure_live/display_mode');
  static bool _listening = false;

  /// The latest info; null until the first answer or where there is none.
  static final ValueNotifier<DisplayModeInfo?> info = ValueNotifier(null);

  /// Whether this platform reports display modes.
  static bool get supported => Platform.isAndroid || Platform.isWindows;

  static void _listen() {
    if (_listening || !supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'displayModeChanged' && call.arguments is Map) {
        publish(DisplayModeInfo.fromMap(call.arguments as Map<Object?, Object?>));
      }
    });
  }

  /// Takes a new [next] (public for the channel handler and tests).
  static void publish(DisplayModeInfo? next) {
    if (next != null && info.value != next) info.value = next;
  }

  static Future<void> _call(String method, [Object? arguments]) async {
    if (!supported) return;
    _listen();
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(method, arguments);
      if (result != null) publish(DisplayModeInfo.fromMap(result));
    } on PlatformException {
      // The system keeps its own choice.
    } on MissingPluginException {
      // No window yet.
    }
  }

  /// Asks for the highest rate or the system's choice (live_ui's
  /// `AdaptiveRefreshRateController` calls this on Android).
  static Future<void> applyHighRefreshRate({required bool high}) async {
    if (!Platform.isAndroid) return;
    await _call('setHighRefreshRate', {'enabled': high});
  }

  /// Reads the info again (the settings page; Windows' "detect" action).
  static Future<void> refresh() => _call('getDisplayModeInfo');
}
