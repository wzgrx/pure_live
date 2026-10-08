import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

const _live = RoomCardData(
  platformId: 'douyu',
  platformName: '斗鱼',
  title: 'A rather long broadcast title that does not fit',
  anchorName: 'Streamer',
  isLive: true,
  audience: RoomAudience(kind: RoomAudienceKind.popularity, value: '84.7万'),
);

Widget _host(Widget child, {double width = 188, ThemeData? theme}) => MaterialApp(
  theme: theme ?? const LiveTheme(primaryColor: Colors.blue).light,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('LiveRoomCard (docs/A-界面设计/A09-浏览界面/A09.1-房间卡片)', () {
    testWidgets('c1, c6: cover, avatar, one-line title, streamer; the audience bottom right in 12-point figures', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live)));
      final card = tester.getRect(find.byType(LiveRoomCard));
      final cover = tester.getRect(find.byType(AspectRatio).first);
      expect(cover.width / cover.height, closeTo(16 / 9, 0.01));
      // The caption is 64 under the cover (U.4a; 3.x's dense ListTile).
      expect(card.height - cover.height, 64);
      final title = tester.widget<Text>(find.byKey(const ValueKey('room-card-title')));
      expect(title.maxLines, 1);
      expect(find.text('Streamer'), findsOneWidget);
      expect(find.text('S'), findsOneWidget); // letter avatar
      final audience = tester.getRect(find.byKey(const ValueKey('cover-audience-metric')));
      expect(audience.right, closeTo(cover.right - 8, 0.5));
      expect(audience.bottom, closeTo(cover.bottom - 8, 0.5));
      final figure = tester.widget<Text>(find.text('84.7万'));
      expect(figure.style?.fontSize, 12);
      expect(figure.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.byIcon(AppIcons.audienceHeat), findsOneWidget);
      // Single-platform lists do not mark the platform ("automatic").
      expect(find.byKey(const ValueKey('room-card-platform-badge')), findsNothing);
    });

    testWidgets('c2: the platform as logo and name on the top left: automatic in mixed lists, always, hidden', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live, mixedPlatforms: true)));
      final badge = find.byKey(const ValueKey('room-card-platform-badge'));
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('斗鱼')), findsOneWidget);
      expect(find.descendant(of: badge, matching: find.byType(PlatformLogo)), findsOneWidget);
      final cover = tester.getRect(find.byType(AspectRatio).first);
      expect(tester.getTopLeft(badge), cover.topLeft + const Offset(8, 8));

      await tester.pumpWidget(_host(const LiveRoomCard(data: _live, appearance: RoomCardAppearance.detailed)));
      expect(badge, findsOneWidget);
      final hidden = RoomCardAppearance.standard.withPlatformBadgeMode(RoomCardPlatformBadgeMode.hidden);
      await tester.pumpWidget(_host(LiveRoomCard(data: _live, appearance: hidden, mixedPlatforms: true)));
      expect(badge, findsNothing);
      expect(LiveRoomCard.showsPlatform(RoomCardAppearance.standard, mixedPlatforms: false), isFalse);
    });

    testWidgets('c3, c4, c7: replay in the primary colour; offline dimmed and marked; restrictions bottom left', (
      tester,
    ) async {
      const replay = RoomCardData(platformId: 'huya', title: 't', anchorName: 'n', isReplay: true);
      await tester.pumpWidget(_host(const LiveRoomCard(data: replay)));
      final chip = tester.widget<CoverChip>(find.byKey(const ValueKey('room-card-replay-badge')));
      final theme = Theme.of(tester.element(find.byType(LiveRoomCard)));
      expect(chip.background, theme.colorScheme.primary);
      expect(find.text('录播'), findsOneWidget);

      const offline = RoomCardData(
        platformId: 'huya',
        title: 't',
        anchorName: 'n',
        isOffline: true,
        restrictionLabel: '付费',
      );
      await tester.pumpWidget(_host(const LiveRoomCard(data: offline)));
      expect(find.byKey(const ValueKey('room-card-offline-dim')), findsOneWidget);
      expect(find.text('未开播'), findsOneWidget);
      final cover = tester.getRect(find.byType(AspectRatio).first);
      final restriction = tester.getRect(find.byKey(const ValueKey('room-card-restriction')));
      expect(restriction.bottomLeft, cover.bottomLeft + const Offset(8, -8));
      expect(find.text('付费'), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
    });

    testWidgets('c1, c5: checking replaces the status; a missing cover shows the TV placeholder, not "offline"', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live, statusPending: true, statusPendingLabel: '状态待确认')));
      expect(find.text('状态待确认'), findsOneWidget);
      expect(find.byIcon(AppIcons.statusPending), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
      expect(find.byKey(const ValueKey('room-card-cover-placeholder')), findsOneWidget);
      expect(find.byIcon(AppIcons.coverPlaceholder), findsOneWidget);
      expect(find.byIcon(AppIcons.networkError), findsNothing);
    });

    testWidgets('c3: colour roles in both themes (white light, container dark); history keeps its delete button', (
      tester,
    ) async {
      var deleted = 0;
      await tester.pumpWidget(_host(LiveRoomCard(data: _live, showDelete: true, onDelete: () => deleted++)));
      final light = Theme.of(tester.element(find.byType(LiveRoomCard))).colorScheme;
      Material surface() => tester.widget<Material>(find.byKey(const ValueKey('room-card-surface')));
      expect(surface().color, light.surfaceContainerLowest);
      await tester.tap(find.byKey(const ValueKey('room-card-delete')));
      expect(deleted, 1);

      await tester.pumpWidget(
        _host(
          const LiveRoomCard(data: _live),
          theme: const LiveTheme(primaryColor: Colors.blue).dark,
        ),
      );
      await tester.pumpAndSettle();
      final dark = Theme.of(tester.element(find.byType(LiveRoomCard))).colorScheme;
      expect(surface().color, dark.surfaceContainer);
      final title = tester.widget<Text>(find.byKey(const ValueKey('room-card-title')));
      expect(title.style?.color, dark.onSurface);
    });

    testWidgets('A04.1: the cover chips grow at most 1.3× with the text size and stay inside their capsule', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _host(const LiveRoomCard(data: _live)),
        ),
      );
      final text = find.descendant(of: find.byType(CoverChip), matching: find.text('84.7万'));
      expect(MediaQuery.textScalerOf(tester.element(text)).scale(10) / 10, closeTo(1.3, 0.001));
      // A line of the chip's words at that size fits the 22-high capsule.
      final style = tester.widget<Text>(text).style!;
      expect(style.fontSize! * style.height! * 1.3, lessThanOrEqualTo(22));
    });

    testWidgets('appendix A 14: tap opens, long press and right click open the dialog', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _host(LiveRoomCard(data: _live, onTap: () => calls.add('tap'), onLongPress: () => calls.add('menu'))),
      );
      await tester.tap(find.byType(LiveRoomCard));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(LiveRoomCard));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LiveRoomCard), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(calls, ['tap', 'menu', 'menu']);
    });

    testWidgets('c9: a mouse tints the card and shows the whole title; keyboard focus draws the outline', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(_host(LiveRoomCard(data: _live, onTap: () => opened++)));
      final scheme = Theme.of(tester.element(find.byType(LiveRoomCard))).colorScheme;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 500));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(LiveRoomCard)));
      await tester.pump();
      expect(
        tester.widget<Material>(find.byKey(const ValueKey('room-card-surface'))).color,
        scheme.surfaceContainerHigh,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip(_live.title), findsOneWidget); // the whole title on hover
      await mouse.moveTo(const Offset(500, 500));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ring = tester.widget<DecoratedBox>(find.byKey(const ValueKey('room-card-ring')));
      expect((ring.decoration as BoxDecoration).border?.top.color, scheme.primary);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('the compact row of the "简洁" preset (3.x), with the platform badge in mixed lists', (tester) async {
      await tester.pumpWidget(
        _host(const LiveRoomCard(data: _live, appearance: RoomCardAppearance.compact), width: 393),
      );
      expect(find.byKey(const ValueKey('room-card-compact-layout')), findsOneWidget);
      expect(find.text('84.7万'), findsOneWidget);
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live, appearance: RoomCardAppearance.compact)));
      // Narrow: no figures beside the title (3.x: from 260).
      expect(find.text('84.7万'), findsNothing);
    });

    testWidgets('A09.11: the introduction line takes the second line; the size, the avatar and RoomRow keep the name', (
      tester,
    ) async {
      const channel = RoomCardData(
        platformId: 'picarto',
        title: 'Streamer',
        anchorName: 'Streamer',
        introLine: 'Home of the art stream',
      );
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live)));
      final size = tester.getSize(find.byType(LiveRoomCard));
      for (final appearance in [RoomCardAppearance.standard, RoomCardAppearance.compact]) {
        await tester.pumpWidget(_host(LiveRoomCard(data: channel, appearance: appearance)));
        final line = tester.widget<Text>(find.byKey(const ValueKey('room-card-anchor-name')));
        expect(line.data, 'Home of the art stream', reason: appearance.toString());
        expect(line.maxLines, 1);
        expect(find.text('S'), findsOneWidget, reason: "the avatar's letter is the streamer's");
      }
      await tester.pumpWidget(_host(const LiveRoomCard(data: channel)));
      expect(tester.getSize(find.byType(LiveRoomCard)), size);
      await tester.pumpWidget(_host(const RoomRow(data: channel), width: 393));
      expect(find.text('Home of the art stream'), findsNothing);
      expect(find.text('Streamer'), findsNWidgets(2));
      const plain = RoomCardData(platformId: 'picarto', title: 'Streamer', anchorName: 'Streamer');
      expect(channel == plain, isFalse);
      expect(channel.hashCode == plain.hashCode, isFalse);
    });

    testWidgets('c8: the skeleton is the size of the card and has no animation', (tester) async {
      await tester.pumpWidget(_host(const RoomCardSkeleton()));
      final skeleton = tester.getSize(find.byKey(const ValueKey('room-card-skeleton')));
      await tester.pumpWidget(_host(const LiveRoomCard(data: _live)));
      final card = tester.getSize(find.byType(LiveRoomCard));
      expect(skeleton, card);
      await tester.pumpWidget(_host(const RoomCardSkeleton()));
      expect(tester.hasRunningAnimations, isFalse);
      expect(LiveRoomCardMetrics.extent(itemWidth: 188, dense: true), closeTo(188 * 9 / 16 + 64, 0.01));
      expect(LiveRoomCardMetrics.captionHeight(dense: false), 72);
    });
  });

  group('RoomRow (U.4c c5)', () {
    testWidgets('the avatar with the platform logo, the streamer and the last title; 64 high', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _host(RoomRow(data: _live, onTap: () => calls.add('tap'), onLongPress: () => calls.add('menu')), width: 393),
      );
      expect(tester.getSize(find.byType(RoomRow)).height, 64);
      expect(find.byKey(const ValueKey('room-row-platform')), findsOneWidget);
      final name = tester.getTopLeft(find.text('Streamer'));
      final title = tester.getTopLeft(find.text(_live.title));
      expect(name.dy, lessThan(title.dy));
      await tester.tap(find.byType(RoomRow));
      await tester.longPress(find.byType(RoomRow));
      await tester.tap(find.byType(RoomRow), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(calls, ['tap', 'menu', 'menu']);
    });
  });

  group('FollowPill (U.2a change 12, U.4a c11)', () {
    testWidgets('"＋ 关注" in the primary colour, "✓ 已关注" grey; null greys it out', (tester) async {
      var pressed = 0;
      Widget pill({required bool followed, bool enabled = true}) => _host(
        FollowPill(
          followed: followed,
          followLabel: '关注',
          followedLabel: '已关注',
          onPressed: enabled ? () => pressed++ : null,
        ),
      );
      await tester.pumpWidget(pill(followed: false));
      expect(find.text('关注'), findsOneWidget);
      expect(find.byIcon(AppIcons.follow), findsOneWidget);
      await tester.tap(find.byType(FollowPill));
      expect(pressed, 1);
      await tester.pumpWidget(pill(followed: true));
      expect(find.text('已关注'), findsOneWidget);
      expect(find.byIcon(AppIcons.followed), findsOneWidget);
      await tester.pumpWidget(pill(followed: true, enabled: false));
      await tester.tap(find.byType(FollowPill));
      expect(pressed, 1);
    });
  });

  group('GridColumns (UI_PLAN §5.3, U.4a c15)', () {
    test('room cards: the table of U.4a (the side rail takes 81 from 600 up)', () {
      int columns(double window) => GridColumns.rooms(width: window >= 600 ? window - 81 : window, windowWidth: window);
      expect([360.0, 393.0, 600.0, 740.0, 852.0, 1024.0, 1280.0, 1440.0, 1920.0, 2560.0].map(columns), [
        2, 2, 2, 3, 4, 5, 5, 6, 8, 8, //
      ]);
      // A page without the rail (area rooms, U.4e).
      int page(double window) => GridColumns.rooms(width: window, windowWidth: window);
      expect([393.0, 600.0, 852.0, 1024.0, 1280.0, 1440.0, 1920.0].map(page), [2, 3, 4, 5, 6, 6, 8]);
      expect(GridColumns.itemWidth(width: 393, columns: 2), closeTo(187.5, 0.01));
    });

    test('area cards: 3–10 columns with 110 / 130 / 150 (U.4d c5, U.4f c6)', () {
      int columns(double window) => GridColumns.areas(width: window >= 600 ? window - 81 : window, windowWidth: window);
      expect([360.0, 393.0, 680.0, 700.0, 852.0, 1024.0, 1280.0, 1440.0, 1920.0].map(columns), [
        3, 3, 4, 4, 5, 6, 7, 8, 10, //
      ]);
      expect(GridColumns.areas(width: 1280, windowWidth: 1280), 8);
      expect(WindowWidthClass.of(599), WindowWidthClass.compact);
      expect(WindowWidthClass.of(840), WindowWidthClass.expanded);
      expect(WindowWidthClass.of(1600), WindowWidthClass.extraLarge);
    });
  });

  group('showAdaptivePanel', () {
    testWidgets('the same content from the bottom, or on the right 360 wide; ✕ closes it', (tester) async {
      Future<void> open(Size size, {required bool side}) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAdaptivePanel<void>(
                  context,
                  side: side,
                  builder: (_) => const PanelHeader(title: '全部平台', closeTooltip: '关闭'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      addTearDown(tester.view.reset);
      await open(const Size(393, 852), side: false);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('panel-close')));
      await tester.pumpAndSettle();
      expect(find.text('全部平台'), findsNothing);

      await open(const Size(1280, 800), side: true);
      final panel = tester.getRect(find.byKey(const ValueKey('side-panel')));
      expect(panel.width, sidePanelWidth);
      expect(panel.right, 1280);
      expect(panel.height, 800);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('全部平台'), findsNothing);
    });
  });
}
