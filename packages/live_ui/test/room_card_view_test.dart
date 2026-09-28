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

  testWidgets("principles §3.4: an offline row's avatar is the shared initial avatar, toned by the room", (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const OfflineRoomRow(platformId: 'douyu', anchorName: 'kiri', seed: 'douyu:1'), width: 360),
    );
    final avatar = tester.widget<InitialAvatar>(find.byType(InitialAvatar));
    expect(avatar.seed, 'douyu:1');
    expect(find.text('K'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    final logo = tester.widget<PlatformLogo>(find.byType(PlatformLogo));
    expect(logo.size, Sizes.logoMedium);
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
    // Without a cover the logo (a letter tile for a platform without one)
    // sits in the middle of the placeholder, once.
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
      loading: 'Loading',
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
      NavDestination(icon: LiveIcons.follows, label: '关注'),
      NavDestination(icon: LiveIcons.discover, label: '发现'),
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

  testWidgets('principles §5.2: the rail expands and collapses by hand from the expanded class on', (tester) async {
    const destinations = [
      NavDestination(icon: LiveIcons.follows, label: '关注'),
      NavDestination(icon: LiveIcons.discover, label: '发现'),
    ];
    bool? chosen;
    final changes = <bool>[];
    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.windows),
          home: AdaptiveNavScaffold(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            body: const SizedBox.expand(),
            railExtended: chosen,
            onRailExtendedChanged: (value) {
              changes.add(value);
              chosen = value;
            },
            expandRailLabel: 'expand',
            collapseRailLabel: 'collapse',
          ),
        ),
      );
    }

    bool extended() => tester.widget<NavigationRail>(find.byType(NavigationRail)).extended;

    addTearDown(tester.view.reset);
    await pumpAt(const Size(700, 900));
    expect(find.byTooltip('expand'), findsNothing, reason: 'medium keeps the collapsed rail');
    await pumpAt(const Size(1440, 900));
    expect(extended(), isTrue, reason: 'large starts expanded');
    await tester.tap(find.byTooltip('collapse'));
    await pumpAt(const Size(1440, 900));
    expect(changes, [false]);
    expect(extended(), isFalse, reason: 'the choice wins over the class');
    await pumpAt(const Size(1920, 1080));
    expect(extended(), isFalse, reason: 'and is kept on other windows');
    await pumpAt(const Size(1024, 768));
    await tester.tap(find.byTooltip('expand'));
    await pumpAt(const Size(1024, 768));
    expect(changes, [false, true]);
    expect(extended(), isTrue, reason: 'expanded windows can expand the rail');
    await pumpAt(const Size(852, 393));
    expect(find.byTooltip('collapse'), findsNothing, reason: 'landscape phones keep the collapsed rail');
    expect(extended(), isFalse);
  });
}
