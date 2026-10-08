import 'dart:convert';

import 'package:live_store/live_store.dart';
import 'package:pure_live/platform/display_mode.dart';

/// A danmaku look in one tap (3.x `DanmakuViewingPreset` and
/// `DanmakuViewingTemplate`): the area, margins, speed, size, weight,
/// border, opacity, stroke and frame rate together.
final class DanmakuTemplate {
  /// Creates a template.
  const new({
    required this.area,
    required this.speed,
    required this.fontSize,
    required this.fontBorder,
    required this.opacity,
    this.top = 0,
    this.bottom = 0,
    this.fontWeight = 500,
    this.stroke = true,
    this.noEmojiMode = false,
    this.fps = 60,
    this.autoFps = true,
  });

  /// The current look in [settings].
  factory of(SettingsStore settings) => DanmakuTemplate(
    area: settings.get(Settings.danmakuArea),
    top: settings.get(Settings.danmakuTopArea),
    bottom: settings.get(Settings.danmakuBottomArea),
    speed: settings.get(Settings.danmakuSpeed),
    fontSize: settings.get(Settings.danmakuFontSize),
    fontWeight: settings.get(Settings.danmakuFontWeight),
    fontBorder: settings.get(Settings.danmakuFontBorder),
    opacity: settings.get(Settings.danmakuOpacity),
    stroke: settings.get(Settings.enableDanmakuStroke),
    noEmojiMode: settings.get(Settings.noEmojiMode),
    fps: settings.get(Settings.danmakuFps),
    autoFps: settings.get(Settings.danmakuAutoFps),
  );

  /// 3.x's three presets and the defaults, with their text keys.
  static const List<(String, DanmakuTemplate)> presets = [
    ('danmaku_template_best', DanmakuTemplate(area: 0.2, speed: 118, fontSize: 16, fontBorder: 1.5, opacity: 0.92)),
    ('danmaku_template_comfort', DanmakuTemplate(area: 0.35, speed: 105, fontSize: 17, fontBorder: 1.5, opacity: 0.9)),
    ('danmaku_template_dense', DanmakuTemplate(area: 0.55, speed: 138, fontSize: 15, fontBorder: 1.2, opacity: 0.88)),
    ('reset', DanmakuTemplate(area: 1, speed: 120, fontSize: 16, fontBorder: 1.5, opacity: 1)),
  ];

  /// Display area, 0 to 1.
  final double area;

  /// Pixels kept free above.
  final double top;

  /// Pixels kept free below.
  final double bottom;

  /// Speed.
  final double speed;

  /// Font size.
  final double fontSize;

  /// Font weight, 100 to 900.
  final int fontWeight;

  /// Border width.
  final double fontBorder;

  /// Opacity, 0 to 1.
  final double opacity;

  /// Stroke on.
  final bool stroke;

  /// Emotes off.
  final bool noEmojiMode;

  /// Frame rate.
  final int fps;

  /// Frame rate follows the display.
  final bool autoFps;

  /// 3.x's saved form (`savedDanmakuTemplate`, schema 2).
  String encode() => jsonEncode({
    'version': 2,
    'noEmojiMode': noEmojiMode,
    'area': area,
    'top': top,
    'bottom': bottom,
    'speed': speed,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'fontBorder': fontBorder,
    'opacity': opacity,
    'stroke': stroke,
    'fps': fps,
    'autoFps': autoFps,
  });

