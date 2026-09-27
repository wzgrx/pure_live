import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

import 'support/session_harness.dart';

const _forbidden = 'Failed to open https://cdn.test/live.flv.';

void main() {
  group('lifecycle (§1)', () {
    test('creates the engine on the first open and publishes resolving, connecting, playing and a commit', () {
      fakeAsync((async) {
        final h = Harness(async);
        expect(h.engines, isEmpty, reason: 'SES-1: nothing native before a room opens');
        expect(h.state.phase, PlaybackPhase.idle);
        unawaited(h.session.open(h.request()));
        expect(h.state.phase, PlaybackPhase.resolving);
        h.settle();
        expect(h.engines, hasLength(1));
        expect(h.state.phase, PlaybackPhase.connecting, reason: 'EVT-13: playing=true right after open means trying');
        expect(h.state.showsBuffering, isTrue);
        h.engine.startStreaming();
        h.settle();
        expect(h.state.phase, PlaybackPhase.playing);
        expect(h.state.commit?.line.lineId, 'hw');
        expect(h.state.commit?.quality, original);
        expect(h.state.hasPicture, isTrue);
        expect(h.opened, ['hw/1']);
        expect(h.state.qualities, [original, high]);
      });
    });

    test('close during an open that has not returned: nothing plays and no commit (SES-2, SES-6)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.holdNextOpen();
        unawaited(h.session.open(h.request(room: 'douyu:2')));
        h.settle();
        unawaited(h.session.close());
        expect(h.state.phase, PlaybackPhase.idle);
        expect(h.state.wantsPlay, isFalse);
        h.engine.releaseOpen();
        h.settle();
        expect(h.engine.commands.last, 'stop');
        expect(h.state.commit, isNull);

        final opens = h.engine.opened.length;
        unawaited(h.session.open(h.request(room: 'douyu:3')));
        unawaited(h.session.close());
        h.settle(const Duration(seconds: 1));
        expect(h.engine.opened, hasLength(opens), reason: 'a queued open after close never runs');
      });
    });

    test('pause during an open forgets the half-opened source; play reopens it (SES-5, REG-PLAY-032)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.holdNextOpen();
        unawaited(h.session.selectLine('hs'));
        h.settle();
        unawaited(h.session.pause());
        h.engine.releaseOpen();
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
        expect(h.engine.commands, contains('stop'));
        unawaited(h.session.play());
        h.settle();
        expect(h.opened, ['hw/1', 'hs/1', 'hs/1']);
        h.engine.startStreaming();
        h.settle();
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('pause while the open is still resolving; play starts it again (SES-5)', () {
      fakeAsync((async) {
        final h = Harness(async);
        final gate = Completer<StreamSet>();
        var resolves = 0;
        final request = PlaybackRequest(
          site: 'douyu',
          roomKey: 'douyu:1',
          resolve: (quality) {
            resolves++;
            return resolves == 1 ? gate.future : h.resolve(quality);
          },
        );
        unawaited(h.session.open(request));
        h.settle();
        unawaited(h.session.pause());
        gate.complete(h.resolve(null));
        h.settle();
        expect(h.engines.isEmpty || h.engine.opened.isEmpty, isTrue, reason: 'the paused open went no further');
        unawaited(h.session.play());
        h.settle();
        expect(h.engine.opened, hasLength(1));
        h.engine.startStreaming();
        h.settle();
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('soft stop keeps the engine for 45 s, then releases it; a new room within 45 s reuses it (SES-7, SES-8)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        final revision = h.state.engineRevision;
        unawaited(h.session.close());
        h.settle(const Duration(seconds: 30));
        expect(h.engine.commands.last, 'stop');
        expect(h.engine.disposed, isFalse);
        h.openAndPlay(room: 'douyu:2');
        expect(h.engines, hasLength(1), reason: 'reused within the idle window');
        unawaited(h.session.close());
        h.settle(const Duration(seconds: 44));
        expect(h.engine.disposed, isFalse);
        h.settle(const Duration(seconds: 2));
        expect(h.engine.disposed, isTrue);
        expect(h.state.engineRevision, isNot(revision));
        expect(h.session.engine, isNull);
      });
    });

    test('dispose releases the engine at once', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        unawaited(h.session.dispose());
        h.settle();
        expect(h.engine.disposed, isTrue);
        expect(() => h.session.open(h.request()), throwsStateError);
      });
    });

    test('replays and catch-up end on completed instead of recovering (SES-11)', () {
      fakeAsync((async) {
        final h = Harness(async, continuousLive: false)..openAndPlay();
        h.engine.endOfStream();
        h.settle(const Duration(seconds: 5));
        expect(h.state.phase, PlaybackPhase.ended);
        expect(h.opened, ['hw/1']);
      });
    });
  });

  group('intent and suspension (§2)', () {
    test('engine pauses while buffering show as stalled; only a user pause shows paused (INT-1, EVT-2)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.stallBegin();
        h.settle();
        expect(h.state.phase, PlaybackPhase.stalled);
        expect(h.state.showsPaused, isFalse);
        expect(h.state.showsBuffering, isTrue);
        h.engine.stallEnd();
        h.settle();
        unawaited(h.session.pause());
        expect(h.state.phase, PlaybackPhase.paused, reason: 'the intent changes before the engine is told');
        h.settle();
        expect(h.engine.commands.last, 'pause');
        expect(h.state.showsPaused, isTrue);
        h.settle(const Duration(minutes: 1));
        expect(h.opened, ['hw/1'], reason: 'no watchdog runs while the user paused');
      });
    });

    test('suspension tokens: stale after a user command, one reason keeps it paused (INT-2)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        final background = h.session.suspend(SuspendReason.background);
        final focus = h.session.suspend(SuspendReason.audioFocus);
        h.settle();
        expect(h.state.phase, PlaybackPhase.suspended);
        expect(h.engine.commands.last, 'pause');
        expect(h.session.resume(focus), isTrue);
        h.settle();
        expect(h.engine.commands.last, 'pause', reason: 'still in the background');
        expect(h.session.resume(background), isTrue);
        h.settle();
        expect(h.engine.commands.last, 'play');
        expect(h.state.phase, PlaybackPhase.playing);

        final stale = h.session.suspend(SuspendReason.background);
        unawaited(h.session.pause());
        unawaited(h.session.play());
        h.settle();
        expect(h.session.resume(stale), isFalse, reason: 'the user acted during the suspension');
        final otherRoom = h.session.suspend(SuspendReason.background);
        h.openAndPlay(room: 'douyu:2');
        expect(h.session.resume(otherRoom), isFalse);
      });
    });

    test('no watchdog fires while suspended', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.session.suspend(SuspendReason.background);
        h.engine.stallBegin();
        h.settle(const Duration(minutes: 2));
        expect(h.opened, ['hw/1']);
      });
    });
  });

  group('monitoring (§5)', () {
    test('a live stream that completes is recovered, not taken for a pause (EVT-1, REG-PLAY-001)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.endOfStream();
        h.settle(const Duration(seconds: 1));
        expect(h.opened, ['hw/1', 'hw/2']);
        expect(h.engine.commands.where((command) => command == 'play'), isEmpty);
        h.engine.startStreaming();
        h.settle();
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('buffering gets one 12 s deadline even while the engine says playing (EVT-3, REG-PLAY-003)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.stallBegin();
        h.settle(const Duration(seconds: 6));
        h.engine.resize(1920, 1080);
        h.settle(const Duration(milliseconds: 5900));
        expect(h.opened, ['hw/1']);
        h.settle(const Duration(milliseconds: 200));
        expect(h.opened, ['hw/1', 'hw/2']);
      });
    });

    test('buffering that ends in time overturns the stall (MON-1)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.stallBegin();
        h.settle(const Duration(seconds: 11));
        h.engine.stallEnd();
        h.settle(const Duration(seconds: 30));
        expect(h.opened, ['hw/1']);
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('an unexpected pause is resumed with play() after 350 ms', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        unawaited(h.engine.pause());
        h.settle(const Duration(milliseconds: 300));
        expect(h.engine.commands.last, 'pause');
        h.settle(const Duration(milliseconds: 100));
        expect(h.engine.commands.last, 'play');
        h.settle(const Duration(seconds: 20));
        expect(h.opened, ['hw/1']);
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('an unexpected pause that play() does not fix escalates after 5 s to a rebuild', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.respondToPlay = false;
        unawaited(h.engine.pause());
        h.settle(const Duration(seconds: 5));
        expect(h.opened, ['hw/1']);
        h.settle(const Duration(milliseconds: 500));
        expect(h.opened, ['hw/1', 'hw/1'], reason: 'stall class: same-engine rebuild');
      });
    });

    test('a frozen picture switches to the spare line; hidden pictures are not judged (MON-3, EVT-11)', () {
      fakeAsync((async) {
        final h = Harness(async, capabilities: const EngineCapabilities(frameProgress: true))..openAndPlay();
        for (var i = 0; i < 20; i++) {
          h.engine.frame();
          h.settle(const Duration(milliseconds: 500));
        }
        h.session.setVisible(visible: false);
        h.settle(const Duration(seconds: 30));
        expect(h.opened, ['hw/1']);
        h.session.setVisible(visible: true);
        h.settle(const Duration(milliseconds: 9900));
        expect(h.opened, ['hw/1']);
        h.settle(const Duration(milliseconds: 200));
        expect(h.opened, ['hw/1', 'hs/1']);
      });
    });

    test('an error before open returns is held, then handled for the same generation (EVT-5, EVT-17)', () {
      fakeAsync((async) {
        final h = Harness(async, openLatency: const Duration(milliseconds: 50))..openAndPlay();
        h.engine.failNextOpen(_forbidden);
        unawaited(h.session.open(h.request(room: 'douyu:2')));
        h.settle(const Duration(milliseconds: 30));
        expect(h.engine.opened, hasLength(2));
        h.settle(const Duration(milliseconds: 100));
        expect(h.opened.last, 'hw/3', reason: 'refreshed after the held 403');
      });
    });

    test('a recoverable decoder diagnostic is dropped when frames follow within 1.2 s (EVT-7)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.diagnostic('Error while decoding frame!', prefix: 'ffmpeg/video');
        h.settle(const Duration(milliseconds: 500));
        h.engine.resize(1280, 720);
        h.settle(const Duration(seconds: 2));
        expect(h.opened, ['hw/1']);
      });
    });

    test('a persistent decoder failure retries with software decoding once per URL (REC-1 step 4, EVT-6)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.stallBegin();
        h.engine.diagnostic('Error while decoding frame!', prefix: 'ffmpeg/video');
        h.settle(const Duration(milliseconds: 1300));
        expect(h.opened, ['hw/1', 'hw/1']);
        expect(h.engine.opened.last.softwareDecoding, isTrue);
        h.engine.diagnostic('Error while decoding frame!', prefix: 'ffmpeg/video');
        h.settle(const Duration(milliseconds: 1300));
        expect(h.state.phase, PlaybackPhase.error, reason: 'the same text on the new generation is not deduplicated');
        expect(h.state.failure?.kind, FailureKind.videoDecode);
      });
    });
  });

  group('recovery (§6)', () {
    test('a dead source walks refresh, next line, backoff 750 ms and 2 s, then gives up (REC-1)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.failEveryOpen = _forbidden;
        h.engine.endOfStream();
        h.settle(const Duration(seconds: 1));
        expect(h.opened.take(4), ['hw/1', 'hw/2', 'hs/3', 'hs/4']);
        expect(h.state.phase, PlaybackPhase.recovering);
        expect(h.state.failure, isNull, reason: 'REC-5: no error while recovering');
        h.settle(const Duration(seconds: 5));
        expect(h.opened, ['hw/1', 'hw/2', 'hs/3', 'hs/4', 'hw/5', 'hw/6', 'hs/7']);
        expect(h.state.phase, PlaybackPhase.error);
        expect(h.state.failure?.kind, FailureKind.source);
        expect(h.state.wantsPlay, isFalse);
        expect(h.engine.commands.last, 'stop');
      });
    });

    test('a user command abandons the recovery in progress (REC-4)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.failEveryOpen = _forbidden;
        h.engine.endOfStream();
        h.settle(const Duration(milliseconds: 100));
        final opens = h.engine.opened.length;
        unawaited(h.session.pause());
        h.settle(const Duration(seconds: 10));
        expect(h.engine.opened, hasLength(opens));
        expect(h.state.phase, PlaybackPhase.paused);
        expect(h.state.failure, isNull);
      });
    });

    test('keeps the quality and line through refreshes; a same-URL refresh still reopens (REC-3, SRC-8)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        unawaited(h.session.selectQuality(high));
        h.settle();
        unawaited(h.session.selectLine('hs'));
        h.settle();
        h.engine.startStreaming();
        h
          ..settle()
          ..sameUrls = true;
        h.engine.endOfStream();
        h.settle();
        h.engine.startStreaming();
        h.settle(const Duration(seconds: 40));
        h.engine.endOfStream();
        h.settle();
        expect(h.opened.skip(2), ['hs/2', 'hs/0', 'hs/0']);
        expect(h.state.quality, high);
        expect(h.state.line?.requested, high);
      });
    });

    test('a lease that cuts every 300 s recovers for an hour (REC-2)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        for (var i = 0; i < 12; i++) {
          h.settle(const Duration(seconds: 300));
          h.engine.endOfStream();
          h.settle();
          h.engine.startStreaming();
          h.settle();
        }
        expect(h.state.phase, PlaybackPhase.playing);
        expect(h.engine.opened, hasLength(13));
      });
    });

    test('at most two rounds start in three minutes (REC-2)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        for (var i = 0; i < 2; i++) {
          h.settle(const Duration(seconds: 31));
          h.engine.endOfStream();
          h.settle();
          h.engine.startStreaming();
        }
        h.settle(const Duration(seconds: 31));
        expect(h.state.phase, PlaybackPhase.playing);
        h.engine.endOfStream();
        h.settle();
        expect(h.state.phase, PlaybackPhase.error);
        expect(h.state.failure?.kind, FailureKind.exhausted);
      });
    });

    test('manual retry clears counts and the round window (REC-6)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        h.engine.failEveryOpen = _forbidden;
        h.engine.endOfStream();
        h.settle(const Duration(seconds: 10));
        expect(h.state.phase, PlaybackPhase.error);
        h.engine.failEveryOpen = null;
        unawaited(h.session.retry());
        h.settle();
        h.engine.startStreaming();
        h.settle();
        expect(h.state.phase, PlaybackPhase.playing);
        expect(h.session.ledger.roundStarts, isEmpty);
      });
    });

    test('an offline room is not retried; a transient resolve failure is (REC-1)', () {
      fakeAsync((async) {
        final offline = Harness(async)..failures.add(const StreamUnavailable('douyu', 'offline'));
        unawaited(offline.session.open(offline.request()));
        offline.settle();
        expect(offline.state.phase, PlaybackPhase.error);
        expect(offline.state.failure?.kind, FailureKind.unavailable);
        expect(offline.engines, isEmpty);

        final flaky = Harness(async)..failures.add(const NetworkFailure('douyu', 'reset'));
        unawaited(flaky.session.open(flaky.request()));
        flaky.settle();
        expect(flaky.opened, ['hw/2']);
      });
    });
  });

  group('leases (SRC-6)', () {
    test('a lease that does not cut only prefetches; the next refresh uses it', () {
      fakeAsync((async) {
        final h = Harness(async, lease: LeaseKind.prefetch)..openAndPlay();
        expect(h.resolves, 1);
        h.settle(const Duration(seconds: 271));
        expect(h.resolves, 2);
        expect(h.opened, ['hw/1'], reason: 'the established connection is left alone');
        h.engine.endOfStream();
        h.settle();
        expect(h.opened, ['hw/1', 'hw/2']);
        expect(h.resolves, 2, reason: 'the unexpired prefetch replaced a resolve');
      });
    });
  });

  group('audio only and geometry (§7, §8)', () {
    test('switches in place; a stuck switch rolls back after 5 s with a notice (AUD-1, AUD-4)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay();
        unawaited(h.session.setAudioOnly(enabled: true));
        h.settle();
        expect(h.engine.audioOnly, isTrue);
        expect(h.state.audioOnly, isTrue);
        expect(h.opened, ['hw/1'], reason: 'no reopen');
        unawaited(h.session.setAudioOnly(enabled: false));
        h.settle();
        expect(h.state.audioOnly, isFalse);

        h.engine.hangAudioSwitch = true;
        unawaited(h.session.setAudioOnly(enabled: true));
        h.settle();
        expect(h.state.audioOnly, isTrue, reason: 'AUD-2: the audio presentation shows first');
        h.settle(const Duration(seconds: 5));
        expect(h.state.audioOnly, isFalse);
        expect(h.state.notice, 'audio_only_failed');
      });
    });

    test('decides orientation per source generation from decoded sizes (GEO-1, GEO-3)', () {
      fakeAsync((async) {
        final h = Harness(async)..openAndPlay(width: 1080, height: 1920);
        expect(h.state.geometry.orientation, VideoOrientation.unknown);
        h.settle(const Duration(milliseconds: 700));
        expect(h.state.geometry.orientation, VideoOrientation.portrait);
        unawaited(h.session.selectLine('hs'));
        h.settle();
        expect(h.state.geometry, VideoGeometry.unknown);
      });
    });
  });

  test('GeometryTracker: fixed windows, 3 samples or 500 ms, hysteresis (GEO-2, GEO-3)', () {
    fakeAsync((async) {
      final commits = <VideoOrientation>[];
      final tracker = GeometryTracker((geometry) => commits.add(geometry.orientation));
      for (var i = 0; i < 10; i++) {
        tracker.add(1920, 1080);
        async.elapse(const Duration(milliseconds: 50));
      }
      expect(commits, [VideoOrientation.landscape], reason: 'a steady stream of events does not starve the decision');
      tracker.add(1000, 1000);
      async.elapse(const Duration(seconds: 1));
      expect(commits.last, VideoOrientation.square);
      expect(GeometryTracker.classify(0.95, VideoOrientation.portrait), VideoOrientation.portrait);
      expect(GeometryTracker.classify(0.95, VideoOrientation.unknown), VideoOrientation.square);
      expect(GeometryTracker.classify(1.05, VideoOrientation.landscape), VideoOrientation.landscape);
      expect(GeometryTracker.classify(0.9, VideoOrientation.unknown), VideoOrientation.portrait);
      tracker.dispose();
    });
  });

  test('nextRecoveryStep follows the chain order', () {
    final ledger = RecoveryLedger();
    RecoveryStep next(FailureKind kind, {bool spare = true, bool software = false}) => nextRecoveryStep(
      PlaybackFailure(kind, 'x'),
      ledger,
      canRefresh: true,
      hasSpareLine: spare,
      softwareTried: software,
      continuousLive: true,
      backoff: const [Duration(milliseconds: 750), Duration(seconds: 2)],
    );
    expect(next(FailureKind.network), isA<RefreshStep>().having((step) => step.usePrefetch, 'prefetch', isTrue));
    ledger.refreshes = 1;
    expect(next(FailureKind.network), isA<RefreshStep>().having((step) => step.nextLine, 'next line', isTrue));
    ledger.refreshes = 2;
    expect(next(FailureKind.network), isA<SwitchLineStep>());
    expect(next(FailureKind.network, spare: false), isA<BackoffStep>());
    expect(next(FailureKind.frameStall), isA<SwitchLineStep>());
    expect(next(FailureKind.frameStall, spare: false), isA<RebuildStep>());
    expect(next(FailureKind.videoDecode), isA<SoftwareDecodeStep>());
    expect(next(FailureKind.videoDecode, software: true), isA<GiveUpStep>());
    expect(next(FailureKind.audioDecode), isA<GiveUpStep>());
    expect(next(FailureKind.unavailable), isA<GiveUpStep>());
    ledger
      ..startBackoff()
      ..startBackoff();
    expect(next(FailureKind.liveCompleted, spare: false), isA<RefreshStep>());
    ledger
      ..refreshes = 2
      ..rebuilds = 1;
    expect(next(FailureKind.liveCompleted, spare: false), isA<GiveUpStep>());
  });
}
