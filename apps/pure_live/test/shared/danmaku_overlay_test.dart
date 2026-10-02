import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

// U.2h (docs/ui/compare/U.2h) c1-c10 and F.2a on the flying layer.

LiveMessage _chat(String text, {String id = ''}) =>
    LiveMessage(type: LiveMessageType.chat, userName: 'u', message: text, color: LiveMessageColor.white, messageId: id);

const LiveMessage _local = LiveMessage(
  type: LiveMessageType.chat,
  userName: 'Pure Live',
  message: '本地',
  color: LiveMessageColor.white,
  isLocal: true,
  style: LiveMessageStyle(fontSize: 16, baseSpeed: 100, fontWeight: 500, showStroke: true, strokeWidth: 1),
);

final class _Layer {
  new(this.tester);

  final WidgetTester tester;
  final StreamController<LiveMessage> messages = StreamController.broadcast(sync: true);
  final StreamController<LiveRetraction> retractions = StreamController.broadcast(sync: true);

  Future<void> pump({
    DanmakuLook look = const DanmakuLook(),
    double height = 300,
    int? fps,
    double refreshRate = 60,
    bool running = true,
    bool held = false,
    EmoteTable emotes = EmoteTable.empty,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: height,
          child: DanmakuOverlay(
            messages: messages.stream,
            retractions: retractions.stream,
            look: look,
            fps: fps,
            refreshRate: refreshRate,
            running: running,
            held: held,
            emotes: emotes,
          ),
        ),
      ),
    ),
  );

  DanmakuOverlayState get state => tester.state(find.byType(DanmakuOverlay));

  Rect rect(LiveMessage message) => state.rectOf(message)!;

  /// Frames of a display at [hz] for [seconds].
  Future<void> run(double hz, double seconds) async {
    final frame = Duration(microseconds: (Duration.microsecondsPerSecond / hz).round());
    final frames = (seconds * hz).round();
    for (var i = 0; i < frames; i++) {
      await tester.pump(frame);
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await messages.close();
    await retractions.close();
  }
}

