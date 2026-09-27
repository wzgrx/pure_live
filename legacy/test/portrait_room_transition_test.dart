import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/layout/live_play_content.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';

void main() {
  Future<void> dismiss(WidgetTester tester) async {
    final handle = find.byKey(const ValueKey('live-play-portrait-sheet-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
  }

  test('portrait panel ranges remain ordered at every finite viewport height', () {
    for (final mode in PortraitLayoutMode.values) {
      for (final height in <double>[0, 1, 40, 120, 240, 309, 310, 390, 780, 1600]) {
        final range = portraitPanelRange(height, mode);
        expect(range.minimum, inInclusiveRange(0, height));
        expect(range.maximum, inInclusiveRange(range.minimum, height));
        expect(range.middle, inInclusiveRange(range.minimum, range.maximum));
        expect(range.initial, inInclusiveRange(range.minimum, range.maximum));
      }
    }
  });

  testWidgets('short viewport and restore keep video mounted and panel content reachable', (tester) async {
    var mounts = 0;
    var disposes = 0;
    Widget scene(double height) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          height: height,
          child: PortraitLiveRoomLayout(
            video: _VideoMountProbe(onMount: () => mounts++, onDispose: () => disposes++),
            resolution: const SizedBox(height: 55, child: Text('画质与线路')),
            danmaku: const Column(
              children: [
                SizedBox(height: 48, child: Text('弹幕列表')),
                Expanded(child: ColoredBox(color: Colors.white)),
                SizedBox(height: 64, child: TextField()),
              ],
            ),
            mode: PortraitLayoutMode.balanced,
            onEnterPortraitFullscreen: () {},
            onEnterLandscapeFullscreen: () {},
          ),
        ),
      ),
    );
    for (final height in <double>[580, 240, 120, 1, 0, 580]) {
      await tester.pumpWidget(scene(height));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'viewport height $height');
      expect(mounts, 1);
      expect(disposes, 0);
    }
    await tester.pumpWidget(const SizedBox());
    expect(disposes, 1);
  });

  testWidgets('compact panel can scroll to its input and preserves focus after resize', (tester) async {
    final focus = FocusNode();
    final text = TextEditingController(text: '尚未发送');
    addTearDown(focus.dispose);
    addTearDown(text.dispose);
    Widget keyboardScene(double height) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          height: height,
          child: PortraitLiveRoomLayout(
            video: const ColoredBox(color: Colors.black),
            resolution: const SizedBox(height: 55),
            danmaku: Column(
              children: [
                const SizedBox(height: 48),
                const Expanded(child: SizedBox()),
                SizedBox(
                  height: 64,
                  child: TextField(focusNode: focus, controller: text),
                ),
              ],
            ),
            mode: PortraitLayoutMode.balanced,
            onEnterPortraitFullscreen: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(keyboardScene(120));
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    final input = tester.getRect(find.byType(TextField));
    expect(input.bottom, lessThanOrEqualTo(120));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(keyboardScene(580));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(text.text, '尚未发送');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fullscreen shortcut stays bounded and labeled at narrow widths and large text', (tester) async {
    var requests = 0;
    for (final width in <double>[72, 120, 160, 320]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 240,
                child: PortraitLiveRoomLayout(
                  mode: PortraitLayoutMode.balanced,
                  video: const ColoredBox(color: Colors.black),
                  resolution: const SizedBox(height: 55),
                  danmaku: const SizedBox(),
                  onEnterLandscapeFullscreen: () => requests++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width=$width, text scale=2');
      expect(find.byTooltip('横屏全屏'), findsOneWidget);
      final action = find.byKey(const ValueKey('portrait-landscape-fullscreen'));
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(240));
      await tester.tap(action);
    }
    expect(requests, 4);
  });

  Widget scene({VoidCallback? onEnter, PortraitLayoutMode mode = PortraitLayoutMode.balanced}) => MaterialApp(
    home: SizedBox(
      width: 390,
      height: 580,
      child: PortraitLiveRoomLayout(
        video: const ColoredBox(color: Colors.black),
        resolution: const SizedBox(height: 55),
        danmaku: const ColoredBox(color: Colors.white),
        mode: mode,
        onEnterPortraitFullscreen: onEnter,
      ),
    ),
  );

  testWidgets('a declined fullscreen entry restores the sheet and permits another gesture', (tester) async {
    var requests = 0;
    await tester.pumpWidget(scene(onEnter: () => requests++));
    await dismiss(tester);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset, Offset.zero);
    await dismiss(tester);
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  testWidgets('changing layout mode revokes an entry waiting for its animation', (tester) async {
    var requests = 0;
    void enter() => requests++;
    await tester.pumpWidget(scene(onEnter: enter));
    await dismiss(tester);
    await tester.pumpWidget(scene(onEnter: enter, mode: PortraitLayoutMode.immersive));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset, Offset.zero);
  });

  testWidgets('removing the entry action during dismissal restores the remaining panel', (tester) async {
    var requests = 0;
    await tester.pumpWidget(scene(onEnter: () => requests++));
    await dismiss(tester);
    await tester.pumpWidget(scene());
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset, Offset.zero);
  });

  testWidgets('disposing the room during dismissal does not navigate later', (tester) async {
    var requests = 0;
    await tester.pumpWidget(scene(onEnter: () => requests++));
    await dismiss(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
}

class _VideoMountProbe extends StatefulWidget {
  const _VideoMountProbe({required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_VideoMountProbe> createState() => _VideoMountProbeState();
}

class _VideoMountProbeState extends State<_VideoMountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
