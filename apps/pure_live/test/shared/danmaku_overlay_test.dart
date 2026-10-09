import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

// U.2h (docs/D-弹幕/D03-飞行弹幕引擎/D03.1-飞行弹幕渲染) c1-c10 and F.2a on the flying layer.

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

/// Answers every image request with [bytes] and keeps the addresses.
final class _ImageService extends FileService {
  new(this.bytes);

  final List<int> bytes;
  final List<String> urls = [];

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    urls.add(url);
    return _ImageResponse(bytes);
  }
}

final class _ImageResponse implements FileServiceResponse {
  new(this.bytes);

  final List<int> bytes;

  @override
  Stream<List<int>> get content => Stream.value(bytes);

  @override
  int get contentLength => bytes.length;

  @override
  String? get eTag => null;

  @override
  String get fileExtension => '.png';

  @override
  int get statusCode => 200;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
}

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
    int? maxVisible = 48,
    EmoteTable emotes = EmoteTable.empty,
    EdgeInsets giftClearance = EdgeInsets.zero,
    Color? color,
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
            maxVisible: maxVisible,
            emotes: emotes,
            giftClearance: giftClearance,
            color: color,
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

  testWidgets('D03.3 c4: at most 48 remote danmaku on screen by default (3.x); local ones do not count', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layer = _Layer(tester);
    // Lanes for far more than 48 short ones.
    await layer.pump(height: 4000);
    for (var i = 0; i < 60; i++) {
      layer.messages.add(_chat('$i'));
    }
    await layer.run(60, 1);
    expect(layer.state.flyingCount, 48);
    expect(layer.state.pendingCount, 12);
    layer.messages
      ..add(_local)
      ..add(_local);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(layer.state.flyingCount, 50, reason: 'the local ones still get a place');
    await layer.close();
  });

  testWidgets('D05.2: "同屏最大弹幕条数": a lower limit lets the next ones wait; a higher one lets them in', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layer = _Layer(tester);
    await layer.pump(height: 4000, maxVisible: 10);
    for (var i = 0; i < 30; i++) {
      layer.messages.add(_chat('$i'));
    }
    await layer.run(60, 1);
    expect(layer.state.flyingCount, 10);
    expect(layer.state.pendingCount, 20);

    // Raised while they wait: the waiting ones enter at once (four a frame).
    await layer.pump(height: 4000, maxVisible: 24);
    await layer.run(60, 0.5);
    expect(layer.state.flyingCount, 24);
    expect(layer.state.pendingCount, 6);

    // Lowered: the ones on screen fly on, nothing new enters until fewer
    // than the limit are left.
    await layer.pump(height: 4000, maxVisible: 12);
    layer.messages.add(_chat('等着'));
    await layer.run(60, 0.5);
    expect(layer.state.flyingCount, 24, reason: 'none is taken off the screen');
    expect(layer.state.pendingCount, 7);
    await layer.close();
  });

  testWidgets("Q02.1: a network emoticon loads through the app's image cache (the app proxy)", (tester) async {
    final previous = AppImageCache.manager;
    addTearDown(() => AppImageCache.manager = previous);
    final png = File('assets/emo/images/bilibili/dog.png').readAsBytesSync();
    final service = _ImageService(png);
    AppImageCache.manager = CacheManager(
      Config('test', repo: NonStoringObjectProvider(), fileSystem: MemoryCacheSystem(), fileService: service),
    );
    const url = 'https://emotes.example/dog.png';
    final layer = _Layer(tester);
    await layer.pump(emotes: EmoteTable.of(const {'[dog]': (asset: '', url: url)}));
    final picture = _chat('好[dog]');
    layer.messages.add(picture);
    for (var i = 0; i < 20 && layer.state.rectOf(picture) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(service.urls, [url]);
    expect(layer.state.rectOf(picture), isNotNull, reason: 'the picture arrived and the danmaku flies');
    await layer.close();
    // flutter_cache_manager's clean-up after a lookup, 10 s later.
    await tester.pump(const Duration(seconds: 11));
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

  testWidgets('D03.4 (V01.3): a pinned danmaku stands, the others fly on; let go, it flies on from there', (
    tester,
  ) async {
    final layer = _Layer(tester);
    // Two lanes of 26.
    await layer.pump(height: 60);
    final pinned = _chat('按住我');
    final other = _chat('照飞');
    layer.messages
      ..add(pinned)
      ..add(other);
    await tester.pump();
    await layer.run(60, 1);
    final at = layer.rect(pinned);
    final before = layer.rect(other);
    expect(layer.state.pinAt(at.center.translate(0, 100)), isNull, reason: 'nothing there');
    expect(layer.state.pinAt(at.center), same(pinned));
    expect(layer.state.pinnedMessage, same(pinned));

    await layer.run(60, 2);
    expect(layer.rect(pinned), at, reason: 'it stands');
    expect(layer.rect(other).left, closeTo(before.left - 240, 2), reason: 'the other flies on, 120 px/s');
    expect(layer.state.messageAt(at.center), same(pinned), reason: 'a long press there finds it');

    layer.state.unpin();
    expect(layer.state.pinnedMessage, isNull);
    await layer.run(60, 0.5);
    expect(layer.rect(pinned).left, closeTo(at.left - 60, 2), reason: 'on from where it stood, at its speed');

    // Everything held (the actions open) while it is pinned: let go after,
    // it does not jump.
    final again = layer.rect(pinned);
    layer.state.pinAt(again.center);
    await layer.pump(height: 60, held: true);
    await layer.run(60, 1);
    layer.state.unpin();
    await layer.pump(height: 60);
    expect(layer.rect(pinned), again);

    // A pinned one taken back is gone, and nothing stays pinned.
    layer.state.pinAt(layer.rect(pinned).center);
    layer.retractions.add(const LiveRetraction.all());
    await tester.pump();
    expect(layer.state.pinnedMessage, isNull);
    expect(layer.state.flyingCount, 0);
    await layer.close();
  });

  testWidgets("D03.4: no new danmaku enters a pinned one's lane; let go, the lane takes them again", (tester) async {
    final layer = _Layer(tester);
    // One lane.
    await layer.pump(height: 30);
    final pinned = _chat('按住我');
    layer.messages.add(pinned);
    await tester.pump();
    await layer.run(60, 1);
    layer.state.pinAt(layer.rect(pinned).center);
    final next = _chat('后来的');
    layer.messages.add(next);
    await layer.run(60, 2);
    expect(layer.state.rectOf(next), isNull, reason: 'well in, but it stands: the lane waits');
    expect(layer.state.pendingCount, 1);
    layer.state.unpin();
    await layer.run(60, 0.1);
    expect(layer.state.rectOf(next), isNotNull);
    expect(layer.state.pendingCount, 0);
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

  group('A08.12: gifts over the picture', () {
    testWidgets('a gift flies in the gift look, recorded once; frames only move it; the one colour does not touch it', (
      tester,
    ) async {
      final layer = _Layer(tester);
      await layer.pump(color: const Color(0xFF00FF00));
      final gift = _flyingGift('甲 送出 告白气球 ×1');
      layer.messages.add(gift);
      await tester.pump();
      expect(layer.state.recordCount, 1);
      final style = layer.state.lastTextStyle!;
      expect(style.color, LivePalettes.danmakuGift, reason: 'gold, whatever the one colour is');
      expect(style.fontWeight!.value, greaterThanOrEqualTo(600));
      // The frame and the icon around the words: wider than the words alone.
      final chat = _chat('甲 送出 告白气球 ×1');
      layer.messages.add(chat);
      await tester.pump();
      expect(layer.rect(gift).width, greaterThan(layer.rect(chat).width + 16));
      expect(layer.rect(gift).height, lessThanOrEqualTo(const DanmakuLook().lane));
      expect(layer.state.lastTextStyle!.color, const Color(0xFF00FF00));
      final records = layer.state.recordCount;
      final painted = layer.state.paintCount;
      layer.messages.add(_flyingGift('甲 送出 告白气球 ×1'));
      await layer.run(60, 1);
      expect(layer.state.recordCount, records, reason: 'the same gift again: from the cache');
      expect(layer.state.paintCount - painted, inInclusiveRange(59, 61), reason: 'one painting a frame, as for chat');
      expect(layer.rect(gift).left, closeTo(400 - 120 * 61 / 60, 3), reason: 'it scrolls at the look speed');
      await layer.close();
    });

    testWidgets('the danmaku outline and opacity apply to it (readable on the video)', (tester) async {
      final layer = _Layer(tester);
      await layer.pump(look: const DanmakuLook(opacity: 0.5, strokeWidth: 2));
      layer.messages.add(_flyingGift('乙 送出 飞机 ×1'));
      await tester.pump();
      final style = layer.state.lastTextStyle!;
      expect(style.color!.a, closeTo(0.5, 0.01));
      expect(style.color!.withValues(alpha: 1), LivePalettes.danmakuGift);
      await layer.pump(look: const DanmakuLook(stroke: false));
      layer.messages.add(_flyingGift('丙 送出 飞机 ×1'));
      await tester.pump();
      expect(layer.state.recordCount, 2, reason: 'another look, another recording');
      await layer.close();
    });

    testWidgets('a precious one stands at the top, centred, for 4 s, over the chat flying past', (tester) async {
      final layer = _Layer(tester);
      await layer.pump();
      final gift = _flyingGift('丁 送出 火箭 ×1', tier: LiveGiftTier.precious);
      layer.messages.add(gift);
      await tester.pump();
      final rect = layer.rect(gift);
      expect(rect.center.dx, closeTo(200, 0.5));
      expect(rect.top, lessThan(const DanmakuLook().lane));
      final second = _flyingGift('戊 送出 火箭 ×1', tier: LiveGiftTier.precious);
      layer.messages.add(second);
      await tester.pump();
      expect(layer.rect(second).top, closeTo(rect.top + const DanmakuLook().lane, 0.5), reason: 'the next place');
      await layer.run(60, 3.5);
      expect(layer.rect(gift), rect, reason: 'it stands');
      await layer.run(60, 1);
      expect(layer.state.rectOf(gift), isNull, reason: 'gone after 4 s');
      expect(DanmakuOverlayState.giftHold, const Duration(seconds: 4));
      await layer.close();
    });

    testWidgets('fullscreen bars: gifts keep clear of them; the chat does not change', (tester) async {
      final layer = _Layer(tester);
      const clear = EdgeInsets.only(top: 60, bottom: 60);
      await layer.pump(giftClearance: clear);
      final held = _flyingGift('甲 送出 火箭 ×1', tier: LiveGiftTier.precious);
      final gifts = [for (var i = 0; i < 6; i++) _flyingGift('观众$i 送出 告白气球 ×1')];
      final chat = _chat('聊天');
      layer.messages
        ..add(chat)
        ..add(held);
      gifts.forEach(layer.messages.add);
      // Four enter a frame.
      await tester.pump();
      await layer.run(60, 0.1);
      expect(layer.rect(chat).top, lessThan(26), reason: 'the chat takes the first lane as before');
      expect(layer.rect(held).top, greaterThanOrEqualTo(60));
      for (final gift in gifts) {
        final rect = layer.rect(gift);
        expect(rect.top, greaterThanOrEqualTo(60), reason: '${gift.message}: below the top bar');
        expect(rect.bottom, lessThanOrEqualTo(300 - 60), reason: '${gift.message}: above the bottom bar');
      }
      await layer.close();
    });

    testWidgets('the display range and the bars leave no lane: a gift takes the lanes there are', (tester) async {
      final layer = _Layer(tester);
      await layer.pump(look: const DanmakuLook(area: 0.2), giftClearance: const EdgeInsets.only(top: 120));
      final gift = _flyingGift('甲 送出 告白气球 ×1');
      layer.messages.add(gift);
      await tester.pump();
      expect(layer.rect(gift).bottom, lessThanOrEqualTo(300 * 0.2), reason: 'inside the display range');
      await layer.close();
    });

    testWidgets('"同屏最大弹幕条数" counts gifts with the chat; a gift over it waits in the same line', (tester) async {
      final layer = _Layer(tester);
      await layer.pump(maxVisible: 2);
      final gift = _flyingGift('甲 送出 告白气球 ×1');
      layer.messages
        ..add(_chat('一'))
        ..add(_chat('二'))
        ..add(gift);
      await tester.pump();
      expect(layer.state.flyingCount, 2);
      expect(layer.state.rectOf(gift), isNull);
      expect(layer.state.pendingCount, 1);
      await layer.pump(maxVisible: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(layer.state.rectOf(gift), isNotNull);
      await layer.close();
    });

    testWidgets('its picture: the icon until it has loaded, not recorded again; the next one has it', (tester) async {
      final previous = AppImageCache.manager;
      addTearDown(() => AppImageCache.manager = previous);
      final png = File('assets/emo/images/bilibili/dog.png').readAsBytesSync();
      final service = _ImageService(png);
      AppImageCache.manager = CacheManager(
        Config('gift', repo: NonStoringObjectProvider(), fileSystem: MemoryCacheSystem(), fileService: service),
      );
      const url = 'https://gifts.example/rocket.png';
      final layer = _Layer(tester);
      await layer.pump();
      final first = _flyingGift('甲 送出 火箭 ×1', icon: url);
      layer.messages.add(first);
      await tester.pump();
      expect(layer.state.rectOf(first), isNotNull, reason: 'it does not wait for its picture');
      final width = layer.rect(first).width;
      for (var i = 0; i < 20 && service.urls.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(service.urls, [url]);
      expect(layer.state.recordCount, 1, reason: 'the one on screen is not recorded again');
      expect(layer.rect(first).width, width);
      layer.messages.add(_flyingGift('甲 送出 火箭 ×1', icon: url));
      await tester.pump();
      expect(layer.state.recordCount, 2, reason: 'the next one is recorded with the picture');
      await layer.close();
      await tester.pump(const Duration(seconds: 11));
    });

    test('the frame: thicker for a precious gift, so the tiers differ without their colour', () {
      expect(giftFrameWidth(LiveGiftTier.precious), greaterThan(giftFrameWidth(LiveGiftTier.valuable)));
    });
  });
}

/// A gift as the room's gate hands it to the flying layer: its words, a
/// value of the [tier].
LiveMessage _flyingGift(String words, {LiveGiftTier tier = LiveGiftTier.valuable, String? icon}) {
  final gift = LiveGift(
    name: '礼物',
    totalValue: tier == LiveGiftTier.precious ? 500000 : 52000,
    unit: LiveGiftUnit.goldSeed,
    iconUrl: icon == null ? null : Uri.parse(icon),
  );
  return LiveMessage(
    type: LiveMessageType.gift,
    userName: words.split(' ').first,
    message: words,
    color: LiveMessageColor.white,
    data: gift,
  );
}
