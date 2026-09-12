import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart';

void main() {
  test('each viewing preset only matches its actual rendered values', () {
    for (final preset in DanmakuViewingPreset.values) {
      expect(
        preset.matches(
          area: preset.area,
          top: preset.top,
          bottom: preset.bottom,
          speed: preset.speed,
          fontSize: preset.fontSize,
          fontWeight: preset.fontWeight,
          fontBorder: preset.fontBorder,
          opacity: preset.opacity,
          stroke: preset.stroke,
          autoFps: true,
        ),
        isTrue,
        reason: preset.id,
      );
      expect(
        preset.matches(
          area: preset.area + 0.01,
          top: preset.top,
          bottom: preset.bottom,
          speed: preset.speed,
          fontSize: preset.fontSize,
          fontWeight: preset.fontWeight,
          fontBorder: preset.fontBorder,
          opacity: preset.opacity,
          stroke: preset.stroke,
          autoFps: true,
        ),
        isFalse,
        reason: '${preset.id} must clear selection after manual edits',
      );
    }
  });

  test('preset selection clears when dynamic FPS is disabled', () {
    final preset = DanmakuViewingPreset.values.first;
    expect(
      preset.matches(
        area: preset.area,
        top: preset.top,
        bottom: preset.bottom,
        speed: preset.speed,
        fontSize: preset.fontSize,
        fontWeight: preset.fontWeight,
        fontBorder: preset.fontBorder,
        opacity: preset.opacity,
        stroke: preset.stroke,
        autoFps: false,
      ),
      isFalse,
    );
  });

  test('saved viewing template round trips all visual fields', () {
    const template = DanmakuViewingTemplate(
      noEmojiMode: true,
      area: 0.42,
      top: 12,
      bottom: 34,
      speed: 180,
      fontSize: 21,
      fontWeight: 700,
      fontBorder: 2.5,
      opacity: 0.64,
      stroke: false,
      fps: 144,
      autoFps: false,
    );

    final decoded = DanmakuViewingTemplate.tryDecode(
      template.encode(),
      fallbackNoEmojiMode: false,
      fallbackFontWeight: 500,
      fallbackStroke: true,
      fallbackFps: 60,
      fallbackAutoFps: true,
    );

    expect(decoded, isNotNull);
    expect(decoded!.noEmojiMode, isTrue);
    expect(decoded.area, 0.42);
    expect(decoded.top, 12);
    expect(decoded.bottom, 34);
    expect(decoded.speed, 180);
    expect(decoded.fontSize, 21);
    expect(decoded.fontWeight, 700);
    expect(decoded.fontBorder, 2.5);
    expect(decoded.opacity, 0.64);
    expect(decoded.stroke, isFalse);
    expect(decoded.fps, 144);
    expect(decoded.autoFps, isFalse);
  });

  test('legacy template preserves settings that were not stored yet', () {
    final decoded = DanmakuViewingTemplate.tryDecode(
      '{"area":0.2,"top":0,"bottom":0,"speed":118,"fontSize":16,'
      '"fontBorder":1.5,"opacity":0.92}',
      fallbackNoEmojiMode: true,
      fallbackFontWeight: 600,
      fallbackStroke: false,
      fallbackFps: 90,
      fallbackAutoFps: false,
    );

    expect(decoded, isNotNull);
    expect(decoded!.noEmojiMode, isTrue);
    expect(decoded.fontWeight, 600);
    expect(decoded.stroke, isFalse);
    expect(decoded.fps, 90);
    expect(decoded.autoFps, isFalse);
  });

  test('malformed and out-of-range templates are rejected as a whole', () {
    DanmakuViewingTemplate? decode(String raw) => DanmakuViewingTemplate.tryDecode(
      raw,
      fallbackNoEmojiMode: false,
      fallbackFontWeight: 500,
      fallbackStroke: true,
      fallbackFps: 60,
      fallbackAutoFps: true,
    );

    expect(
      decode(
        '{"area":0.2,"top":0,"bottom":0,"speed":118,"fontSize":16,'
        '"fontBorder":1.5,"opacity":"bad"}',
      ),
      isNull,
    );
    expect(
      decode(
        '{"area":0.2,"top":0,"bottom":0,"speed":999,"fontSize":16,'
        '"fontBorder":1.5,"opacity":0.9}',
      ),
      isNull,
    );
    expect(
      decode(
        '{"area":0.2,"top":0,"bottom":0,"speed":118,"fontSize":16,'
        '"fontBorder":1.5,"opacity":0.9,"fps":59.5}',
      ),
      isNull,
    );
    expect(decode('[1,2,3]'), isNull);
  });
}
