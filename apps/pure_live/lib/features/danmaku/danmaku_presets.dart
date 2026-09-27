import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';

/// A danmaku look in one step (F-DM-02 位置预设): area, margins, speed and
/// text. The values are 3.x's `DanmakuViewingPreset`s.
@immutable
final class DanmakuPreset {
  const new({
    required this.name,
    required this.area,
    required this.speed,
    required this.fontSize,
    required this.strokeWidth,
    required this.opacity,
    this.top = 0,
    this.bottom = 0,
    this.fontWeight = 500,
    this.stroke = true,
  });

  final String name;
  final double area;
  final double top;
  final double bottom;
  final double speed;
  final double fontSize;
  final int fontWeight;
  final double strokeWidth;
  final double opacity;
  final bool stroke;

  /// Writes the preset; the frame rate goes back to automatic.
  Future<void> apply(SettingsStore settings) async {
    await settings.set(Settings.danmakuArea, area);
    await settings.set(Settings.danmakuTopArea, top);
    await settings.set(Settings.danmakuBottomArea, bottom);
    await settings.set(Settings.danmakuSpeed, speed);
    await settings.set(Settings.danmakuFontSize, fontSize);
    await settings.set(Settings.danmakuFontWeight, fontWeight);
    await settings.set(Settings.danmakuStrokeWidth, strokeWidth);
    await settings.set(Settings.danmakuOpacity, opacity);
    await settings.set(Settings.danmakuStroke, stroke);
    await settings.set(Settings.danmakuAutoFps, true);
  }

  /// Whether [settings] hold this preset now.
  bool matches(SettingsStore settings) {
    bool near(double a, double b) => (a - b).abs() < 0.001;
    return near(settings.get(Settings.danmakuArea), area) &&
        near(settings.get(Settings.danmakuTopArea), top) &&
        near(settings.get(Settings.danmakuBottomArea), bottom) &&
        near(settings.get(Settings.danmakuSpeed), speed) &&
        near(settings.get(Settings.danmakuFontSize), fontSize) &&
        settings.get(Settings.danmakuFontWeight) == fontWeight &&
        near(settings.get(Settings.danmakuStrokeWidth), strokeWidth) &&
        near(settings.get(Settings.danmakuOpacity), opacity) &&
        settings.get(Settings.danmakuStroke) == stroke;
  }
}

/// The presets, in 3.x's order; the last one restores the defaults.
const danmakuPresets = [
  DanmakuPreset(name: '最佳观感', area: 0.20, speed: 118, fontSize: 16, strokeWidth: 1.5, opacity: 0.92),
  DanmakuPreset(name: '舒适', area: 0.35, speed: 105, fontSize: 17, strokeWidth: 1.5, opacity: 0.90),
  DanmakuPreset(name: '密集', area: 0.55, speed: 138, fontSize: 15, strokeWidth: 1.2, opacity: 0.88),
  DanmakuPreset(name: '恢复默认', area: 1, speed: 120, fontSize: 16, strokeWidth: 1.5, opacity: 1),
];

/// The user's own danmaku style (F-DM-02 样式模板), stored as 3.x's JSON
/// (`DanmakuViewingTemplate` schema 2) in [Settings.danmakuTemplate].
abstract final class DanmakuTemplate {
  /// Saves the current style.
  static Future<void> save(SettingsStore settings) => settings.set(
    Settings.danmakuTemplate,
    jsonEncode({
      'version': 2,
      'noEmojiMode': settings.get(Settings.danmakuNoEmoji),
      'area': settings.get(Settings.danmakuArea),
      'top': settings.get(Settings.danmakuTopArea),
      'bottom': settings.get(Settings.danmakuBottomArea),
      'speed': settings.get(Settings.danmakuSpeed),
      'fontSize': settings.get(Settings.danmakuFontSize),
      'fontWeight': settings.get(Settings.danmakuFontWeight),
      'fontBorder': settings.get(Settings.danmakuStrokeWidth),
      'opacity': settings.get(Settings.danmakuOpacity),
      'stroke': settings.get(Settings.danmakuStroke),
      'fps': settings.get(Settings.danmakuFps),
      'autoFps': settings.get(Settings.danmakuAutoFps),
    }),
  );

  /// Whether a template is saved.
  static bool exists(SettingsStore settings) => settings.get(Settings.danmakuTemplate).isNotEmpty;

  /// Restores the saved style; false when there is none or it is damaged.
  /// Each value goes through its setting's range, so a damaged field keeps
  /// the current value instead of failing the whole template.
  static Future<bool> restore(SettingsStore settings) async {
    final raw = settings.get(Settings.danmakuTemplate);
    if (raw.isEmpty) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return false;
    }
    if (decoded is! Map<String, Object?>) return false;
    Future<void> put<T extends Object>(Setting<T> setting, Object? value) async {
      final normalized = setting.decode(value);
      if (normalized != null) await settings.set(setting, normalized);
    }

    await put(Settings.danmakuNoEmoji, decoded['noEmojiMode']);
    await put(Settings.danmakuArea, decoded['area']);
    await put(Settings.danmakuTopArea, decoded['top']);
    await put(Settings.danmakuBottomArea, decoded['bottom']);
    await put(Settings.danmakuSpeed, decoded['speed']);
    await put(Settings.danmakuFontSize, decoded['fontSize']);
    await put(Settings.danmakuFontWeight, decoded['fontWeight']);
    await put(Settings.danmakuStrokeWidth, decoded['fontBorder']);
    await put(Settings.danmakuOpacity, decoded['opacity']);
    await put(Settings.danmakuStroke, decoded['stroke']);
    await put(Settings.danmakuFps, decoded['fps']);
    await put(Settings.danmakuAutoFps, decoded['autoFps']);
    return true;
  }
}