  /// Reads a saved template; null when it is damaged or out of range (3.x
  /// `tryDecode`: nothing is applied then). Missing optional fields take
  /// [fallback]'s.
  static DanmakuTemplate? tryDecode(String raw, DanmakuTemplate fallback) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, Object?>) return null;
      double number(String key, double min, double max) {
        final field = value[key];
        if (field is! num || !field.isFinite || field < min || field > max) throw FormatException(key);
        return field.toDouble();
      }

      bool flag(String key, {required bool otherwise}) {
        if (!value.containsKey(key)) return otherwise;
        final field = value[key];
        if (field is! bool) throw FormatException(key);
        return field;
      }

      int whole(String key, int otherwise, int min, int max) {
        if (!value.containsKey(key)) return otherwise;
        final field = value[key];
        if (field is! num || field != field.roundToDouble() || field < min || field > max) throw FormatException(key);
        return field.toInt();
      }

      return DanmakuTemplate(
        noEmojiMode: flag('noEmojiMode', otherwise: fallback.noEmojiMode),
        area: number('area', 0, 1),
        top: number('top', 0, 300),
        bottom: number('bottom', 0, 300),
        speed: number('speed', 20, 400),
        fontSize: number('fontSize', 10, 30),
        fontWeight: whole('fontWeight', fallback.fontWeight, 100, 900),
        fontBorder: number('fontBorder', 0, 4),
        opacity: number('opacity', 0, 1),
        stroke: flag('stroke', otherwise: fallback.stroke),
        fps: whole('fps', fallback.fps, 30, 240),
        autoFps: flag('autoFps', otherwise: fallback.autoFps),
      );
    } on FormatException {
      return null;
    }
  }

  /// Writes the template into [settings].
  Future<void> apply(SettingsStore settings) async {
    await settings.set(Settings.danmakuArea, area);
    await settings.set(Settings.danmakuTopArea, top);
    await settings.set(Settings.danmakuBottomArea, bottom);
    await settings.set(Settings.danmakuSpeed, speed);
    await settings.set(Settings.danmakuFontSize, fontSize);
    await settings.set(Settings.danmakuFontWeight, fontWeight);
    await settings.set(Settings.danmakuFontBorder, fontBorder);
    await settings.set(Settings.danmakuOpacity, opacity);
    await settings.set(Settings.enableDanmakuStroke, stroke);
    await settings.set(Settings.noEmojiMode, noEmojiMode);
    await settings.set(Settings.danmakuFps, fps);
    await settings.set(Settings.danmakuAutoFps, autoFps);
  }

  /// Writes a preset into [settings] as 3.x did (`_applyPreset`): the look
  /// and "frame rate follows the display"; the emote switch and the manual
  /// frame rate stay as they are.
  Future<void> applyPreset(SettingsStore settings) async {
    await settings.set(Settings.danmakuArea, area);
    await settings.set(Settings.danmakuTopArea, top);
    await settings.set(Settings.danmakuBottomArea, bottom);
    await settings.set(Settings.danmakuSpeed, speed);
    await settings.set(Settings.danmakuFontSize, fontSize);
    await settings.set(Settings.danmakuFontWeight, fontWeight);
    await settings.set(Settings.danmakuFontBorder, fontBorder);
    await settings.set(Settings.danmakuOpacity, opacity);
    await settings.set(Settings.enableDanmakuStroke, stroke);
    await settings.set(Settings.danmakuAutoFps, true);
  }

  /// The preset [current] matches (3.x `_matchingPreset`: the look, with the
  /// frame rate following the display), as its text key; null for a look
  /// of the user's own.
  static String? presetOf(DanmakuTemplate current) {
    if (!current.autoFps) return null;
    for (final (key, preset) in presets) {
      if (preset.sameLook(current)) return key;
    }
    return null;
  }

  /// Whether [other] looks the same (3.x `matches`).
  bool sameLook(DanmakuTemplate other) {
    bool close(double a, double b) => (a - b).abs() < 0.001;
    return close(area, other.area) &&
        close(top, other.top) &&
        close(bottom, other.bottom) &&
        close(speed, other.speed) &&
        close(fontSize, other.fontSize) &&
        fontWeight == other.fontWeight &&
        close(fontBorder, other.fontBorder) &&
        close(opacity, other.opacity) &&
        stroke == other.stroke;
  }
}

/// The flying layer's frame rate for the danmaku settings on [display] and
/// the display's current rate (`DanmakuOverlay.fps`, `refreshRate`): the
/// room's picture and the multi-view cells ask this one rule (N01.2 c2).
({int fps, double? refreshRate}) danmakuFrameRate({
  required bool automatic,
  required int configured,
  required String mode,
  DisplayModeInfo? display,
}) => (
  fps: resolvedDanmakuFps(
    automatic: automatic,
    configured: configured,
    mode: mode,
    maxRefreshRate: display?.maxRefreshRate,
    currentRefreshRate: display?.currentRefreshRate,
  ),
  refreshRate: (display?.currentRefreshRate ?? 0) > 0 ? display!.currentRefreshRate : null,
);

/// The danmaku frame rate in use (3.x `resolvedDanmakuFps`): the manual
/// [configured] rate, or with [automatic] the display's highest rate capped
/// by the refresh rate [mode] (`powerSaving` 60, `balanced` 60,
/// `performance` the display's).
int resolvedDanmakuFps({
  required bool automatic,
  required int configured,
  required String mode,
  double? maxRefreshRate,
  double? currentRefreshRate,
  bool pip = false,
}) {
  // The picture-in-picture danmaku goes down to 15 and saves power at 30
  // (3.x `resolveAdaptiveDanmakuFps(pip: true)`).
  final floor = pip ? 15 : 30;
  if (!automatic) return configured.clamp(floor, 240);
  final maximum = maxRefreshRate ?? 0;
  final current = currentRefreshRate ?? 0;
  final detected = maximum > 0 ? maximum : (current > 0 ? current : 60.0);
  final device = detected.round().clamp(floor, 240);
  return switch (mode) {
    'performance' => device,
    'balanced' => device.clamp(floor, 60),
    _ => device.clamp(floor, pip ? 30 : 60),
  };
}
