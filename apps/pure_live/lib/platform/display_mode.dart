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

/// What the live room plays, for the display's refresh rate (U.2i): the
/// video's frame rate and the "界面刷新率" mode.
@immutable
final class PlaybackRefresh {
  /// Creates the facts.
  const new({required this.frameRate, required this.mode});

  /// Frames a second ([normalizeFrameRate]d).
  final double frameRate;

  /// `powerSaving`, `balanced` or `performance`.
  final String mode;

  @override
  bool operator ==(Object other) => other is PlaybackRefresh && other.frameRate == frameRate && other.mode == mode;

  @override
  int get hashCode => Object.hash(frameRate, mode);
}

/// 23.976 → 24, 29.97 → 30, 59.94 → 60: a rate within 0.5 % of a whole
/// number is that number.
double normalizeFrameRate(double fps) {
  final whole = fps.roundToDouble();
  return (fps - whole).abs() <= whole * 0.005 ? whole : fps;
}

/// The rates of [supported] that are a whole multiple of [fps] (within
/// 0.5 %), ascending: 60 and 120 for 30 frames on a 60/90/120 Hz display.
List<double> frameRateMultiples(double fps, List<double> supported) {
  if (fps <= 0) return const [];
  return [
    for (final rate in [...supported]..sort())
      if (rate >= fps * 0.995 && (rate - (rate / fps).round() * fps).abs() <= rate * 0.005) rate,
  ];
}

/// The refresh rate the window asks for while [playback] plays (U.2i, see
/// docs/ui/compare/U.2i/v4-policy.jpg), [high] being what the refresh-rate
/// mode asks now (touching in balanced, always in performance):
///
/// - power saving: 0, the system's choice (the declared frame rate leads it);
/// - balanced: the highest whole multiple while touching, else the highest
///   one up to 60 (60 for 30 or 60 frames, 50 for 25 or 50);
/// - performance: the highest whole multiple (120, not 144, for 60 frames).
///
/// Null keeps 3.x's choice (the highest rate when [high], else the system's):
/// no rate of the display is a multiple, or a mode that asks for nothing.
double? playbackRefreshRate({required PlaybackRefresh playback, required bool high, required List<double> supported}) {
  final multiples = frameRateMultiples(playback.frameRate, supported);
  if (multiples.isEmpty) return null;
  return switch (playback.mode) {
    'performance' => high ? multiples.last : null,
    'balanced' when high => multiples.last,
    'balanced' => multiples.where((rate) => rate <= 60.5).lastOrNull,
    _ => 0,
  };
}

/// The display mode of the window (3.x `DisplayModeService`): applies the
/// refresh-rate hint (Android) and keeps [info] current from the answers and
/// the native `displayModeChanged` reports (Android display changes; Windows
/// moves to another monitor or a mode switch).
///
/// U.2i: while the live room plays ([setPlayback]) the video's frame rate is
/// declared to the system (Android 12 and later: only switched when
/// seamless) and the window's preferred rate becomes a whole multiple of it
/// ([playbackRefreshRate]).
abstract final class DisplayMode {
  static const MethodChannel _channel = MethodChannel('pure_live/display_mode');
  static bool _listening = false;
  static bool _high = false;
  static PlaybackRefresh? _playback;

  /// Android in tests.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? Platform.isAndroid;

  /// The latest info; null until the first answer or where there is none.
  static final ValueNotifier<DisplayModeInfo?> info = ValueNotifier(null);

  /// Whether this platform reports display modes.
  static bool get supported => _android || Platform.isWindows;

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
  /// `AdaptiveRefreshRateController` calls this on Android); while a video
  /// plays, a whole multiple of its frame rate instead (U.2i).
  static Future<void> applyHighRefreshRate({required bool high}) async {
    if (!_android) return;
    _high = high;
    await _applyRate();
  }

  /// What the live room plays now, or null: nothing plays, it is paused, the
  /// room was left, the app went to the background or "播放时匹配视频帧率"
  /// is off (U.2i c2-c4). Picture-in-picture keeps it.
  static Future<void> setPlayback(PlaybackRefresh? playback) async {
    if (!_android || playback == _playback) return;
    _playback = playback;
    await _call('setVideoFrameRate', {'fps': playback?.frameRate ?? 0.0});
    await _applyRate();
  }

  static Future<void> _applyRate() {
    final playback = _playback;
    final rate = playback == null
        ? null
        : playbackRefreshRate(
            playback: playback,
            high: _high,
            supported: info.value?.supportedRefreshRates ?? const [],
          );
    return _call('setHighRefreshRate', {'enabled': _high, 'refreshRate': ?rate});
  }

  /// Forgets the requests (tests).
  @visibleForTesting
  static void debugReset() {
    _high = false;
    _playback = null;
    debugAndroid = null;
    info.value = null;
  }

  /// Reads the info again (the settings page; Windows' "detect" action).
  static Future<void> refresh() => _call('getDisplayModeInfo');
}
