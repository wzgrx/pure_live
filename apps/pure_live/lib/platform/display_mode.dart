import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

/// The rate declared on Flutter's surface while [playback] plays (U.2i,
/// revised in 4.0.x by P01: docs/T14/T14b/T14b.1/README.md "4.0.x 修订"),
/// [high] being what the refresh-rate mode asks now (touching in balanced,
/// always in performance):
///
/// - power saving: 0, the video's own frame rate is declared and the system
///   picks;
/// - balanced at rest: the highest whole multiple up to 60 (60 for 30 or 60
///   frames, 50 for 25 where the display has 50 Hz), else the lowest one
///   (120 for 24 frames at 60/90/120 Hz);
/// - balanced while touching, performance: the highest whole multiple (120,
///   not 144, for 60 frames);
/// - no rate of the display is a whole multiple (25 and 50 frames at
///   60/90/120 Hz): the highest rate. A frame then stays one period more or
///   less, and the shortest period judders least (docs/README.md/
///   research-smoothness-2026-10-02.md 1.4).
///
/// 0 too while the display's rates are not known.
double playbackRefreshRate({required PlaybackRefresh playback, required bool high, required List<double> supported}) {
  if ((playback.mode != 'balanced' && playback.mode != 'performance') || supported.isEmpty) return 0;
  final multiples = frameRateMultiples(playback.frameRate, supported);
  if (multiples.isEmpty) return supported.reduce(math.max);
  if (high) return multiples.last;
  return multiples.where((rate) => rate <= 60.5).lastOrNull ?? multiples.first;
}

/// The display mode of the window (3.x `DisplayModeService`): asks for a
/// refresh rate (Android) and keeps [info] current from the answers and the
/// native `displayModeChanged` reports (Android display changes; Windows
/// moves to another monitor or a mode switch).
///
/// How the rate is asked for (P01, docs/T14/T14b/T14b.1 "4.0.x 修订"; the
/// activity's `applyRefreshRate`), always as a number, never a category:
///
/// - the live room plays ([setPlayback]): only [playbackRefreshRate] (the
///   video's own frame rate in power saving) declared on Flutter's surface
///   as a fixed source, switched only when seamless (Android 12 and later).
///   Android ignores the window's preferred rate for a surface that declares
///   one; Android 8–11 keep that window hint;
/// - nothing plays and the high rate is asked for ([applyHighRefreshRate]):
///   the highest rate declared as a minimum (Android 16 and later), else the
///   window hint (3.x);
/// - otherwise the system's choice.
///
/// [limited] tells when the system keeps the display at 60 Hz all the same.
abstract final class DisplayMode {
  static const MethodChannel _channel = MethodChannel('pure_live/display_mode');
  static bool _listening = false;
  static bool _high = false;
  static PlaybackRefresh? _playback;

  /// How long the display must stay at 60 Hz against a request of 90 or
  /// more, while the user interacts, before [limited] turns on (P01 c3).
  static const Duration limitDelay = Duration(seconds: 3);

  // A touch counts as interaction until this long after the last finger
  // lifts (AdaptiveRefreshRateController.settleDelay).
  static const Duration _interactionGrace = Duration(milliseconds: 1500);
  static bool _watchingPointers = false;
  static int _pointers = 0;
  static Timer? _graceTimer;
  static Timer? _limitTimer;
  static bool _confirming = false;

  /// Android in tests.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? Platform.isAndroid;

  /// The latest info; null until the first answer or where there is none.
  static final ValueNotifier<DisplayModeInfo?> info = ValueNotifier(null);

  /// Whether the system holds the app at 60 Hz (P01 c3): the app asked for
  /// 90 Hz or more (balanced while touching, performance) and the display
  /// stayed at 60 for [limitDelay] while the user interacted (a still
  /// screen may idle down by design). Off again once the display runs
  /// faster. The settings' refresh-rate row says where to raise it.
  static final ValueNotifier<bool> limited = ValueNotifier(false);

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
    final previous = info.value;
    if (next == null || previous == next) return;
    info.value = next;
    // Another display or resolution: the room's rate is chosen again.
    if (_android &&
        previous != null &&
        _playback != null &&
        !listEquals(previous.supportedRefreshRates, next.supportedRefreshRates)) {
      unawaited(_applyRate());
    }
    _checkLimit();
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
  /// plays, [playbackRefreshRate] instead.
  static Future<void> applyHighRefreshRate({required bool high}) async {
    if (!_android) return;
    _high = high;
    _watchPointers();
    await _applyRate();
  }

