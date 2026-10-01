import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
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
}