void main() {
  testWidgets('c1: 3.x lanes of 26 for 16 px, the text in the middle of its lane', (tester) async {
    expect(const DanmakuLook().lane, 26);
    expect(const DanmakuLook(fontSize: 30).lane, 46.5);
    expect(const DanmakuLook(laneHeight: 20, fontSize: 10).lane, 20, reason: "the mini windows' own lanes (U.2j)");
    final layer = _Layer(tester);
    await layer.pump();
    final first = _chat('一');
    final second = _chat('二');
    layer.messages
      ..add(first)
      ..add(second);
    await tester.pump();
    final a = layer.rect(first);
    final b = layer.rect(second);
    expect(a.left, 400, reason: 'it enters at the right edge');
    expect(a.center.dy, closeTo(13, 0.01));
    expect(b.center.dy, closeTo(26 + 13, 0.01));
    await layer.close();
  });

  testWidgets('the speed is by time: 120 px/s at 60, 90, 120 and 144 Hz', (tester) async {
    final layer = _Layer(tester);
    for (final hz in [60.0, 90.0, 120.0, 144.0]) {
      await layer.pump(refreshRate: hz);
      final message = _chat('同样快 $hz');
      layer.messages.add(message);
      await tester.pump();
      final start = layer.rect(message).left;
      await layer.run(hz, 1);
      expect(start - layer.rect(message).left, closeTo(120, 1), reason: '$hz Hz');
      layer.retractions.add(const LiveRetraction.all());
      await tester.pump();
    }
    await layer.close();
  });

  test('c3: the cap as a whole fraction of the refresh rate', () {
    expect(danmakuFrameDivisor(refreshRate: 60, cap: 60), 1);
    expect(danmakuFrameDivisor(refreshRate: 120, cap: 60), 2);
    expect(danmakuFrameDivisor(refreshRate: 90, cap: 60), 2, reason: '45 a second, even steps');
    expect(danmakuFrameDivisor(refreshRate: 144, cap: 60), 3, reason: '48 a second');
    expect(danmakuFrameDivisor(refreshRate: 120.3, cap: 60), 2);
    expect(danmakuFrameDivisor(refreshRate: 60, cap: 30), 2);
    expect(danmakuFrameDivisor(refreshRate: 144, cap: 144), 1);
    expect(danmakuFrameDivisor(refreshRate: 144), 1, reason: 'no cap: every refresh');
  });

  testWidgets("B08 c4 (R5): a frame with the last one's time moves nothing; the next moves one step, not two", (
    tester,
  ) async {
    final layer = _Layer(tester);
    await layer.pump(refreshRate: 120);
    final message = _chat('同一时刻');
    layer.messages.add(message);
    await tester.pump();
    const frame = Duration(microseconds: 8333);
    await layer.run(120, 0.1);
    var x = layer.rect(message).left;
    final steps = <double>[];
    final paints = <int>[];
    Future<void> next(Duration after) async {
      final painted = layer.state.paintCount;
      await tester.pump(after);
      final now = layer.rect(message).left;
      steps.add(x - now);
      paints.add(layer.state.paintCount - painted);
      x = now;
    }

    // Variable refresh rate: the engine clamps a time that went back, so a
    // frame repeats the last time and the next vsync is two periods on
    // (Flutter #190372).
    await next(frame);
    await next(Duration.zero);
    await next(frame * 2);
    await next(frame);
    await next(Duration.zero);
    await next(frame * 2);
    await next(frame);
    const step = 120 * 8333 / Duration.microsecondsPerSecond;
    expect(steps, [
      closeTo(step, 0.001),
      0,
      closeTo(step, 0.001),
      closeTo(step, 0.001),
      0,
      closeTo(step, 0.001),
      closeTo(step, 0.001),
    ]);
    expect(paints, [1, 0, 1, 1, 0, 1, 1], reason: 'the repeated frame paints nothing');
    await layer.close();
  });

  testWidgets('c3, F.2a: a manual 30 paints about 30 times a second at 60 Hz; 60 at 120 Hz every other refresh', (
    tester,
  ) async {
    final layer = _Layer(tester);
    await layer.pump(fps: 30);
    layer.messages.add(_chat('三十帧'));
    await tester.pump();
    var before = layer.state.paintCount;
    await layer.run(60, 1);
    expect(layer.state.paintCount - before, inInclusiveRange(29, 31));

    await layer.pump(fps: 60, refreshRate: 120);
    before = layer.state.paintCount;
    await layer.run(120, 1);
    expect(layer.state.paintCount - before, inInclusiveRange(59, 61));
    await layer.close();
  });

  testWidgets('c2: a new look applies to the next ones; the ones on screen fly on at their speed', (tester) async {
    final layer = _Layer(tester);
    await layer.pump();
    final old = _chat('旧的');
    layer.messages.add(old);
    await tester.pump();
    await layer.run(60, 0.5);
    final x = layer.rect(old).left;
    await layer.pump(look: const DanmakuLook(speed: 240, fontSize: 20));
    final fresh = _chat('新的');
    layer.messages.add(fresh);
    await tester.pump();
    final y = layer.rect(fresh).left;
    await layer.run(60, 0.5);
    expect(layer.state.flyingCount, 2, reason: 'nothing was cleared');
    expect(x - layer.rect(old).left, closeTo(60, 1));
    expect(y - layer.rect(fresh).left, closeTo(120, 1));
    expect(layer.state.lastTextStyle?.fontSize, 20);
    await layer.close();
  });

  testWidgets('c5, c6: the opacity is in the colours, no layer; one layout per content and look', (tester) async {
    final layer = _Layer(tester);
    await layer.pump(look: const DanmakuLook(opacity: 0.25));
    expect(find.byType(Opacity), findsNothing);
    layer.messages
      ..add(_chat('666'))
      ..add(_chat('666'))
      ..add(_chat('666'));
    await tester.pump();
    expect(layer.state.flyingCount, 3);
    expect(layer.state.recordCount, 1);
    expect(layer.state.lastTextStyle?.color?.a, closeTo(0.25, 0.01));
    await layer.close();
  });

  testWidgets('c7: no free lane, they wait (at most four enter a frame); stale ones go after 5 s', (tester) async {
    final layer = _Layer(tester);
    // Two lanes of 26.
    await layer.pump(height: 60);
    for (var i = 0; i < 6; i++) {
      layer.messages.add(_chat('排队的第 $i 条弹幕'));
    }
    await tester.pump();
    expect(layer.state.flyingCount, 2);
    expect(layer.state.pendingCount, 4);
    await layer.run(60, 2);
    expect(layer.state.flyingCount, greaterThan(2), reason: 'the lanes took the next ones');
    expect(layer.state.flyingCount + layer.state.pendingCount, 6);

    // Long ones free a lane only after 3.8 s: the third pair is stale at 5 s.
    layer.retractions.add(const LiveRetraction.all());
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      layer.messages.add(_chat('${'长' * 25}$i'));
    }
    await layer.run(60, 6);
    expect(layer.state.pendingCount, 0);
    expect(layer.state.flyingCount, 4);

    layer.retractions.add(const LiveRetraction.all());
    await layer.pump(height: 600);
    for (var i = 0; i < 10; i++) {
      layer.messages.add(_chat('一下来十条 $i'));
    }
    final before = layer.state.flyingCount;
    await tester.pump(const Duration(milliseconds: 16));
    expect(layer.state.flyingCount - before, 4);
    await layer.close();
  });

  testWidgets('c8, F.2a: the font and text-only mode; the emoticons fly as pictures', (tester) async {
    final layer = _Layer(tester);
    final emotes = EmoteTable.of(const {'[dog]': (asset: 'assets/emo/images/bilibili/dog.png', url: '')});
    await layer.pump(
      look: const DanmakuLook(fontFamily: 'LXGW', textOnly: true),
      emotes: emotes,
    );
    layer.messages.add(_chat('[dog]'));
    await tester.pump();
    expect(layer.state.flyingCount + layer.state.pendingCount, 0, reason: 'nothing is left in text-only mode');
    final text = _chat('好[dog]');
    layer.messages.add(text);
    await tester.pump();
    expect(layer.state.lastTextStyle?.fontFamily, 'LXGW');
    final textOnly = layer.rect(text).width;

    await layer.pump(emotes: emotes);
    final picture = _chat('好[dog]');
    layer.messages.add(picture);
    for (var i = 0; i < 20 && layer.state.rectOf(picture) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(layer.rect(picture).width, greaterThan(textOnly + 16), reason: 'the picture, 1.3 × the font size');
    await layer.close();
  });

  testWidgets('c9: the danmaku at a point; held, everything stands and nothing new enters', (tester) async {
    final layer = _Layer(tester);
    await layer.pump();
    final message = _chat('点我');
    layer.messages.add(message);
    await tester.pump();
    await layer.run(60, 1);
    final rect = layer.rect(message);
    expect(layer.state.messageAt(rect.center), same(message));
    expect(layer.state.messageAt(rect.center.translate(0, 100)), isNull);

    await layer.pump(held: true);
    layer.messages.add(_chat('不进来'));
    await layer.run(60, 1);
    expect(layer.rect(message), rect);
    expect(layer.state.flyingCount, 1);
    await layer.pump();
    await layer.run(60, 0.5);
    expect(layer.rect(message).left, closeTo(rect.left - 60, 1));
    await layer.close();
  });

  test('B02 c3: danmakuRunning: playing; paused only with "继续飘过"; never while it opens, buffers or failed', () {
    for (final behavior in [DanmakuPausedBehavior.pause, DanmakuPausedBehavior.fly]) {
      expect(danmakuRunning(PlaybackStatus.playing, behavior), isTrue, reason: behavior);
      for (final status in [PlaybackStatus.opening, PlaybackStatus.buffering, PlaybackStatus.error]) {
        expect(danmakuRunning(status, behavior), isFalse, reason: '$status $behavior');
      }
    }
    expect(danmakuRunning(PlaybackStatus.paused, DanmakuPausedBehavior.pause), isFalse);
    expect(danmakuRunning(PlaybackStatus.paused, DanmakuPausedBehavior.fly), isTrue);
    expect(danmakuRunning(PlaybackStatus.paused, 'anything else'), isFalse, reason: 'the default');
  });

  testWidgets("c10: a paused video stops the platform's danmaku; a local one still enters and flies", (tester) async {
    final layer = _Layer(tester);
    await layer.pump();
    final message = _chat('暂停');
    layer.messages.add(message);
    await tester.pump();
    await layer.run(60, 0.5);
    await layer.pump(running: false);
    final rect = layer.rect(message);
    layer.messages
      ..add(_chat('暂停时来的'))
      ..add(_local);
    await layer.run(60, 1);
    expect(layer.rect(message), rect);
    expect(layer.state.flyingCount, 2);
    expect(layer.rect(_local).left, closeTo(400 - 100 + 100 / 60, 2), reason: 'its own speed, 100 px/s');
    await layer.close();
  });

  testWidgets('a retraction takes it off the screen', (tester) async {
    final layer = _Layer(tester);
    await layer.pump();
    layer.messages
      ..add(_chat('撤回', id: 'x'))
      ..add(_chat('留下', id: 'y'));
    await tester.pump();
    layer.retractions.add(const LiveRetraction.message('x'));
    await tester.pump();
    expect(layer.state.flyingCount, 1);
    await layer.close();
  });
}
