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
}
