import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

Widget _app(Widget child) => MaterialApp(
  theme: const LiveTheme(primaryColor: Colors.indigo).light,
  home: Scaffold(body: child),
);

void main() {
  group('icons', () {
    test('every platform has a logo; other ids get the app logo instead of throwing', () {
      for (final id in PlatformLogos.ids) {
        expect(File(PlatformLogos.assetFor(id)).existsSync(), isTrue, reason: id);
      }
      expect(PlatformLogos.ids, hasLength(35));
      expect(PlatformLogos.assetFor(' DouYu '), 'assets/platforms/douyu.png');
      expect(PlatformLogos.assetFor('kick'), 'assets/platforms/kick.png');
      expect(PlatformLogos.assetFor('huajiao'), PlatformLogos.fallback);
      expect(File(PlatformLogos.fallback).existsSync(), isTrue);
    });

    test('the icon font is bundled with this package', () {
      expect(CustomIcons.search.fontPackage, 'live_ui');
      expect(File('assets/fonts/CustomIcons.ttf').existsSync(), isTrue);
    });
  });

  testWidgets('CommonAvatar shows the first letter without a picture', (tester) async {
    await tester.pumpWidget(_app(const CommonAvatar(avatarUrl: ' ', fallbackName: 'abc', dense: true)));
    expect(find.text('A'), findsOneWidget);
    expect(tester.getSize(find.byType(CommonAvatar)), const Size(34, 34));
  });

  group('settings blocks', () {
    testWidgets('a card divides neighbouring tiles, the narrow stacked tile included', (tester) async {
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var switched = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => context.buildModernCard([
              context.buildSwitchTile(title: 'Switch', value: false, onChanged: (value) => switched = value),
              const SizedBox(),
              context.buildTile(title: 'Stacked', trailing: const Text('value'), stackTrailingOnNarrow: true),
              context.buildTile(title: 'Plain', onTap: () {}),
              const Padding(padding: EdgeInsets.all(8), child: Text('not a tile')),
            ]),
          ),
        ),
      );
      // 3.x missed the divider around the stacked tile (it was a LayoutBuilder).
      expect(find.byType(Divider), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Switch'));
      expect(switched, isTrue);
    });

    testWidgets('a slider row reports values and lays the badge out', (tester) async {
      double? changed;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => context.buildSliderTile(
              icon: Icons.speed,
              title: 'Speed',
              value: 5,
              min: 0,
              max: 10,
              displayValue: '5x',
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      );
      expect(find.text('5x'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      expect(changed, isNotNull);
    });

    testWidgets('group titles and section titles', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Column(
              children: [
                context.buildGroupTitle('Group'),
                const SectionTitle(title: 'Section'),
                const MenuListTile(leading: Icon(Icons.settings), text: 'Menu'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);
    });
  });

  group('CountButton', () {
    testWidgets('steps on tap and stays within the limits', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        _app(Center(child: CountButton(minValue: 0, maxValue: 2, selectedValue: 2, onChanged: values.add))),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.remove));
      expect(values, [1]);
    });

    testWidgets('holding repeats from the last value even when the parent does not rebuild', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        _app(Center(child: CountButton(minValue: 0, maxValue: 3, selectedValue: 0, onChanged: values.add))),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.add)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 450));
      await gesture.up();
      expect(values, [1, 2, 3]);
    });
  });

  group('AdaptiveRefreshRateController', () {
    testWidgets('balanced: high while touching, released 1.5 s after', (tester) async {
      final applied = <bool>[];
      final controller = AdaptiveRefreshRateController(({required high}) async => applied.add(high));
      await tester.pumpWidget(
        AdaptiveRefreshRateScope(
          controller: controller,
          mode: RefreshRateMode.balanced,
          child: const SizedBox.expand(),
        ),
      );
      final gesture = await tester.startGesture(const Offset(10, 10));
      await tester.pump();
      expect(controller.requestedHigh, isTrue);
      // A scroll ending under a finger still down must not start the release.
      controller.endScroll();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.requestedHigh, isTrue);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1400));
      expect(controller.requestedHigh, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.requestedHigh, isFalse);
      // The first request is the system's choice, as in 3.x.
      expect(applied, [false, true, false]);
    });

    testWidgets('performance stays high until paused', (tester) async {
      final applied = <bool>[];
      final controller = AdaptiveRefreshRateController(({required high}) async => applied.add(high))
        ..setMode(RefreshRateMode.performance);
      await tester.pump();
      expect(applied, [true]);
      controller.pause();
      await tester.pump();
      expect(applied, [true, false]);
      controller.beginPointer();
      expect(controller.requestedHigh, isFalse);
    });
  });

  testWidgets('EmoteText shows the alt text of an emote without a picture', (tester) async {
    const segments = [ChatTextSegment('hi '), ChatEmoteSegment(url: '', alt: ':wave:')];
    await tester.pumpWidget(_app(const EmoteText(segments)));
    expect(find.text('hi :wave:'), findsOneWidget);
    expect(EmoteText.plainText(segments), 'hi :wave:');
  });

  testWidgets('EmoteText shows a bundled picture first; a missing one falls back to the code', (tester) async {
    final bundled = ChatEmoteSegment(url: '', alt: '[x]', asset: PlatformLogos.assetFor('douyu'));
    await tester.pumpWidget(_app(EmoteText([const ChatTextSegment('a'), bundled])));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
    expect(find.text('[x]'), findsNothing);

    await tester.pumpWidget(
      _app(const EmoteText([ChatEmoteSegment(url: '', alt: '[y]', asset: 'assets/emo/none.png')])),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('[y]'), findsOneWidget);
    expect(bundled, ChatEmoteSegment(url: '', alt: '[x]', asset: PlatformLogos.assetFor('douyu')));
    expect(bundled, isNot(const ChatEmoteSegment(url: '', alt: '[x]')));
  });

  testWidgets('QrCodeWidget paints the code at its size', (tester) async {
    await tester.pumpWidget(_app(const Center(child: QrCodeWidget(data: 'https://example.com', size: 120))));
    expect(tester.getSize(find.byType(QrCodeWidget)), const Size(120, 120));
  });

  testWidgets('ScrollableTabBar scrolls its strip with the mouse wheel', (tester) async {
    final controller = TabController(length: 12, vsync: const TestVSync());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 300,
          child: ScrollableTabBar(
            controller: controller,
            isScrollable: true,
            tabs: [for (var i = 0; i < 12; i++) Tab(text: 'Tab number $i')],
          ),
        ),
      ),
    );
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, 0);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(ScrollableTabBar))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  group('VideoStateView (docs/ui/compare/U.2g c2)', () {
    Widget host(Widget child, {double height = 300}) => MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 393, height: height, child: child),
        ),
      ),
    );

    testWidgets('icon, sentence, reason and two buttons, the first filled white', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        host(
          VideoStateView(
            icon: AppIcons.playbackError,
            title: '播放已中断',
            reason: '网络连接失败',
            dim: OnVideoColors.scrim,
            actions: [
              VideoStateAction(
                key: const ValueKey('a'),
                label: '重试',
                icon: AppIcons.refresh,
                onPressed: () => pressed.add('a'),
              ),
              VideoStateAction(
                key: const ValueKey('b'),
                label: '换线路',
                icon: AppIcons.switchLine,
                onPressed: () => pressed.add('b'),
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('video-state-icon')), findsOneWidget);
      expect(find.text('播放已中断'), findsOneWidget);
      expect(find.text('网络连接失败'), findsOneWidget);
      final first = tester.widget<Material>(find.byKey(const ValueKey('a')));
      final second = tester.widget<Material>(find.byKey(const ValueKey('b')));
      expect(first.color, OnVideoColors.foreground);
      expect(second.color, OnVideoColors.buttonFill);
      expect(tester.getCenter(find.text('重试')).dx, lessThan(tester.getCenter(find.text('换线路')).dx));
      expect(tester.getTopLeft(find.text('网络连接失败')).dy, greaterThan(tester.getBottomLeft(find.text('播放已中断')).dy - 1));
      expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('video-state-dim'))).color, OnVideoColors.scrim);
      await tester.tap(find.text('换线路'));
      expect(pressed, ['b']);
    });

    testWidgets('compact leaves out the icon but keeps the streamer; a spinner when busy', (tester) async {
      await tester.pumpWidget(
        host(const VideoStateView(icon: AppIcons.playbackError, title: 'x', compact: true), height: 221),
      );
      expect(find.byKey(const ValueKey('video-state-icon')), findsNothing);
      await tester.pumpWidget(
        host(
          const VideoStateView(
            leading: VideoStateAvatar(child: SizedBox()),
            title: '当前主播未开播或已下播',
            compact: true,
          ),
          height: 221,
        ),
      );
      expect(find.byKey(const ValueKey('video-state-avatar')), findsOneWidget);
      await tester.pumpWidget(host(const VideoStateView(busy: true, title: '正在进入直播间…')));
      expect(find.byKey(const ValueKey('video-state-spinner')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-state-dim')), findsNothing);
    });

    testWidgets('a button turns while its action runs and takes no second tap', (tester) async {
      final done = Completer<void>();
      var taps = 0;
      await tester.pumpWidget(
        host(
          VideoStateView(
            title: '播放已中断',
            actions: [
              VideoStateAction(
                label: '重试',
                icon: AppIcons.refresh,
                onPressed: () {
                  taps++;
                  return done.future;
                },
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.byKey(const ValueKey('video-state-button-busy')), findsOneWidget);
      await tester.tap(find.text('重试'), warnIfMissed: false);
      expect(taps, 1);
      done.complete();
      await tester.pump();
      expect(find.byKey(const ValueKey('video-state-button-busy')), findsNothing);
    });
  });

  testWidgets('VideoCentreButton (B02 c2): a white play mark on a 64 disc of 45 % black; busy, a spinner', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: VideoCentreButton(key: const ValueKey('centre'), tooltip: '播放', onPressed: () => taps++),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('centre'))), const Size(64, 64));
    final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
    expect(style.backgroundColor!.resolve({}), OnVideoColors.button);
    expect(OnVideoColors.button.a, closeTo(0.45, 0.01));
    expect(style.foregroundColor!.resolve({}), OnVideoColors.foreground);
    expect(find.byIcon(AppIcons.play), findsOneWidget);
    expect(find.byTooltip('播放'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('centre')));
    expect(taps, 1);

    await tester.pumpWidget(
      _app(
        Center(
          child: VideoCentreButton(
            key: const ValueKey('centre'),
            tooltip: '缓冲中',
            busy: true,
            size: 58,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('centre'))), const Size(58, 58));
    final disc = tester.widget<DecoratedBox>(find.byKey(const ValueKey('video-centre-busy')));
    expect((disc.decoration as BoxDecoration).color, OnVideoColors.button);
    expect(find.byType(DefaultLoadingIndicator), findsOneWidget);
    expect(find.byIcon(AppIcons.play), findsNothing);
    await tester.tap(find.byKey(const ValueKey('centre')), warnIfMissed: false);
    expect(taps, 1, reason: 'busy: no tap');
  });

  test('InkOnColor.contrastOn picks the ink with the higher contrast (U.2e S2)', () {
    // 3.x put white on Bilibili's 100 yuan gold at about 1.9:1.
    expect(InkOnColor.contrastOn(const Color(0xFFE2B52B)), InkOnColor.ink);
    expect(InkOnColor.contrastOn(const Color(0xFFFFF1C5)), InkOnColor.ink);
    expect(InkOnColor.contrastOn(const Color(0xFF2A60B2)), InkOnColor.light);
    expect(InkOnColor.contrastOn(const Color(0xFF427D9E)), InkOnColor.light);
    expect(InkOnColor.contrastMutedOn(const Color(0xFF2A60B2)), InkOnColor.lightMuted);
  });

  testWidgets('ReadableContent keeps a reading column at most 720 wide, centred', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = ValueKey('column');
    await tester.pumpWidget(
      _app(
        const ReadableContent(
          child: SizedBox(key: key, width: double.infinity, height: 10),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(key));
    expect(rect.width, readableContentMaxWidth);
    expect(rect.center.dx, 640);

    tester.view.physicalSize = const Size(393, 800);
    await tester.pumpWidget(
      _app(
        const ReadableContent(
          child: SizedBox(key: key, width: double.infinity, height: 10),
        ),
      ),
    );
    expect(tester.getRect(find.byKey(key)).width, 393);
  });

  test('the warm container and the QR colours keep their contrast', () {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final brightness in Brightness.values) {
      expect(
        contrast(LiveSemanticColors.warmContainer(brightness), LiveSemanticColors.onWarmContainer(brightness)),
        greaterThan(4.5),
      );
    }
    expect(contrast(QrColors.paper, QrColors.ink), greaterThan(15));
  });
}
