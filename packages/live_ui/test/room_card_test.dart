import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  group('RoomCardLayoutMetrics', () {
    test('a grid cell grows with the font settings (3.x measured the defaults)', () {
      final normal = RoomCardLayoutMetrics.gridMainAxisExtent(
        itemWidth: 320,
        appearance: RoomCardAppearance.standard,
        dense: false,
      );
      expect(normal, 320 * 9 / 16 + 84);
      final large = RoomCardLayoutMetrics.gridMainAxisExtent(
        itemWidth: 320,
        appearance: RoomCardAppearance.standard,
        dense: false,
        fontSizes: const LiveFontSizes(bodyMedium: 26, titleMedium: 30),
      );
      expect(large, closeTo(320 * 9 / 16 + (30 * 1.2 + 3 + 26 * 1.2 + 20), 1e-9));
      expect(
        RoomCardLayoutMetrics.compactHeight(appearance: RoomCardAppearance.compact, dense: true, hasAction: true),
        48 + 16,
      );
    });
  });

  group('RoomCardAppearance', () {
    test('round-trips and matches its presets', () {
      for (final preset in [RoomCardPreset.compact, RoomCardPreset.standard, RoomCardPreset.detailed]) {
        final appearance = RoomCardAppearance.fromPreset(preset);
        expect(RoomCardAppearance.fromJson(appearance.toJson()), appearance);
        expect(RoomCardAppearance.presetOf(appearance), preset);
      }
      expect(RoomCardAppearance.presetOf(RoomCardAppearance.standard.copyWith(cornerRadius: 3)), RoomCardPreset.custom);
      expect(RoomCardAppearance.standard.copyWith(cornerRadius: 99).cornerRadius, 32);
      expect(
        RoomCardAppearance.standard.withPlatformBadgeMode(RoomCardPlatformBadgeMode.always).platformBadgeMode,
        RoomCardPlatformBadgeMode.always,
      );
    });

    test("reads 3.x's older keys", () {
      final read = RoomCardAppearance.fromJson(const {
        'showAsListTile': true,
        'showPlatform': true,
        'showSubtitle': false,
        'showRecordBadge': false,
        'cardBorderRadius': 8,
      });
      expect(read.layout, RoomCardLayout.compact);
      expect(read.showPlatformBadge, isTrue);
      expect(read.automaticPlatformBadge, isFalse);
      expect(read.showAnchorName, isFalse);
      expect(read.showReplayBadge, isFalse);
      expect(read.cornerRadius, 8);
    });

    test('repairs the 3.1.4 compact snapshot; strict imports reject bad values', () {
      final snapshot = {
        'showAvatar': false,
        'showAnchorName': false,
        'showPlatformBadge': false,
        'automaticPlatformBadge': false,
        'showAudience': true,
        'showReplayBadge': true,
        'cornerRadius': 12,
      };
      expect(RoomCardAppearance.fromJson(snapshot, fallback: RoomCardAppearance.compact), RoomCardAppearance.compact);
      expect(() => RoomCardAppearance.fromJson(const {'layout': 'grid'}, strict: true), throwsFormatException);
      expect(RoomCardAppearance.fromJson(const {'layout': 'grid'}).layout, RoomCardLayout.cover);
    });
  });
}
