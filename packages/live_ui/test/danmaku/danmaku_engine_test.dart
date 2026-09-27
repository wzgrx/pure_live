import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_ui/src/danmaku/danmaku_engine.dart';

/// Monotonic clock the tests move by hand.
final class FakeClock {
  Duration now = Duration.zero;

  Duration call() => now;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClock clock;

  setUp(() => clock = FakeClock());

  DanmakuEngine engine({
    DanmakuStyle style = const DanmakuStyle(),
    DanmakuBudget budget = const DanmakuBudget(),
    Size size = const Size(400, 300),
  }) => DanmakuEngine(style: style, budget: budget, clock: clock.call)..resize(size);

  /// Steps [e] for [seconds] at [fps], moving the fake clock along; calls
  /// [check] after every frame.
  void run(DanmakuEngine e, double seconds, {int fps = 60, void Function()? check}) {
    final frames = (seconds * fps).round();
    for (var i = 0; i < frames; i++) {
      clock.now += Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());
      e.step(1 / fps);
      check?.call();
    }
  }

  DanmakuHit only(DanmakuEngine e) => e.visibleItems.single;

  test('FLT-2: removeWhere drops matching items on screen and waiting, others stay', () {
    final e = engine()..addAll(const [DanmakuItem('加群领福利'), DanmakuItem('主播好'), DanmakuItem('加群看片')]);
    run(e, 0.3);
    expect(e.visibleCount, 3);
    e.add(const DanmakuItem('加群最后一条'));
    expect(e.removeWhere((item) => item.text.contains('加群')), 2);
    expect(e.visibleItems.map((hit) => hit.item.text), ['主播好']);
    run(e, 0.2);
    expect(e.visibleItems.map((hit) => hit.item.text), ['主播好'], reason: 'the waiting one went too');
    expect(e.removeWhere((item) => false), 0);
  });

  group('motion', () {
    test('speed is px/s whatever the frame rate', () {
      for (final fps in [30, 60, 90, 144]) {
        final e = engine()
          ..add(const DanmakuItem('abc'))
          ..step(0);
        expect(only(e).rect.left, 400, reason: 'enters at the right edge');
        run(e, 1, fps: fps);
        expect(only(e).rect.left, closeTo(400 - 120, 1e-6), reason: '$fps fps');
      }
    });

    test('a speed change applies to items on screen', () {
      final e = engine()
        ..add(const DanmakuItem('abc'))
        ..step(0);
      run(e, 0.5);
      final before = only(e).rect.left;
      e.style = e.style.copyWith(speed: 240);
      run(e, 0.5);
      expect(only(e).rect.left, closeTo(before - 120, 1e-6));
    });

    test('items leave once fully off the left edge, and the engine goes idle', () {
      final e = engine()
        ..add(const DanmakuItem('abc'))
        ..step(0);
      final width = only(e).rect.width;
      run(e, (400 + width) / 120 - 0.05);
      expect(e.visibleCount, 1);
      run(e, 0.1);
      expect(e.visibleCount, 0);
      expect(e.hasWork, isFalse);
    });
  });

  group('frame clock (REN-2)', () {
    test('following the display steps every vsync by its delta', () {
      final frames = DanmakuFrameClock();
      expect(frames.advance(Duration.zero, null), 0);
      expect(frames.advance(const Duration(microseconds: 8333), null), closeTo(0.008333, 1e-9));
      expect(frames.advance(const Duration(microseconds: 8333), null), isNull, reason: 'no time passed');
    });

    test('a lower rate skips vsyncs but keeps real time', () {
      final frames = DanmakuFrameClock()..advance(Duration.zero, 60);
      var steps = 0;
      var total = 0.0;
      for (var i = 1; i <= 144; i++) {
        final step = frames.advance(Duration(microseconds: (i * 1e6 / 144).round()), 60);
        if (step != null) {
          steps++;
          total += step;
        }
      }
      expect(steps, inInclusiveRange(59, 61));
      expect(total, closeTo(1, 1 / 60));
    });

    test('30 fps on a 60 Hz display steps every other vsync', () {
      final frames = DanmakuFrameClock()..advance(Duration.zero, 30);
      final taken = [
        for (var i = 1; i <= 6; i++) frames.advance(Duration(microseconds: (i * 1e6 / 60).round()), 30) != null,
      ];
      expect(taken, [false, true, false, true, false, true]);
    });

    test('one step covers at most three frame intervals', () {
      final frames = DanmakuFrameClock()..advance(Duration.zero, 60);
      expect(frames.advance(const Duration(seconds: 1), 60), closeTo(3 / 60, 1e-4));
      frames
        ..reset()
        ..advance(Duration.zero, null);
      expect(frames.advance(const Duration(seconds: 1), null), closeTo(3 / 60, 1e-4));
    });
  });

  group('lanes and collisions', () {
    test('scrolling items in one lane never overlap and stay inside the area', () {
      final e = engine(style: const DanmakuStyle(area: 0.5), size: const Size(400, 500));
      for (var i = 0; i < 120; i++) {
        e.add(DanmakuItem('弹幕$i${'啊' * (i % 9)}'));
      }
      var seen = 0;
      run(
        e,
        20,
        check: () {
          final byLane = <double, List<Rect>>{};
          for (final hit in e.visibleItems) {
            byLane.putIfAbsent(hit.rect.top, () => []).add(hit.rect);
            expect(hit.rect.bottom, lessThanOrEqualTo(250 + 1e-9));
          }
          for (final rects in byLane.values) {
            rects.sort((a, b) => a.left.compareTo(b.left));
            for (var i = 1; i < rects.length; i++) {
              expect(rects[i].left - rects[i - 1].right, greaterThanOrEqualTo(16 - 1e-6));
            }
          }
          if (byLane.length > seen) seen = byLane.length;
        },
      );
      expect(seen, e.laneCount, reason: 'every lane got used');
      expect(e.laneCount, 10);
    });

    test('top items sit centered in the first free top lane and expire', () {
      final e = engine()
        ..add(const DanmakuItem('置顶', kind: DanmakuKind.top))
        ..add(const DanmakuItem('置顶二', kind: DanmakuKind.top, duration: Duration(seconds: 1)));
      run(e, 0.1);
      final rects = [for (final hit in e.visibleItems) hit.rect];
      expect(rects, hasLength(2));
      expect(rects[0].center.dx, closeTo(200, 1));
      expect(rects[1].top, greaterThan(rects[0].top));
      run(e, 1);
      expect(e.visibleCount, 1, reason: 'the 1 s item expired');
      run(e, 2.8);
      expect(e.visibleCount, 1);
      run(e, 0.2);
      expect(e.visibleCount, 0);
    });

    test('bottom items stack up from the bottom of the area', () {
      final e = engine(style: const DanmakuStyle(area: 0.5), size: const Size(400, 500))
        ..add(const DanmakuItem('底部', kind: DanmakuKind.bottom))
        ..add(const DanmakuItem('底部二', kind: DanmakuKind.bottom));
      run(e, 0.1);
      final rects = [for (final hit in e.visibleItems) hit.rect];
      expect(rects[0].bottom, lessThanOrEqualTo(250));
      expect(rects[0].bottom, greaterThan(250 - 24.8));
      expect(rects[1].bottom, lessThanOrEqualTo(rects[0].top));
    });

    test('a waiting top item does not block scrolling ones behind it', () {
      final e = engine(size: const Size(400, 30));
      expect(e.laneCount, 1);
      e.add(const DanmakuItem('占位', kind: DanmakuKind.top));
      run(e, 0.1);
      e
        ..add(const DanmakuItem('等待', kind: DanmakuKind.top))
        ..add(const DanmakuItem('滚动'));
      run(e, 0.1);
      expect([for (final hit in e.visibleItems) hit.item.text], containsAll(['占位', '滚动']));
      expect(e.pendingCount, 1);
    });
  });

  group('budget (REN-4)', () {
    test('about one admission per 50 ms, at most two in a frame', () {
      final e = engine(size: const Size(400, 1000));
      for (var i = 0; i < 100; i++) {
        e.add(DanmakuItem('$i'));
      }
      var last = 0;
      run(
        e,
        1,
        check: () {
          final admitted = e.stats.admitted;
          expect(admitted - last, lessThanOrEqualTo(2));
          expect(e.lastFrameLayouts, lessThanOrEqualTo(admitted - last));
          last = admitted;
        },
      );
      expect(e.stats.admitted, inInclusiveRange(19, 22));
    });

    test('never more than maxVisible on screen', () {
      final e = engine(budget: const DanmakuBudget(maxVisible: 5), size: const Size(400, 1000));
      for (var i = 0; i < 50; i++) {
        e.add(DanmakuItem('一条比较长的弹幕$i'));
      }
      var peak = 0;
      run(
        e,
        3,
        check: () {
          expect(e.visibleCount, lessThanOrEqualTo(5));
          if (e.visibleCount > peak) peak = e.visibleCount;
        },
      );
      expect(peak, 5);
    });

    test('a full waiting queue drops the oldest', () {
      final e = engine();
      for (var i = 0; i < 300; i++) {
        e.add(DanmakuItem('$i'));
      }
      expect(e.pendingCount, 120);
      expect(e.stats.droppedOverflow, 180);
      e.step(0);
      expect(e.visibleItems.first.item.text, '180');
    });

    test('items waiting over 5 s are dropped, even while nothing steps', () {
      final e = engine()..add(const DanmakuItem('旧'));
      clock.now += const Duration(seconds: 6);
      e
        ..add(const DanmakuItem('新'))
        ..step(0);
      expect(e.stats.droppedStale, 1);
      expect(only(e).item.text, '新');
    });

    test('an oversized batch is sampled evenly across its span', () {
      // A roomy, fast budget so every kept item reaches the screen in time.
      final e = engine(
        budget: const DanmakuBudget(emitInterval: Duration(milliseconds: 5), maxVisible: 1000),
        size: const Size(400, 4000),
      )..addAll([for (var i = 0; i < 500; i++) DanmakuItem('$i')]);
      expect(e.pendingCount, 120);
      expect(e.stats.droppedSampled, 380);
      expect(e.stats.added, 500);
      final shown = <int>[];
      run(e, 3, check: () => shown.addAll(e.visibleItems.map((hit) => int.parse(hit.item.text))));
      final distinct = shown.toSet().toList()..sort();
      expect(distinct, hasLength(120));
      expect(distinct.first, lessThan(5));
      expect(distinct.last, greaterThan(495));
      for (var i = 1; i < distinct.length; i++) {
        expect(distinct[i] - distinct[i - 1], inInclusiveRange(4, 5));
      }
    });

    test('local items skip the caps and the queue', () {
      final e = engine(budget: const DanmakuBudget(maxVisible: 1));
      for (var i = 0; i < 200; i++) {
        e.add(DanmakuItem('$i'));
      }
      e
        ..add(const DanmakuItem('我发的', isLocal: true))
        ..step(0);
      expect([for (final hit in e.visibleItems) hit.item.text], ['我发的', '80']);
      run(e, 0.5);
      expect(e.visibleCount, 2, reason: 'the local item does not count against maxVisible');
    });

    test('a local item goes on screen even when every lane is busy', () {
      final e = engine(size: const Size(400, 30))
        ..add(const DanmakuItem('一条很长很长很长的弹幕'))
        ..step(0)
        ..add(const DanmakuItem('我发的', isLocal: true))
        ..step(1 / 60);
      expect(e.visibleCount, 2);
    });

    test('with no lane possible nothing waits and frames stop', () {
      final e = engine(style: const DanmakuStyle(area: 0))..add(const DanmakuItem('x'));
      expect(e.hasWork, isTrue);
      e.step(0);
      expect(e.hasWork, isFalse);
      expect(e.stats.droppedFiltered, 1);
    });
  });

  group('style', () {
    test('no-emoji mode drops emoji-only items and strips the rest', () {
      final e = engine(style: const DanmakuStyle(noEmoji: true))
        ..add(const DanmakuItem('🎉🎉'))
        ..add(const DanmakuItem('哈😂'));
      run(e, 0.2);
      expect(e.stats.droppedFiltered, 1);
      final shown = only(e);
      expect(shown.item.text, '哈😂');
      final plain = engine()
        ..add(const DanmakuItem('哈'))
        ..step(0);
      expect(shown.rect.width, only(plain).rect.width);
    });

    test('changing the look re-lays out items on screen and keeps their place', () {
      final e = engine()
        ..add(const DanmakuItem('哈😂'))
        ..add(const DanmakuItem('😂'));
      run(e, 0.5);
      final before = {for (final hit in e.visibleItems) hit.item.text: hit.rect};
      final layouts = e.stats.layouts;
      e.style = e.style.copyWith(noEmoji: true, fontSize: 24);
      e.step(0);
      final after = {for (final hit in e.visibleItems) hit.item.text: hit.rect};
      expect(after.keys, ['哈😂'], reason: 'the emoji-only item left');
      expect(after['哈😂']!.left, before['哈😂']!.left);
      expect(after['哈😂']!.height, greaterThan(before['哈😂']!.height));
      expect(e.stats.layouts, layouts + 1);
    });

    test('identical texts share one layout', () {
      final e = engine(size: const Size(400, 1000));
      for (var i = 0; i < 10; i++) {
        e.add(const DanmakuItem('666'));
      }
      run(e, 1);
      expect(e.stats.admitted, 10);
      expect(e.stats.layouts, 1);
    });
  });

  group('geometry', () {
    test('resizing keeps scrolling items where they are and recomputes lanes', () {
      final e = engine(size: const Size(400, 220))..add(const DanmakuItem('abc'));
      run(e, 0.5);
      final before = only(e).rect;
      final lanes = e.laneCount;
      e.resize(const Size(852, 393));
      expect(only(e).rect.left, before.left);
      expect(e.laneCount, greaterThan(lanes));
      e.resize(const Size(400, 220));
      expect(e.laneCount, lanes);
    });

    test('fixed items re-center on resize', () {
      final e = engine()
        ..add(const DanmakuItem('置顶', kind: DanmakuKind.top))
        ..step(0)
        ..resize(const Size(800, 300));
      expect(only(e).rect.center.dx, closeTo(400, 1));
    });

    test('safe-area insets and margins push lanes inward', () {
      final e = engine(style: const DanmakuStyle(topMargin: 10))
        ..resize(const Size(400, 300), topInset: 24, bottomInset: 16)
        ..add(const DanmakuItem('abc'))
        ..step(0);
      expect(only(e).rect.top, greaterThanOrEqualTo(34));
      expect(e.laneCount, ((300 - 34 - 16) / 24.8).floor());
    });
  });

  group('hit testing (REN-8)', () {
    test('returns the item under a point, with touch slop', () {
      final e = engine()
        ..add(const DanmakuItem('点我', data: 42))
        ..step(0);
      run(e, 1);
      final rect = only(e).rect;
      expect(e.hitTest(rect.center)?.item.data, 42);
      expect(e.hitTest(rect.topCenter.translate(0, -3))?.item.data, 42);
      expect(e.hitTest(rect.centerRight.translate(5, 0)), isNull);
      expect(e.hitTest(const Offset(10, 290)), isNull);
    });

    test('fixed items are on top of scrolling ones', () {
      final e = engine(size: const Size(400, 30))
        ..add(const DanmakuItem('滚动滚动滚动滚动'))
        ..add(const DanmakuItem('置顶置顶置顶置顶置顶置顶置顶', kind: DanmakuKind.top))
        ..step(0);
      run(e, 2);
      expect(e.hitTest(const Offset(200, 12))?.item.kind, DanmakuKind.top);
    });
  });

  test('releasing the screen frees glyphs; the next admission lays out again (REN-9)', () {
    final e = engine()
      ..add(const DanmakuItem('abc'))
      ..step(0);
    expect(e.stats.layouts, 1);
    e.releaseScreen();
    expect(e.visibleCount, 0);
    e
      ..add(const DanmakuItem('abc'))
      ..step(1);
    expect(e.stats.layouts, 2);
  });
}
