import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  Widget host(Widget child, {double width = 200}) => MaterialApp(
    theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('live card shows badge, audience, name and title; taps and menu fire', (tester) async {
    var taps = 0;
    var menus = 0;
    await tester.pumpWidget(
      host(
        RoomCardView(
          platformId: 'douyu',
          anchorName: '主播',
          title: '标题',
          isLive: true,
          audience: '355.1万',
          liveFor: '01:24',
          onTap: () => taps++,
          onMenu: () => menus++,
        ),
        // The test font draws every glyph a full em wide: room for both labels.
        width: 260,
      ),
    );
    expect(find.text('直播 01:24'), findsOneWidget);
    expect(find.text('355.1万'), findsOneWidget);
    expect(find.text('主播'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    await tester.tap(find.byType(RoomCardView));
    await tester.longPress(find.byType(RoomCardView));
    expect((taps, menus), (1, 1));
    expect(find.bySemanticsLabel('主播，直播中，标题'), findsOneWidget);
  });

  testWidgets('at twice the text size the live badge and the audience stay side by side', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(
          const RoomCardView(
            platformId: 'douyu',
            anchorName: '主播',
            title: '标题',
            isLive: true,
            // The test font draws every glyph a full em wide.
            audience: '1.2万',
            liveFor: '01:24',
          ),
          width: 172,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('直播'), findsOneWidget, reason: 'the duration goes first, the word stays');
    final badge = tester.getRect(find.byType(LiveBadge));
    final audience = tester.getRect(find.byType(CoverLabel));
    final cover = tester.getRect(find.byType(AspectRatio));
    expect(badge.right, lessThanOrEqualTo(audience.left), reason: 'no overlap');
    expect(badge.left, greaterThanOrEqualTo(cover.left));
    expect(audience.right, lessThanOrEqualTo(cover.right));
  });

  testWidgets('compact density puts name and title on one line', (tester) async {
    await tester.pumpWidget(
      host(
        const RoomCardView(
          platformId: 'unknown',
          anchorName: '主播',
          title: '标题',
          isLive: false,
          density: CardDensity.compact,
        ),
      ),
    );
    expect(find.text('直播'), findsNothing);
    expect(find.text('U'), findsOneWidget);
    expect(find.textContaining('主播 · 标题', findRichText: true), findsOneWidget);
  });

  testWidgets('F-FAV-01: a recording room carries 录制中 on its card and its row', (tester) async {
    await tester.pumpWidget(
      host(const RoomCardView(platformId: 'douyu', anchorName: '主播', title: '标题', isLive: true, recording: true)),
    );
    expect(find.byType(RecordingBadge), findsOneWidget);
    expect(find.text('录制中'), findsOneWidget);
    expect(find.bySemanticsLabel('主播，直播中，录制中，标题'), findsOneWidget);

    await tester.pumpWidget(host(const RoomCardView(platformId: 'douyu', anchorName: '主播', title: '标题', isLive: true)));
    expect(find.text('录制中'), findsNothing);

    await tester.pumpWidget(
      host(const OfflineRoomRow(platformId: 'cc', anchorName: '主播', tag: '未支持', recording: true), width: 360),
    );
    expect(find.text('未支持'), findsOneWidget);
    expect(find.text('录制中'), findsOneWidget);
  });

  testWidgets('F-APP-06: the card, badges and default buttons use the injected language', (tester) async {
    addTearDown(() => LiveUiText.current = LiveUiText.simplifiedChinese);
    LiveUiText.current = LiveUiText(
      live: 'LIVE',
      liveFor: (duration) => 'LIVE $duration',
      liveNow: 'live',
      offline: 'offline',
      recording: 'Recording',
      separator: ', ',
      retry: 'Retry',
      ok: 'OK',
      cancel: 'Cancel',
      justNow: 'just now',
      minutesAgo: (minutes) => '$minutes min ago',
      hoursAgo: (hours) => '$hours hr ago',
      daysAgo: (days) => '$days d ago',
      countBase: 1000,
      countUnits: const ['K', 'M', 'B'],
    );
    await tester.pumpWidget(
      host(const RoomCardView(platformId: 'douyu', anchorName: 'Host', title: 'Title', isLive: true, recording: true)),
    );
    expect(find.text('Recording'), findsOneWidget);
    expect(find.bySemanticsLabel('Host, live, Recording, Title'), findsOneWidget);
    await tester.pumpWidget(host(MessageView.error(title: 'Failed', onAction: () {}, onSecondary: () {})));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the shell switches between bar and rails with the width', (tester) async {
    const destinations = [
      NavDestination(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: '关注'),
      NavDestination(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: '发现'),
    ];
    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: AdaptiveNavScaffold(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            body: const SizedBox.expand(),
          ),
        ),
      );
    }

    addTearDown(tester.view.reset);
    await pumpAt(const Size(393, 852));
    expect(find.byType(NavigationBar), findsOneWidget);
    await pumpAt(const Size(900, 1000));
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
    await pumpAt(const Size(1440, 900));
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
  });
}
