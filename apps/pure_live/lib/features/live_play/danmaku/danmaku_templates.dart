import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

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

/// The templates card above the danmaku settings: the presets, "save the
/// current look" and "use the saved one".
class DanmakuTemplatesCard extends ConsumerWidget {
  /// Creates the card.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    // Rebuild when any part of the look changes.
    for (final setting in const <Setting<Object>>[
      Settings.danmakuArea,
      Settings.danmakuTopArea,
      Settings.danmakuBottomArea,
      Settings.danmakuSpeed,
      Settings.danmakuFontSize,
      Settings.danmakuFontWeight,
      Settings.danmakuFontBorder,
      Settings.danmakuOpacity,
      Settings.enableDanmakuStroke,
    ]) {
      watchSetting(ref, setting);
    }
    final saved = watchSetting(ref, Settings.savedDanmakuTemplate);
    final current = DanmakuTemplate.of(settings);
    Future<void> use(DanmakuTemplate template) async {
      await template.apply(settings);
      AppNavigator.toast(i18n('danmaku_template_applied'));
    }

    return context.buildModernCard([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(i18n('danmaku_templates'), style: Theme.of(context).textTheme.titleSmall),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final (key, template) in DanmakuTemplate.presets)
              ChoiceChip(
                key: ValueKey('danmaku-template-$key'),
                label: Text(i18n(key)),
                selected: template.sameLook(current),
                onSelected: (_) => unawaited(use(template)),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('danmaku-template-save'),
              onPressed: () async {
                await settings.set(Settings.savedDanmakuTemplate, current.encode());
                AppNavigator.toast(i18n('danmaku_template_saved'));
              },
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: Text(i18n('live_play_template_save')),
            ),
            TextButton.icon(
              key: const ValueKey('danmaku-template-load'),
              onPressed: () async {
                if (saved.trim().isEmpty) {
                  AppNavigator.toast(i18n('danmaku_template_empty'));
                  return;
                }
                final template = DanmakuTemplate.tryDecode(saved, current);
                if (template == null) {
                  AppNavigator.toast(i18n('danmaku_template_invalid'));
                  return;
                }
                await use(template);
              },
              icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
              label: Text(i18n('live_play_template_load')),
            ),
          ],
        ),
      ),
    ]);
  }
}
