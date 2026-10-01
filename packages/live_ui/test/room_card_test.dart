import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

const _room = RoomCardData(
  platformId: 'douyu',
  title: 'A title',
  anchorName: 'Streamer',
  isLive: true,
  audience: RoomAudience(kind: RoomAudienceKind.onlineViewers, value: '1.2万'),
);

Widget _card(RoomCard card, {double width = 400}) => MaterialApp(
  theme: const LiveTheme(primaryColor: Colors.indigo).light,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: card),
    ),
  ),
);

void main() {
  group('RoomCard, cover layout', () {
    testWidgets('shows title, streamer, letter avatar, audience and the fallback cover', (tester) async {
      await tester.pumpWidget(_card(const RoomCard(data: _room)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-card-cover-layout')), findsOneWidget);
      expect(find.text('A title'), findsOneWidget);
      expect(find.text('Streamer'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('1.2万'), findsOneWidget);
      expect(find.byTooltip('在线 1.2万'), findsOneWidget);
      expect(find.byKey(const ValueKey('room-card-cover-fallback')), findsOneWidget);
      // Standard preset: the platform sits beside the title on a wide card.
      expect(find.text('DOUYU'), findsOneWidget);
    });

    testWidgets('an unknown figure is "pending"; offline rooms show no audience', (tester) async {
      const pending = RoomCardData(
        platformId: 'huya',
        title: 't',
        anchorName: 'n',
        isLive: true,
        audience: RoomAudience(kind: RoomAudienceKind.popularity, value: ''),
      );
      await tester.pumpWidget(_card(const RoomCard(data: pending)));
      expect(find.text('待刷新'), findsOneWidget);
      expect(find.byIcon(Icons.whatshot_rounded), findsOneWidget);

      await tester.pumpWidget(
        _card(
          const RoomCard(
            data: RoomCardData(platformId: 'huya', title: 't', anchorName: 'n'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
    });

    testWidgets('detailed preset, replay, restriction, verifying and delete', (tester) async {
      var deleted = 0;
      const data = RoomCardData(
        platformId: 'bilibili',
        title: 't',
        anchorName: 'n',
        isLive: true,
        isReplay: true,
        restrictionLabel: '付费',
      );
      await tester.pumpWidget(
        _card(
          RoomCard(
            data: data,
            appearance: RoomCardAppearance.detailed,
            statusPending: true,
            showDelete: true,
            onDelete: () => deleted++,
          ),
        ),
      );
      expect(find.text('BILIBILI'), findsOneWidget);
      expect(find.text('录播'), findsOneWidget);
      expect(find.text('付费'), findsOneWidget);
      expect(find.text('正在核验'), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('room-card-delete')));
      expect(deleted, 1);
    });

    testWidgets('tap opens, long press and right click open the menu', (tester) async {
      var taps = 0;
      var menus = 0;
      await tester.pumpWidget(_card(RoomCard(data: _room, onTap: () => taps++, onLongPress: () => menus++)));
      await tester.tap(find.text('A title'));
      await tester.longPress(find.text('A title'));
      await tester.tap(find.text('A title'), buttons: kSecondaryButton);
      expect(taps, 1);
      expect(menus, 2);
    });
  });

  group('RoomCard, compact layout', () {
    testWidgets('one row; the badges only when the card is wide enough', (tester) async {
      await tester.pumpWidget(_card(const RoomCard(data: _room, appearance: RoomCardAppearance.compact)));
      expect(find.byKey(const ValueKey('room-card-compact-layout')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsOneWidget);
      final height = tester.getSize(find.byKey(const ValueKey('room-card-compact-layout'))).height;
      expect(height, RoomCardLayoutMetrics.compactHeight(appearance: RoomCardAppearance.compact, dense: false));

      await tester.pumpWidget(
        _card(const RoomCard(data: _room, appearance: RoomCardAppearance.compact, statusPending: true), width: 250),
      );
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

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