  /// What the live room plays now, or null: nothing plays, it is paused, the
  /// room was left, the app went to the background or "播放时匹配视频帧率"
  /// is off (U.2i c2-c4). Picture-in-picture keeps it.
  static Future<void> setPlayback(PlaybackRefresh? playback) async {
    if (!_android || playback == _playback) return;
    _playback = playback;
    _watchPointers();
    await _applyRate();
  }

  /// The rate asked for now: the room's while it plays, the display's
  /// highest while the high rate is asked for, else 0 (the system's).
  static double get _requested {
    final rates = info.value?.supportedRefreshRates ?? const <double>[];
    final playback = _playback;
    if (playback != null) {
      final rate = playbackRefreshRate(playback: playback, high: _high, supported: rates);
      return rate > 0 ? rate : playback.frameRate;
    }
    return _high && rates.isNotEmpty ? rates.reduce(math.max) : 0;
  }

  static Future<void> _applyRate() {
    final playback = _playback;
    _checkLimit();
    if (playback == null) return _call('setHighRefreshRate', {'enabled': _high});
    final rate = playbackRefreshRate(
      playback: playback,
      high: _high,
      supported: info.value?.supportedRefreshRates ?? const [],
    );
    return _call('setHighRefreshRate', {
      'enabled': _high,
      // Declared on Flutter's surface: the video's own frame rate in power
      // saving (the system picks a multiple).
      'frameRate': rate > 0 ? rate : playback.frameRate,
      // The window's hint where nothing can be declared (Android 8-11); 0 is
      // the system's choice.
      'refreshRate': rate,
    });
  }

  // P01 c3: every pointer of the app, to tell interaction from a still
  // screen.
  static void _watchPointers() {
    if (_watchingPointers) return;
    _watchingPointers = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointers++;
      _graceTimer?.cancel();
      _graceTimer = null;
      _checkLimit();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_pointers > 0) _pointers--;
      if (_pointers == 0) {
        _graceTimer?.cancel();
        _graceTimer = Timer(_interactionGrace, () {
          _graceTimer = null;
          _checkLimit();
        });
      }
    }
  }

  static bool get _interacting => _pointers > 0 || _graceTimer != null;

  static void _checkLimit() {
    final current = info.value?.currentRefreshRate ?? 0;
    if (current > 60.5) limited.value = false;
    final suspect = _requested >= 89.5 && _interacting && current > 0 && current <= 60.5;
    if (!suspect) {
      _limitTimer?.cancel();
      _limitTimer = null;
      return;
    }
    _limitTimer ??= Timer(limitDelay, () => unawaited(_confirmLimit()));
  }

  static Future<void> _confirmLimit() async {
    if (_confirming) return;
    _confirming = true;
    try {
      // Not every display reports each switch: read the rate again.
      await refresh();
    } finally {
      _confirming = false;
    }
    final current = info.value?.currentRefreshRate ?? 0;
    final still = _limitTimer != null && _requested >= 89.5 && _interacting && current > 0 && current <= 60.5;
    _limitTimer = null;
    if (still) limited.value = true;
    // Still interacting: look again, so a recovery shows up too.
    _checkLimit();
  }

  /// Forgets the requests (tests).
  @visibleForTesting
  static void debugReset() {
    _high = false;
    _playback = null;
    debugAndroid = null;
    info.value = null;
    limited.value = false;
    _pointers = 0;
    _graceTimer?.cancel();
    _graceTimer = null;
    _limitTimer?.cancel();
    _limitTimer = null;
    _confirming = false;
    if (_watchingPointers) GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _watchingPointers = false;
  }

  /// Reads the info again (the settings page; Windows' "detect" action).
  static Future<void> refresh() => _call('getDisplayModeInfo');
}
