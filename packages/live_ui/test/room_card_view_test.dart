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
