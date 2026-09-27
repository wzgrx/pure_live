import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  group('lane geometry (REN-5)', () {
    test('lane height is font size × 1.55 within 24–64', () {
      expect(const DanmakuStyle().laneHeight, closeTo(24.8, 1e-9));
      expect(const DanmakuStyle(fontSize: 10).laneHeight, 24);
      expect(const DanmakuStyle(fontSize: 30).laneHeight, closeTo(46.5, 1e-9));
      expect(const DanmakuStyle(fontSize: 60).laneHeight, 64);
    });

    test('the area share is applied exactly once (REG-DANMAKU-010)', () {
      // 20% of 500 px is 100 px: four 24.8 px lanes, not 20% of 20%.
      expect(DanmakuLanes.count(height: 500, laneHeight: 24.8, area: 0.2), 4);
      expect(DanmakuLanes.count(height: 500, laneHeight: 24.8, area: 1), 20);
    });

    test('insets come off before the area share', () {
      expect(DanmakuLanes.count(height: 540, laneHeight: 24.8, area: 0.5, topInset: 24, bottomInset: 16), 10);
    });

    test('rotating and rotating back gives the same lanes', () {
      int lanes(double height) => DanmakuLanes.count(height: height, laneHeight: 24.8, area: 0.5, topInset: 24);
      final portrait = lanes(220);
      final landscape = lanes(393);
      expect(landscape, greaterThan(portrait));
      expect(lanes(220), portrait);
    });

    test('tiny views keep one lane; zero area or no height keeps none', () {
      expect(DanmakuLanes.count(height: 20, laneHeight: 24.8, area: 1), 1);
      expect(DanmakuLanes.count(height: 500, laneHeight: 24.8, area: 0), 0);
      expect(DanmakuLanes.count(height: 30, laneHeight: 24.8, area: 1, topInset: 20, bottomInset: 10), 0);
      expect(DanmakuLanes.count(height: double.infinity, laneHeight: 24.8, area: 1), 0);
    });
  });

  group('scroll lane assignment', () {
    test('an empty lane is free, topmost first', () {
      expect(DanmakuLanes.pickScroll([null, null], width: 400, gap: 16), 0);
      expect(DanmakuLanes.pickScroll([500, null], width: 400, gap: 16), 1);
    });

    test('a lane frees once its last item has entered plus the gap', () {
      expect(DanmakuLanes.pickScroll([385], width: 400, gap: 16), -1);
      expect(DanmakuLanes.pickScroll([384], width: 400, gap: 16), 0);
      expect(DanmakuLanes.pickScroll([401, 390, 100], width: 400, gap: 16), 2);
    });

    test('no lanes or all busy gives -1', () {
      expect(DanmakuLanes.pickScroll([], width: 400, gap: 16), -1);
      expect(DanmakuLanes.pickScroll([420, 410], width: 400, gap: 16), -1);
    });

    test('same speed means an admitted item never catches the one ahead', () {
      // Simulate one lane: items of random widths admitted whenever the lane
      // is free, all moving at one speed. The gap never shrinks.
      const width = 400.0;
      const gap = 16.0;
      const speed = 120.0;
      final items = <({double x, double w})>[];
      var seed = 7;
      double next() => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) % 300) + 20.0;
      for (var frame = 0; frame < 600; frame++) {
        for (var i = 0; i < items.length; i++) {
          items[i] = (x: items[i].x - speed / 60, w: items[i].w);
        }
        items.removeWhere((item) => item.x + item.w < 0);
        final tail = items.isEmpty ? null : items.last.x + items.last.w;
        if (DanmakuLanes.pickScroll([tail], width: width, gap: gap) == 0) items.add((x: width, w: next()));
        for (var i = 1; i < items.length; i++) {
          expect(items[i].x - (items[i - 1].x + items[i - 1].w), greaterThanOrEqualTo(gap - 1e-9));
        }
      }
    });

    test('a local item takes the roomiest lane when none is free', () {
      expect(DanmakuLanes.roomiestScroll([420, 405, 430]), 1);
      expect(DanmakuLanes.roomiestScroll([420, null]), 1);
      expect(DanmakuLanes.roomiestScroll([]), -1);
    });
  });

  group('fixed lane assignment', () {
    test('the first expired lane from the edge', () {
      expect(DanmakuLanes.pickFixed([5, 2, 1], 3), 1);
      expect(DanmakuLanes.pickFixed([5, 6], 3), -1);
      expect(DanmakuLanes.pickFixed([double.negativeInfinity, 1], 0), 0);
    });

    test('a local item takes the lane that frees first', () {
      expect(DanmakuLanes.soonestFixed([5, 4, 6]), 1);
      expect(DanmakuLanes.soonestFixed([]), -1);
    });
  });

  group('even sampling (SMP-2)', () {
    test('keeps order and spans the whole batch', () {
      final batch = List.generate(200, (i) => i);
      final kept = DanmakuLanes.sampleEvenly(batch, 20);
      expect(kept, hasLength(20));
      expect(kept.first, lessThan(10));
      expect(kept.last, greaterThan(190));
      for (var i = 1; i < kept.length; i++) {
        expect(kept[i] - kept[i - 1], 10);
      }
    });

    test('small batches pass through; zero keeps nothing', () {
      expect(DanmakuLanes.sampleEvenly([1, 2, 3], 5), [1, 2, 3]);
      expect(DanmakuLanes.sampleEvenly([1, 2, 3], 0), isEmpty);
    });
  });
}
