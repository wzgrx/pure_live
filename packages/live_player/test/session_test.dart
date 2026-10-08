import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

const _a = LivePlayLine(
  'https://a.example/live.flv?sign=1',
  headers: {'referer': 'https://room.example/'},
  lineId: 'a',
);
const _b = LivePlayLine('https://b.example/live.flv?sign=1', lineId: 'b');

PlaybackPlan _plan(List<LivePlayLine> lines, {bool onDemand = false}) =>
    PlaybackPlan.of(LivePlayUrlResolution.lines(lines), onDemand: onDemand);

const _network = PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport');

void main() {
  late FakeEngine engine;
  late PlaybackSession session;

  PlaybackSession start(PlaybackRequest request, FakeAsync async) {
    engine = FakeEngine();
    session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    unawaited(session.open(request));
    async.flushMicrotasks();
    return session;
  }

  test('opens the first line with its headers and plays', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
      expect(engine.opens.single.uri.toString(), _a.url);
      expect(engine.opens.single.headers, _a.headers);
      expect(engine.opens.single.decoder, DecoderMode.hardware);
      expect(session.state.status, PlaybackStatus.playing);
      expect(session.state.lineIndex, 0);
      expect(session.state.lineCount, 2);
    });
  });

  test('G01.4: a line with a variant selector opens through the relay, which restricts its master', () async {
    final relay = await LoopbackRelay.start();
    addTearDown(relay.close);
    const master = LivePlayLine('https://steam.example/master.m3u8', format: StreamFormat.hls);
    fakeAsync((async) {
      engine = FakeEngine();
      session = PlaybackSession(
        engine: () async => engine,
        opener: MediaOpener(relay: () async => relay),
      );
      final plan = PlaybackPlan.of(
        LivePlayUrlResolution.lines(const [master], sourceVariantSelectors: {master.url: _Selector()}),
      );
      unawaited(session.open(PlaybackRequest(site: 'steambroadcast', plan: plan)));
      async.flushMicrotasks();
      expect(engine.opens.single.uri.host, '127.0.0.1', reason: 'the relay, not the CDN master');
      expect(session.state.status, PlaybackStatus.playing);
    });
  });

  test('a network failure without a refresher walks to the next line', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
      engine.emit(const EngineError(_network));
      async.flushMicrotasks();
      expect(engine.opens.map((media) => media.uri.host), ['a.example', 'b.example']);
      expect(session.state.status, PlaybackStatus.playing);
      expect(session.state.lineIndex, 1);
    });
  });

  test('a network failure refreshes the plan and reopens the same line first', () {
    fakeAsync((async) {
      var refreshes = 0;
      const renewed = LivePlayLine('https://a.example/live.flv?sign=2', lineId: 'a');
      start(
        PlaybackRequest(
          site: 'huya',
          plan: _plan([_a, _b]),
          refresh: () async {
            refreshes++;
            return _plan([_b, renewed]);
          },
        ),
        async,
      );
      engine.emit(const EngineError(_network));
      async.flushMicrotasks();
      expect(refreshes, 1);
      expect(engine.opens.last.uri.toString(), renewed.url);
      expect(session.plan!.lines.first.url, _b.url);
      expect(session.state.status, PlaybackStatus.playing);
    });
  });

  test('a lease that does not cut the connection is prefetched and used on the next failure', () {
    final now = DateTime.utc(2026, 10);
    fakeAsync((async) {
      var refreshes = 0;
      final leased = LivePlayLine(
        'https://a.example/live.flv?wsTime=1',
        lineId: 'a',
        lease: PlayLease(refreshAt: now.add(const Duration(minutes: 5)), expiresAt: now.add(const Duration(hours: 1))),
      );
      final fresh = LivePlayLine(
        'https://a.example/live.flv?wsTime=2',
        lineId: 'a',
        lease: PlayLease(refreshAt: now.add(const Duration(minutes: 30)), expiresAt: now.add(const Duration(hours: 2))),
      );
      start(
        PlaybackRequest(
          site: 'huya',
          plan: _plan([leased]),
          refresh: () async {
            refreshes++;
            return _plan([fresh]);
          },
        ),
        async,
      );
      async.elapse(const Duration(minutes: 5, seconds: 1));
      // Prefetched without touching the healthy transport.
      expect(refreshes, 1);
      expect(engine.opens, hasLength(1));
      engine.emit(const EngineCompleted());
      async.flushMicrotasks();
      expect(refreshes, 1, reason: 'the prefetched plan is consumed');
      expect(engine.opens.last.uri.toString(), fresh.url);
      expect(session.state.status, PlaybackStatus.playing);
    }, initialTime: now);
  });

  test('a decoder failure retries the source with software decoding; an audio one does not', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'kuaishou', plan: _plan([_a])), async);
      engine.emit(
        const EngineError(PlayerException(message: 'no decoder found', type: PlayerErrorType.codec, code: 'video_x')),
      );
      async.flushMicrotasks();
      expect(engine.opens.map((media) => media.decoder), [DecoderMode.hardware, DecoderMode.software]);
      expect(session.state.decoder, DecoderMode.software);

      start(PlaybackRequest(site: 'kuaishou', plan: _plan([_a])), async);
      engine.emit(
        const EngineError(PlayerException(message: 'ad failed', type: PlayerErrorType.codec, code: 'audio_decoder')),
      );
      async.flushMicrotasks();
      expect(engine.opens, hasLength(1));
      expect(session.state.status, PlaybackStatus.error);
    });
  });

  test('the platform refusing the stream is published at once, without walking the lines', () {
    fakeAsync((async) {
      start(
        PlaybackRequest(
          site: 'bilibili',
          plan: _plan([_a, _b]),
          refresh: () async => throw const StreamUnavailable('bilibili', 'offline'),
        ),
        async,
      );
      engine.emit(const EngineError(_network));
      async.flushMicrotasks();
      expect(engine.opens, hasLength(1));
      expect(session.state.status, PlaybackStatus.error);
      expect(session.state.failure, SourceFailureKind.terminal);
      expect(session.state.error, isA<StreamUnavailable>());
    });
  });

  test('exhausted recovery waits for bounded retry rounds, then publishes the error', () {
    fakeAsync((async) {
      Future<void> notFound(EngineMedia _) async => throw const PlayerException(
        message: 'server returned 404',
        type: PlayerErrorType.source,
        code: 'source_open',
      );
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      engine
        ..onOpen = notFound
        ..emit(const EngineError(_network));
      async.flushMicrotasks();
      // Software retry of the one line failed too: a retry round is pending.
      expect(session.state.status, PlaybackStatus.buffering);
      async.elapse(const Duration(seconds: 10));
      expect(session.state.status, PlaybackStatus.error);
      expect(session.state.failure, SourceFailureKind.transient);
      final opens = engine.opens.length;
      async.elapse(const Duration(minutes: 1));
      expect(engine.opens, hasLength(opens), reason: 'nothing reopens after the error');
    });
  });

  test('buffering that never ends is recovered once its first deadline passes', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
      engine.emit(const EngineBuffering(buffering: true));
      async.elapse(const Duration(seconds: 8));
      // Repeated notifications keep the first deadline.
      engine.emit(const EngineBuffering(buffering: true));
      async.elapse(const Duration(seconds: 5));
      expect(engine.opens.last.uri.host, 'b.example');
    });
  });

  test('B02: the state says when the session recovers and which attempt; buffering, a resume and the user do not', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'yy', plan: _plan([_a, _b])), async);
      final seen = <(PlaybackStatus, int)>[];
      final subscription = session.states.listen((state) => seen.add((state.status, state.recovery)));
      addTearDown(subscription.cancel);

      // A stream that waits for data (a YY room right after it starts) has
      // not failed: buffering, no recovery.
      engine.emit(const EngineBuffering(buffering: true));
      expect((session.state.status, session.state.recovering), (PlaybackStatus.buffering, false));
      engine.playing();
      expect(session.state.status, PlaybackStatus.playing);

      // A drop: every step of the recovery carries the attempt; playing
      // again ends it.
      seen.clear();
      engine.emit(const EngineError(_network));
      async.flushMicrotasks();
      expect(seen.where((state) => state.$1 != PlaybackStatus.playing), everyElement((PlaybackStatus.buffering, 1)));
      expect(seen.last, (PlaybackStatus.playing, 0));
      expect(session.state.lineIndex, 1);

      // Another drop soon after is the second attempt; after sustained
      // playback the count starts again.
      seen.clear();
      engine.emit(const EngineError(PlayerException(message: 'reset', type: PlayerErrorType.network, code: 'b')));
      async.flushMicrotasks();
      expect(seen.first, (PlaybackStatus.buffering, 2));
      // Both lines failed: a retry round, the third attempt, brings it back.
      async.elapse(const Duration(seconds: 1));
      expect(seen.map((state) => state.$2), contains(3));
      expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
      async.elapse(const Duration(seconds: 31));
      seen.clear();
      engine.emit(const EngineError(PlayerException(message: 'reset', type: PlayerErrorType.network, code: 'c')));
      async.flushMicrotasks();
      expect(seen.first, (PlaybackStatus.buffering, 1));

      // A pause and its resume: buffering again, no recovery.
      unawaited(session.pause());
      async.flushMicrotasks();
      seen.clear();
      unawaited(session.resume());
      async.flushMicrotasks();
      expect(seen.first, (PlaybackStatus.buffering, 0));
      expect(seen.map((state) => state.$2), everyElement(0));

      // The user's own line switch is no recovery either.
      seen.clear();
      unawaited(session.selectLine(0));
      async.flushMicrotasks();
      expect(seen.map((state) => state.$2), everyElement(0));
    });
  });

  test('B02: retry rounds count as attempts; the published error ends the recovery', () {
    fakeAsync((async) {
      Future<void> notFound(EngineMedia _) async => throw const PlayerException(
        message: 'server returned 404',
        type: PlayerErrorType.source,
        code: 'source_open',
      );
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      engine
        ..onOpen = notFound
        ..emit(const EngineError(_network));
      async.flushMicrotasks();
      final first = session.state.recovery;
      expect(first, greaterThan(0));
      async.elapse(const Duration(seconds: 1));
      expect(session.state.recovery, greaterThan(first), reason: 'the first round');
      async.elapse(const Duration(seconds: 10));
      expect((session.state.status, session.state.recovering), (PlaybackStatus.error, false));
    });
  });

  test('a user pause is kept; an unexpected live pause asks the engine to play', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      unawaited(session.pause());
      async.flushMicrotasks();
      engine.emit(const EnginePlaying(playing: false));
      async.elapse(const Duration(seconds: 10));
      expect(session.state.status, PlaybackStatus.paused);
      expect(engine.calls.where((call) => call == 'play'), isEmpty);

      unawaited(session.resume());
      async.flushMicrotasks();
      engine.emit(const EnginePlaying(playing: true));
      engine.calls.clear();
      engine.emit(const EnginePlaying(playing: false));
      async.elapse(const Duration(milliseconds: 400));
      expect(engine.calls, contains('play'));
      expect(session.state.status, isNot(PlaybackStatus.paused));
    });
  });

  test('a replay ends as completed, not as a failure, and seeks', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'huya', plan: _plan([_a], onDemand: true)), async);
      engine.emit(const EngineCompleted());
      async.flushMicrotasks();
      expect(session.state.status, PlaybackStatus.completed);
      expect(engine.opens, hasLength(1));
      unawaited(session.seek(const Duration(seconds: 30)));
      async.flushMicrotasks();
      expect(engine.calls, containsAllInOrder(['seek 30', 'play']));

      start(PlaybackRequest(site: 'huya', plan: _plan([_a, _b])), async);
      engine.emit(const EngineCompleted());
      async.flushMicrotasks();
      expect(engine.opens.last.uri.host, 'b.example', reason: 'a live source ending is a failure');
    });
  });

  test('a diagnostic during the open is dropped once the source plays', () {
    fakeAsync((async) {
      engine = FakeEngine();
      session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
      engine.onOpen = (_) async {
        engine
          ..emit(const EngineError(_network))
          ..playing();
      };
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b]))));
      async.flushMicrotasks();
      expect(engine.opens, hasLength(1));
      expect(session.state.status, PlaybackStatus.playing);
    });
  });

  test('stop releases the input and keeps the engine until it idles', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      final input = session.input!;
      unawaited(session.stop());
      async.flushMicrotasks();
      expect(input.isUsable, isFalse);
      expect(session.state.status, PlaybackStatus.stopped);
      expect(engine.calls, contains('stop'));
      expect(engine.disposed, isFalse);
      async.elapse(const Duration(seconds: 46));
      expect(engine.disposed, isTrue);
      expect(session.engine, isNull);
    });
  });

  test('overlapping stops, then an open: no idle release of the playing engine', () {
    // Release fixes, item 9: the first stop's idle timer was overwritten,
    // never cancelled, and released the engine 45 s into the next playback.
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      unawaited(session.stop());
      unawaited(session.stop());
      async.flushMicrotasks();
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]))));
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 46));
      expect(session.state.status, PlaybackStatus.playing);
      expect(engine.disposed, isFalse);
      expect(session.engine, same(engine));
    });
  });

  test('a stop still finishing when the next open starts arms no idle release', () {
    fakeAsync((async) {
      start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
      unawaited(session.stop());
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_b]))));
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 46));
      expect(session.state.status, PlaybackStatus.playing);
      expect(engine.opens.last.uri.host, 'b.example');
      expect(engine.disposed, isFalse);
    });
  });

  test('disposed while the engine is still being created: dispose waits for it and releases it', () {
    fakeAsync((async) {
      engine = FakeEngine();
      final creating = Completer<PlayerEngine>();
      session = PlaybackSession(engine: () => creating.future, opener: MediaOpener());
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]))));
      async.flushMicrotasks();
      var done = false;
      unawaited(session.dispose().then((_) => done = true));
      async.flushMicrotasks();
      expect(done, isFalse, reason: 'the engine is still being created');
      creating.complete(engine);
      async.flushMicrotasks();
      expect(engine.disposed, isTrue);
      expect(engine.opens, isEmpty);
      expect(session.engine, isNull);
      expect(done, isTrue);
    });
  });

  test('disposed while the engine creation fails: dispose still completes', () {
    fakeAsync((async) {
      final creating = Completer<PlayerEngine>();
      session = PlaybackSession(engine: () => creating.future, opener: MediaOpener());
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]))));
      async.flushMicrotasks();
      var done = false;
      unawaited(session.dispose().then((_) => done = true));
      creating.completeError(StateError('no decoder'));
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(session.engine, isNull);
    });
  });

  test('a stalled open is bounded and the next line is tried', () {
    fakeAsync((async) {
      engine = FakeEngine();
      session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
      engine.onOpen = (media) async {
        if (media.uri.host == 'a.example') {
          await Completer<void>().future;
          return;
        }
        engine.playing();
      };
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b]))));
      async.elapse(const Duration(seconds: 19));
      expect(engine.opens.last.uri.host, 'b.example');
      expect(session.state.status, PlaybackStatus.playing);
    });
  });

  test('a picture off screen is not judged stalled; on screen again, the watchdog starts afresh', () {
    fakeAsync((async) {
      engine = FakeEngine()..reportsFrames = true;
      session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
      unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b]))));
      async.flushMicrotasks();
      session.setPresentationVisible(visible: false);
      expect(session.presentationVisible, isFalse);
      async.elapse(const Duration(seconds: 30));
      expect(engine.opens, hasLength(1));
      expect(session.state.status, PlaybackStatus.playing);
      session.setPresentationVisible(visible: true);
      async.elapse(const Duration(seconds: 9));
      expect(engine.opens, hasLength(1));
      async.elapse(const Duration(seconds: 2));
      // Still no frame ten seconds after it showed again: recovered.
      expect(engine.opens, hasLength(greaterThan(1)));
    });
  });

  test("F.1b: the line's declared size lays out the picture until the decoder reports one", () {
    fakeAsync((async) {
      const portrait = LivePlayLine('https://a.example/portrait.flv', lineId: 'a', width: 1088, height: 1920);
      final states = <PlaybackState>[];
      engine = FakeEngine();
      session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
      session.states.listen(states.add);
      unawaited(session.open(PlaybackRequest(site: 'douyin', plan: _plan([portrait]))));
      async.flushMicrotasks();
      final opening = states.firstWhere((state) => state.status == PlaybackStatus.opening && state.line != null);
      expect(opening.aspectRatio, isNull, reason: 'no frame yet');
      expect(opening.declaredAspectRatio, closeTo(1088 / 1920, 1e-9));
      expect(opening.expectsPortrait, isTrue);
      expect(opening.isPortrait, isFalse, reason: 'isPortrait still only follows the decoder');

      // The decoder wins once it speaks.
      engine.emit(const EngineVideoSize(1920, 1080));
      async.flushMicrotasks();
      expect(session.state.expectedAspectRatio, closeTo(16 / 9, 1e-9));
      expect(session.state.expectsPortrait, isFalse);

      // A stopped session declares nothing (its next room starts unknown).
      unawaited(session.stop());
      async.flushMicrotasks();
      expect(session.state.declaredAspectRatio, isNull);
      expect(session.state.expectsPortrait, isFalse);

      // A line without a size declares nothing.
      unawaited(session.open(PlaybackRequest(site: 'douyin', plan: _plan([_b]))));
      async.flushMicrotasks();
      expect(session.state.declaredAspectRatio, isNull);
      async.elapse(const Duration(seconds: 1));
    });
  });

  group('G02.3: the network goes away and comes back', () {
    /// A Bilibili plan whose refresh needs the network: offline it fails as
    /// the HTTP client does ([hang]: it never answers instead).
    PlaybackRequest request({required bool Function() online, bool hang = false, void Function()? onRefresh}) =>
        PlaybackRequest(
          site: 'bilibili',
          plan: _plan([_a, _b]),
          refresh: () async {
            onRefresh?.call();
            if (online()) return _plan([_a, _b]);
            if (hang) await Completer<void>().future;
            throw const TransportFailure('bilibili', TransportReason.connect);
          },
        );

    /// mpv's `time-pos` moving on every second while [flowing] says so.
    Timer play(bool Function() flowing) {
      final ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (flowing()) engine.advance();
      });
      addTearDown(ticker.cancel);
      return ticker;
    }

    test('a stream that stops moving says it reconnects within seconds; flipping flags do not postpone it', () {
      fakeAsync((async) {
        var refreshes = 0;
        var flowing = true;
        start(request(online: () => true, onRefresh: () => refreshes++), async);
        final ticker = play(() => flowing);
        async.elapse(const Duration(seconds: 5));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));

        // Cut: nothing moves any more; mpv waits for data.
        flowing = false;
        engine.emit(const EngineBuffering(buffering: true));
        async.elapse(const Duration(seconds: 3));
        expect(session.state.recovering, isFalse, reason: 'a short stall is a buffering (B02)');
        // mpv's buffering flag flips (core-idle, paused-for-cache): no proof
        // that anything arrived.
        engine.playing();
        async.elapse(const Duration(seconds: 2));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.buffering, 1));
        engine.emit(const EngineBuffering(buffering: true));
        async.elapse(const Duration(seconds: 3));
        engine.playing();
        expect((session.state.status, session.state.recovery), (PlaybackStatus.buffering, 1));
        expect(refreshes, 0);
        // Twelve seconds without progress: the recovery acts, still the
        // first attempt.
        async.elapse(const Duration(seconds: 5));
        expect(refreshes, 1);
        expect(engine.opens, hasLength(2));
        // The reopened source says it plays at once (mpv: not paused); that
        // is no recovery until it moves.
        expect((session.state.status, session.state.recovery), (PlaybackStatus.buffering, 1));
        flowing = true;
        async.elapse(const Duration(seconds: 2));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
        ticker.cancel();
      });
    });

    test('offline: the attempts count on, the failure is the network, and it plays again by itself', () {
      fakeAsync((async) {
        var online = true;
        start(request(online: () => online), async);
        final attempts = <int>[];
        final subscription = session.states.listen((state) {
          if (state.recovering && (attempts.isEmpty || attempts.last != state.recovery)) attempts.add(state.recovery);
        });
        addTearDown(subscription.cancel);
        // The connection the cut broke stays dead; a new one opened online
        // plays.
        var dead = false;
        engine.onOpen = (_) async {
          dead = !online;
          engine.playing();
        };
        play(() => online && !dead);
        async.elapse(const Duration(seconds: 3));

        online = false;
        dead = true;
        engine.emit(const EngineBuffering(buffering: true));
        async.elapse(const Duration(seconds: 7));
        expect(session.state.recovery, 1, reason: 'within ten seconds of the cut');
        async.elapse(const Duration(seconds: 15));
        expect(session.state.status, PlaybackStatus.buffering);
        expect(session.state.recovery, greaterThan(2), reason: 'each look at the network is another attempt');
        expect(engine.opens, hasLength(1), reason: 'no line or decoder is tried while the network is gone');
        async.elapse(const Duration(seconds: 20));
        expect(session.state.status, PlaybackStatus.error);
        expect(session.state.recovering, isFalse);
        expect(session.state.failure, SourceFailureKind.transient);
        expect(
          session.state.error,
          isA<PlayerException>()
              .having((error) => error.type, 'type', PlayerErrorType.network)
              .having((error) => error.code, 'code', networkLostCode),
        );
        expect(attempts, [for (var attempt = 1; attempt <= attempts.length; attempt++) attempt]);

        // Back: it plays again without the retry button.
        async.elapse(const Duration(seconds: 30));
        expect(session.state.status, PlaybackStatus.error, reason: 'still offline');
        online = true;
        async.elapse(const Duration(seconds: 6));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
        expect(engine.opens, hasLength(2));
        expect(engine.opens.map((media) => media.decoder), everyElement(DecoderMode.hardware));
      });
    });

    test('a refresh that never answers counts as the network gone, within a minute of the cut', () {
      fakeAsync((async) {
        var online = true;
        start(request(online: () => online, hang: true), async);
        var dead = false;
        engine.onOpen = (_) async {
          dead = !online;
          engine.playing();
        };
        play(() => online && !dead);
        async.elapse(const Duration(seconds: 3));
        online = false;
        dead = true;
        engine.emit(const EngineBuffering(buffering: true));
        async.elapse(const Duration(seconds: 7));
        expect(session.state.recovery, 1);
        async.elapse(const Duration(seconds: 50));
        expect(session.state.status, PlaybackStatus.error);
        expect((session.state.error! as PlayerException).code, networkLostCode);
        online = true;
        async.elapse(const Duration(seconds: 10));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
      });
    });

    test('a decoder failure while the network is there is still a decoder failure', () {
      fakeAsync((async) {
        var refreshes = 0;
        start(request(online: () => true, onRefresh: () => refreshes++), async);
        const codec = PlayerException(message: 'decode failed', type: PlayerErrorType.codec, code: 'video_decoder');
        engine
          ..onOpen = ((_) async => engine.emit(const EngineError(codec)))
          ..emit(const EngineError(codec));
        async.flushMicrotasks();
        expect(engine.opens.map((media) => media.decoder), [DecoderMode.hardware, DecoderMode.software]);
        expect(session.state.status, PlaybackStatus.error);
        expect((session.state.error! as PlayerException).type, PlayerErrorType.codec);
        expect(refreshes, 0);
        async.elapse(const Duration(minutes: 1));
        expect(engine.opens, hasLength(2), reason: 'nothing reopens by itself');
      });
    });

    test('B02 unchanged: a pause, a resume that waits and a line switch are no reconnection', () {
      fakeAsync((async) {
        var refreshes = 0;
        var flowing = true;
        start(request(online: () => true, onRefresh: () => refreshes++), async);
        play(() => flowing);
        async.elapse(const Duration(seconds: 3));
        unawaited(session.pause());
        flowing = false;
        engine.emit(const EnginePlaying(playing: false));
        async.elapse(const Duration(seconds: 20));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.paused, 0));

        unawaited(session.resume());
        async.flushMicrotasks();
        engine
          ..emit(const EngineBuffering(buffering: true))
          ..emit(const EnginePlaying(playing: true));
        async.elapse(const Duration(seconds: 8));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.buffering, 0));
        flowing = true;
        engine.emit(const EngineBuffering(buffering: false));
        async.elapse(const Duration(seconds: 3));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));

        flowing = false;
        unawaited(session.selectLine(1));
        async.flushMicrotasks();
        engine.emit(const EngineBuffering(buffering: true));
        async.elapse(const Duration(seconds: 8));
        expect((session.state.status, session.state.recovery), (PlaybackStatus.buffering, 0));
        expect(refreshes, 0);
      });
    });
  });

  group('G02.2 buffering reconciliation', () {
    /// mpv's buffering flag stuck at true while the engine says it plays.
    void stuck() => engine
      ..emit(const EngineBuffering(buffering: true))
      ..emit(const EnginePlaying(playing: true));

    /// mpv's `time-pos` moving on every second.
    Timer move() {
      final ticker = Timer.periodic(const Duration(seconds: 1), (_) => engine.advance());
      addTearDown(ticker.cancel);
      return ticker;
    }

    test('positions advancing during a stuck buffering bring playing back; no reopen after 12 s', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
        stuck();
        expect(session.state.status, PlaybackStatus.buffering);
        final seen = <PlaybackStatus>[];
        final subscription = session.states.listen((state) => seen.add(state.status));
        addTearDown(subscription.cancel);
        move();
        async.elapse(const Duration(seconds: 13));
        expect(session.state.status, PlaybackStatus.playing);
        expect(session.state.recovering, isFalse);
        expect(engine.opens, hasLength(1));
        // One snapshot for the reconciliation, none for the positions.
        expect(seen, [PlaybackStatus.playing]);
      });
    });

    test('positions that stand still keep the buffering deadline', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
        final causes = <(int, String?)>[];
        final subscription = session.states.listen((state) => causes.add((state.recovery, state.recoveryCause)));
        addTearDown(subscription.cancel);
        stuck();
        final ticker = Timer.periodic(const Duration(seconds: 1), (_) => engine.emit(EnginePosition(engine.position)));
        addTearDown(ticker.cancel);
        async.elapse(const Duration(seconds: 11));
        expect((session.state.status, engine.opens.length), (PlaybackStatus.buffering, 1));
        async.elapse(const Duration(seconds: 2));
        expect(engine.opens, hasLength(2));
        expect(causes, contains((1, 'buffering_stall_timeout')));
        // The reopened line plays: the recovery and its cause end.
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
        expect(session.state.recoveryCause, isNull);
      });
    });

    test('presented frames during buffering bring playing back (Windows)', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
        engine.reportsFrames = true;
        stuck();
        for (var frame = 0; frame < 5; frame++) {
          async.elapse(const Duration(milliseconds: 80));
          engine.emit(const EngineFrame());
        }
        expect(session.state.status, PlaybackStatus.buffering, reason: 'five frames are not enough');
        for (var frame = 0; frame < 7; frame++) {
          async.elapse(const Duration(milliseconds: 80));
          engine.emit(const EngineFrame());
        }
        expect(session.state.status, PlaybackStatus.playing);
        final ticker = Timer.periodic(const Duration(seconds: 1), (_) => engine.emit(const EngineFrame()));
        addTearDown(ticker.cancel);
        async.elapse(const Duration(seconds: 13));
        expect((session.state.status, engine.opens.length), (PlaybackStatus.playing, 1));
      });
    });

    test('frames of an audio-only player are no proof', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a]), audioOnly: true), async);
        engine.reportsFrames = true;
        stuck();
        for (var frame = 0; frame < 12; frame++) {
          async.elapse(const Duration(milliseconds: 80));
          engine.emit(const EngineFrame());
        }
        expect(session.state.status, PlaybackStatus.buffering);
      });
    });

    test('a user pause is not undone by positions', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a])), async);
        stuck();
        unawaited(session.pause());
        async.flushMicrotasks();
        engine.calls.clear();
        move();
        async.elapse(const Duration(seconds: 20));
        expect(session.state.status, PlaybackStatus.paused);
        expect(engine.calls.where((call) => call == 'play'), isEmpty);
        expect(engine.opens, hasLength(1));
      });
    });

    test('a seek jump is no progress', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'huya', plan: _plan([_a], onDemand: true)), async);
        stuck();
        engine.advance(Duration.zero);
        async.elapse(const Duration(seconds: 1));
        engine.advance(const Duration(seconds: 60));
        expect(session.state.status, PlaybackStatus.buffering);
        // From the new place, real progress counts.
        async.elapse(const Duration(seconds: 1));
        engine.advance();
        expect(session.state.status, PlaybackStatus.playing);
      });
    });

    test("a stale generation's positions are ignored", () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
        stuck();
        engine.onOpen = (_) => Completer<void>().future;
        unawaited(session.selectLine(1));
        async.flushMicrotasks();
        move();
        async.elapse(const Duration(seconds: 5));
        expect(session.state.status, isNot(PlaybackStatus.playing));
        expect(engine.opens, hasLength(2));
      });
    });

    test('recoveryCause clears once playing again', () {
      fakeAsync((async) {
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b])), async);
        engine
          ..onOpen = ((_) async {})
          ..emit(const EngineError(_network));
        async.flushMicrotasks();
        expect((session.state.recovery, session.state.recoveryCause), (1, 'transport'));
        engine.playing();
        expect((session.state.status, session.state.recovery), (PlaybackStatus.playing, 0));
        expect(session.state.recoveryCause, isNull);
      });
    });
  });

  group('G03.1 timing', () {
    test('timing: one line per open, each mark once', () {
      fakeAsync((async) {
        const second = Duration(seconds: 1);
        final timings = <PlaybackTiming>[];
        engine = FakeEngine();
        final creating = Completer<PlayerEngine>();
        session = PlaybackSession(engine: () => creating.future, opener: MediaOpener());
        final loading = Completer<void>();
        engine.onOpen = (_) => loading.future;

        // The room: T0, then its detail, qualities and URLs a second apart.
        final startup = StartupMarks();
        async.elapse(second);
        startup.markDetail();
        async.elapse(second);
        startup
          ..markQualities()
          ..markQualities();
        async.elapse(second);
        startup.markUrls();
        unawaited(
          session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]), startup: startup, onTiming: timings.add)),
        );
        async.elapse(second);
        creating.complete(engine);
        async
          ..flushMicrotasks()
          ..elapse(second);
        loading.complete();
        async
          ..flushMicrotasks()
          ..elapse(second);
        engine
          ..emit(const EngineVideoSize(1920, 1080))
          ..emit(const EngineVideoSize(1280, 720));
        async.elapse(second);
        expect(timings, isEmpty);
        engine.playing();
        expect(session.state.status, PlaybackStatus.playing);

        final timing = timings.single;
        expect(
          timing.line(room: 'abc123'),
          [
            'playback-timing site=douyu room=abc123 route=direct engine=new result=playing',
            'detail=1000 qualities=1000 urls=1000 engineReady=1000 input=0 load=1000 firstFrame=1000 playing=1000',
            'total=7000',
          ].join(' '),
        );
        for (final name in PlaybackTiming.segmentNames) {
          expect(timing.segment(name), isNotNull, reason: name);
          expect(timing.segment(name)!.isNegative, isFalse, reason: name);
        }

        // Later events and recoveries of the same open report nothing more.
        engine
          ..onOpen = null
          ..emit(const EngineVideoSize(640, 360))
          ..emit(const EngineError(_network));
        async.flushMicrotasks();
        engine.playing();
        async.elapse(const Duration(seconds: 5));
        expect(timings, hasLength(1));
      });
    });

    test('timing: the wall clock set back while a room opens does not bend the line', () {
      // K90: `detail=869 … load=19 firstFrame=475 playing=0 total=13`, the
      // steps adding up to 1.37 s. Only a wall clock going back between the
      // marks and the end gives that; the timing reads a monotonic one.
      fakeAsync((async) {
        final origin = DateTime.utc(2026, 10, 8, 12);
        final monotonic = timingNow;
        timingNow = () => origin.add(async.elapsed);
        addTearDown(() => timingNow = monotonic);
        var setBack = Duration.zero;
        withClock(Clock(() => origin.add(async.elapsed - setBack)), () {
          final timings = <PlaybackTiming>[];
          final startup = StartupMarks();
          async.elapse(const Duration(seconds: 1));
          startup
            ..markDetail()
            ..markQualities()
            ..markUrls();
          start(PlaybackRequest(site: 'kilakila', plan: _plan([_a]), startup: startup, onTiming: timings.add), async);
          async.elapse(const Duration(seconds: 1));
          setBack = const Duration(seconds: 3);
          engine.emit(const EngineVideoSize(1280, 720));
          final timing = timings.single;
          final steps = [for (final step in timing.segments) step ?? Duration.zero].reduce((a, b) => a + b);
          expect(timing.total, steps);
          expect(timing.total, const Duration(seconds: 2));
          expect(timing.segment('detail'), const Duration(seconds: 1));
          expect(timing.segment('firstFrame'), const Duration(seconds: 1));
        });
      });
    });

    test('timing: an open without a room times from the session open', () {
      fakeAsync((async) {
        final timings = <PlaybackTiming>[];
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a]), onTiming: timings.add), async);
        expect(session.state.status, PlaybackStatus.playing);
        // mpv's "playing" right after loading is not the end: the picture is.
        expect(timings, isEmpty);
        async.elapse(const Duration(seconds: 1));
        engine.emit(const EngineVideoSize(1280, 720));
        expect(
          timings.single.line(),
          'playback-timing site=douyu room=- route=direct engine=new result=playing '
          'detail=- qualities=- urls=- engineReady=0 input=0 load=0 firstFrame=1000 playing=0 total=1000',
        );
      });
    });

    test('timing: a source without a picture ends at its first move', () {
      fakeAsync((async) {
        final timings = <PlaybackTiming>[];
        start(PlaybackRequest(site: 'ximalaya', plan: _plan([_a]), onTiming: timings.add), async);
        engine.emit(const EnginePosition(Duration(seconds: 40)));
        async.elapse(const Duration(seconds: 2));
        expect(timings, isEmpty, reason: 'the first position is where it starts');
        engine.emit(const EnginePosition(Duration(seconds: 41)));
        expect(
          timings.single.line(),
          'playback-timing site=ximalaya room=- route=direct engine=new result=playing '
          'detail=- qualities=- urls=- engineReady=0 input=0 load=0 firstFrame=- playing=2000 total=2000',
        );
      });
    });

    test('timing: a superseded open writes nothing', () {
      fakeAsync((async) {
        final timings = <PlaybackTiming>[];
        engine = FakeEngine()..onOpen = (_) => Completer<void>().future;
        session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
        unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]), onTiming: timings.add)));
        async.elapse(const Duration(seconds: 1));
        expect(engine.opens, hasLength(1));

        engine.onOpen = null;
        unawaited(session.open(PlaybackRequest(site: 'huya', plan: _plan([_b]), onTiming: timings.add)));
        async.flushMicrotasks();
        expect(session.state.status, PlaybackStatus.playing);
        engine.emit(const EngineVideoSize(1280, 720));
        expect(timings.map((timing) => timing.site), ['huya']);

        // A stop while opening, and a line switch, drop the open's timing too.
        engine.onOpen = (_) => Completer<void>().future;
        unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a, _b]), onTiming: timings.add)));
        async.flushMicrotasks();
        unawaited(session.selectLine(1));
        async.flushMicrotasks();
        unawaited(session.stop());
        async.elapse(const Duration(seconds: 30));
        expect(timings, hasLength(1));
      });
    });

    test('timing: a reused engine says reused', () {
      fakeAsync((async) {
        final timings = <PlaybackTiming>[];
        start(PlaybackRequest(site: 'douyu', plan: _plan([_a]), onTiming: timings.add), async);
        engine.emit(const EngineVideoSize(1280, 720));
        unawaited(session.stop());
        async.elapse(const Duration(seconds: 10));
        expect(engine.disposed, isFalse);
        unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_b]), onTiming: timings.add)));
        async.flushMicrotasks();
        engine.emit(const EngineVideoSize(1280, 720));
        expect(timings.map((timing) => timing.engineReused), [false, true]);
        expect(timings.last.line(), contains(' engine=reused '));
      });
    });

    test('timing: an error reports its code', () {
      fakeAsync((async) {
        final timings = <PlaybackTiming>[];
        start(PlaybackRequest(site: 'douyu', plan: _plan(const []), onTiming: timings.add), async);
        expect(session.state.status, PlaybackStatus.error);
        expect(
          timings.single.line(),
          'playback-timing site=douyu room=- route=- engine=- result=error:no_source '
          'detail=- qualities=- urls=- engineReady=- input=- load=- firstFrame=- playing=- total=0',
        );

        // A source that never opens: the deadline's code, after the walk.
        engine = FakeEngine()..onOpen = (_) => Completer<void>().future;
        session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
        unawaited(session.open(PlaybackRequest(site: 'douyu', plan: _plan([_a]), onTiming: timings.add)));
        async.elapse(const Duration(minutes: 2));
        expect(session.state.status, PlaybackStatus.error);
        expect(timings, hasLength(2));
        expect(timings.last.error, 'source_open_timeout');
        expect(timings.last.line(), contains('route=direct engine=new result=error:source_open_timeout'));
      });
    });
  });
}

/// A variant selector that selects nothing; the engine is fake and never
/// reads the master (G01.4).
final class _Selector implements HlsVariantSelector {
  @override
  HlsMasterSelection selectIn(String text, {required Uri source}) => throw const FormatException('unused');
}
