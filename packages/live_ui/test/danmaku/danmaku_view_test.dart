import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  late DanmakuController controller;

  setUp(() => controller = DanmakuController());
  tearDown(() => controller.dispose());

  Widget host({Size size = const Size(400, 300), Widget? below, EdgeInsets padding = EdgeInsets.zero}) => MediaQuery(
    data: MediaQueryData(padding: padding),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: Stack(
            children: [
              ?below,
              Positioned.fill(child: DanmakuView(controller: controller)),
            ],
          ),
        ),
      ),
    ),
  );

  RenderObject layer(WidgetTester tester) => tester.renderObject(find.byType(DanmakuView));

  /// Pumps 60 Hz frames for [total]; one long pump is a stall the layer
  /// deliberately does not catch up on.
  Future<void> play(WidgetTester tester, Duration total) async {
    for (var t = Duration.zero; t < total; t += const Duration(microseconds: 16667)) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  testWidgets('paints items on one clipped canvas in its own layer', (tester) async {
    await tester.pumpWidget(host());
    controller
      ..add(const DanmakuItem('第一条'))
      ..add(const DanmakuItem('置顶', kind: DanmakuKind.top));
    await tester.pump();
    await play(tester, const Duration(milliseconds: 500));
    expect(controller.visibleCount, 2);
    final render = layer(tester);
    expect(render.isRepaintBoundary, isTrue);
    expect(
      render,
      paints
        ..clipRect(rect: Offset.zero & const Size(400, 300))
        ..paragraph()
        ..paragraph()
        ..paragraph()
        ..paragraph(),
    );
  });

  testWidgets('the ticker runs only while there is something to show', (tester) async {
    await tester.pumpWidget(host());
    expect(controller.isTicking, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    controller.add(const DanmakuItem('abc'));
    expect(controller.isTicking, isTrue);
    await tester.pump();
    await play(tester, const Duration(seconds: 1));
    expect(controller.visibleCount, 1);

    // 400 px + text width at 120 px/s: gone within 4 s.
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.visibleCount, 0);
    expect(controller.isTicking, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final paints = controller.stats.paints;
    final frames = controller.stats.frames;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.stats.paints, paints, reason: 'no idle repaints');
    expect(controller.stats.frames, frames, reason: 'no idle frame callbacks');
  });

  testWidgets('movement follows elapsed time, not the frame count', (tester) async {
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    final start = _find(controller, 'abc').left;
    // Ten 50 ms frames and fifty 10 ms frames cover the same second.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final coarse = _find(controller, 'abc').left;
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    final fine = _find(controller, 'abc').left;
    expect(start - coarse, closeTo(60, 0.5));
    expect(coarse - fine, closeTo(60, 0.5));
  });

  testWidgets('a lower frame rate advances less often but just as far', (tester) async {
    controller.budget = const DanmakuBudget(fps: 30);
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    final start = _find(controller, 'abc').left;
    final frames = controller.stats.frames;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(controller.stats.frames - frames, inInclusiveRange(29, 31));
    expect(start - _find(controller, 'abc').left, closeTo(120, 1));
  });

  testWidgets('pause freezes positions and holds new items; resume continues', (tester) async {
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    await play(tester, const Duration(milliseconds: 500));
    controller.pause(#video);
    final frozen = _find(controller, 'abc');
    expect(controller.isTicking, isFalse);
    controller.add(const DanmakuItem('新来的'));
    await tester.pump(const Duration(seconds: 2));
    expect(_find(controller, 'abc'), frozen);
    expect(controller.pendingCount, 1);

    controller
      ..pause(#menu)
      ..resume(#video);
    expect(controller.isPaused, isTrue, reason: 'the menu still holds it');
    controller.resume(#menu);
    await tester.pump();
    await play(tester, const Duration(milliseconds: 500));
    expect(_find(controller, 'abc').left, closeTo(frozen.left - 60, 1));
    expect(controller.visibleCount, 2);
  });

  testWidgets('a style change applies on screen while paused', (tester) async {
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    controller.pause();
    final before = _find(controller, 'abc');
    final paints = controller.stats.paints;
    controller.style = controller.style.copyWith(fontSize: 28);
    await tester.pump();
    final after = _find(controller, 'abc');
    expect(after.left, before.left);
    expect(after.height, greaterThan(before.height));
    expect(controller.stats.paints, paints + 1);
    expect(controller.isTicking, isFalse);
  });

  testWidgets('resizing keeps items moving from where they were', (tester) async {
    await tester.pumpWidget(host(size: const Size(400, 220)));
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    await play(tester, const Duration(milliseconds: 500));
    final before = _find(controller, 'abc');
    final lanes = controller.laneCount;
    await tester.pumpWidget(host(size: const Size(852, 393)));
    expect(_find(controller, 'abc').left, closeTo(before.left, 0.01));
    expect(controller.laneCount, greaterThan(lanes));
    await play(tester, const Duration(milliseconds: 500));
    expect(_find(controller, 'abc').left, closeTo(before.left - 60, 1));
  });

  testWidgets('safe-area padding keeps lanes clear of the insets', (tester) async {
    await tester.pumpWidget(host(padding: const EdgeInsets.only(top: 40)));
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    expect(_find(controller, 'abc').top, greaterThanOrEqualTo(40));
    expect(controller.laneCount, (260 / 24.8).floor());
  });

  testWidgets('pointers pass through; the app asks for the item under a tap', (tester) async {
    final taps = <Offset>[];
    await tester.pumpWidget(
      host(
        below: Positioned.fill(child: GestureDetector(onTapUp: (details) => taps.add(details.globalPosition))),
      ),
    );
    controller.add(const DanmakuItem('点我', data: 'msg-1'));
    await tester.pump();
    await play(tester, const Duration(seconds: 1));
    final target = _find(controller, '点我').center;
    await tester.tapAt(target);
    expect(taps, [target]);
    expect(controller.itemAtGlobal(taps.single)?.item.data, 'msg-1');
    expect(controller.itemAtGlobal(const Offset(5, 295)), isNull);
  });

  testWidgets('unmounting stops frames and clears the screen (REN-9)', (tester) async {
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    expect(controller.visibleCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(controller.visibleCount, 0);
    expect(controller.isTicking, isFalse);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('moving the view with a GlobalKey keeps the items', (tester) async {
    final key = GlobalKey();
    Widget placed({required bool left}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          SizedBox(
            width: 400,
            height: 300,
            child: left ? DanmakuView(key: key, controller: controller) : null,
          ),
          SizedBox(
            width: 400,
            height: 300,
            child: left ? null : DanmakuView(key: key, controller: controller),
          ),
        ],
      ),
    );
    await tester.pumpWidget(placed(left: true));
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    await play(tester, const Duration(milliseconds: 500));
    await tester.pumpWidget(placed(left: false));
    expect(controller.visibleCount, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isTicking, isTrue);
  });

  testWidgets('a controller swap hands the surface over', (tester) async {
    final other = DanmakuController();
    addTearDown(other.dispose);
    await tester.pumpWidget(host());
    controller.add(const DanmakuItem('abc'));
    await tester.pump();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DanmakuView(controller: other),
      ),
    );
    expect(controller.visibleCount, 0, reason: 'the old controller released its screen');
    expect(controller.isTicking, isFalse);
    other.add(const DanmakuItem('新'));
    await tester.pump();
    expect(other.visibleCount, 1);
  });

  testWidgets('clear empties the layer and stops', (tester) async {
    await tester.pumpWidget(host());
    controller.addAll(const [DanmakuItem('a'), DanmakuItem('b')]);
    await tester.pump();
    controller.clear();
    expect(controller.visibleCount + controller.pendingCount, 0);
    expect(controller.isTicking, isFalse);
    await tester.pump();
    expect(layer(tester), isNot(paints..paragraph()));
  });
}

Rect _find(DanmakuController controller, String text) =>
    controller.visibleItems.firstWhere((hit) => hit.item.text == text).rect;
