import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

void main() {
  group('U.2i: the frame rate of the video', () {
    test("mpv's container-fps first; a live FLV's 1000 is no frame rate", () {
      expect(parseFrameRate('29.970030'), closeTo(29.97, 0.001));
      expect(parseFrameRate('1000.000000'), isNull);
      expect(parseFrameRate(''), isNull);
      fakeAsync((async) {
        final reads = <String>[];
        double? fps;
        unawaited(
          probeFrameRate((property) async {
            reads.add(property);
            return '25.000000';
          }).then((value) => fps = value),
        );
        async.elapse(const Duration(seconds: 2));
        expect(fps, 25);
        expect(reads, ['container-fps']);
      });
    });

    test('without it, an estimate that holds over two readings; nothing after the open is replaced', () {
      fakeAsync((async) {
        final estimates = ['59.2', '59.9', '59.95'];
        double? fps;
        unawaited(
          probeFrameRate((property) async => property == 'container-fps' ? '' : estimates.removeAt(0))
              .then((value) => fps = value),
        );
        async.elapse(const Duration(seconds: 6));
        expect(fps, 59.95);

        var current = true;
        double? replaced = -1;
        unawaited(probeFrameRate((_) async => '', current: () => current).then((value) => replaced = value));
        current = false;
        async.elapse(const Duration(seconds: 10));
        expect(replaced, isNull);
      });
    });

    test('the session keeps it with the stream and forgets it when the stream stops', () {
      fakeAsync((async) {
        final engine = FakeEngine();
        final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
        unawaited(
          session.open(
            PlaybackRequest(
              site: 'douyu',
              plan: PlaybackPlan.of(LivePlayUrlResolution.lines(const [LivePlayLine('https://a.example/1.flv')])),
            ),
          ),
        );
        async.flushMicrotasks();
        engine.emit(const EngineFrameRate(30));
        expect(session.state.frameRate, 30);
        unawaited(session.stop());
        async.flushMicrotasks();
        expect(session.state.frameRate, isNull);
      });
    });
  });

  group('F.1a: the screen stays on while the view plays', () {
    late List<bool> applied;

    setUp(() {
      applied = [];
      ScreenWake.reset();
      ScreenWake.apply = ({required enabled}) async => applied.add(enabled);
    });
    tearDown(ScreenWake.reset);

    Future<PlaybackSession> playing(WidgetTester tester) async {
      final session = PlaybackSession(engine: () async => FakeEngine(), opener: MediaOpener());
      await session.open(
        PlaybackRequest(
          site: 'douyu',
          plan: PlaybackPlan.of(LivePlayUrlResolution.lines(const [LivePlayLine('https://a.example/1.flv')])),
        ),
      );
      expect(session.state.status, PlaybackStatus.playing);
      return session;
    }

    Widget view(PlaybackSession session, {required bool keepOn}) => Directionality(
      textDirection: TextDirection.ltr,
      child: LiveVideoView(session: session, keepScreenOn: keepOn),
    );

    testWidgets('off: never asked; on: asked at once, released when the view goes', (tester) async {
      final session = await playing(tester);
      await tester.pumpWidget(view(session, keepOn: false));
      expect(applied, isEmpty);
      expect(ScreenWake.held, isFalse);

      await tester.pumpWidget(view(session, keepOn: true));
      expect(applied, [true]);
      await tester.pumpWidget(view(session, keepOn: false));
      expect(applied, [true, false]);
      await tester.pumpWidget(view(session, keepOn: true));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(applied, [true, false, true, false]);
      await session.dispose();
    });

    testWidgets('two views share one count; a paused session lets go', (tester) async {
      final session = await playing(tester);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Expanded(child: LiveVideoView(session: session)),
              Expanded(child: LiveVideoView(session: session)),
            ],
          ),
        ),
      );
      expect(applied, [true]);
      await session.togglePlayPause();
      await tester.pump();
      expect(session.state.status, PlaybackStatus.paused);
      expect(applied, [true, false]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(applied, [true, false]);
      await session.dispose();
    });
  });
}
