import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

import 'support/synthetic_flv.dart';

const _quality = Quality(id: '0', label: '原画', rank: 10);

/// A Douyu-like line: issued now, `expire=300`, refreshed 45 s early.
StreamLine _line(int serial, {Duration refreshIn = const Duration(seconds: 255)}) {
  final issued = clock.now();
  return StreamLine(
    url: Uri.parse('https://cdn.test/live/$serial.flv?expire=300'),
    format: StreamFormat.flv,
    lineId: 'hw',
    requested: _quality,
    lease: Lease(
      refreshAt: issued.add(refreshIn),
      expiresAt: issued.add(refreshIn + const Duration(seconds: 45)),
      cutsConnection: true,
    ),
  );
}

final class _Run {
  new(FakeCdn cdn, {LineRenewer? renew, Duration refreshIn = const Duration(seconds: 255)}) {
    splicer = FlvSplicer(
      line: _line(0, refreshIn: refreshIn),
      open: cdn.open,
      renew: renew ?? (current) async => _line(++renewals, refreshIn: refreshIn),
      emit: output.add,
      onEvent: events.add,
    );
    done = splicer.run().then((_) => finished = true);
  }

  late final FlvSplicer splicer;
  late final Future<void> done;
  final output = OutputCheck();
  final events = <SpliceEvent>[];
  int renewals = 0;
  bool finished = false;

  List<SpliceSwitched> get switches => events.whereType<SpliceSwitched>().toList();
}

void main() {
  test('splices each renewal at the first undelivered keyframe: one timeline, no gap, no repeat', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300));
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 700));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.switches, hasLength(2));
      expect(run.switches.every((event) => !event.shifted && !event.oldEnded), isTrue);
      expect(cdn.connections, hasLength(3));
      expect(cdn.connections.take(2).every((connection) => connection.cancelled), isTrue);
      final out = run.output;
      expect(out.videoMonotonic, isTrue);
      expect(out.audioMonotonic, isTrue);
      expect(out.repeatedVideo, 0);
      expect(out.maxVideoGap, 40, reason: 'one frame interval across both switches');
      expect(out.maxAudioGap, lessThanOrEqualTo(46));
      expect(out.video.last - out.video.first, greaterThan(699000 - 1000));
      expect(out.scripts, 1, reason: 'script tags are not repeated after a switch');
      expect(out.videoConfigs, 1, reason: 'an unchanged configuration is not re-sent');
      expect(out.audioConfigs, 1);
      expect(run.splicer.line.url.path, '/live/2.flv');
    });
  });

  test('holds the old stream at its keyframe when the new connection lags behind the live edge', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300))..lagMs = 250;
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 290));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      final switched = run.switches.single;
      expect(switched.oldEnded, isFalse);
      expect(switched.switchAt - 100000, lessThan(257000), reason: 'the first keyframe after the refresh');
      expect(run.output.maxVideoGap, 40);
      expect(run.output.repeatedVideo, 0);
    });
  });

  test('re-sends a codec configuration that changed on the new connection', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300));
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 200));
      cdn.flv = const SyntheticFlv(videoConfigPayload: [7, 7, 7]);
      async.elapse(const Duration(seconds: 100));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.switches, hasLength(1));
      expect(run.output.videoConfigs, 2);
      expect(run.output.audioConfigs, 1);
      expect(run.output.maxVideoGap, 40);
    });
  });

  test('shifts a new connection on another timeline to continue the delivered one', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300))
        ..shiftFrom = 1
        ..timelineShift = 5000000;
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 290));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.switches.single.shifted, isTrue);
      final out = run.output;
      expect(out.videoMonotonic, isTrue);
      expect(out.audioMonotonic, isTrue);
      expect(out.maxVideoGap, lessThanOrEqualTo(80));
      expect(out.video.last, lessThan(200000 + 300000), reason: 'stays on the delivered timeline');
    });
  });

  test('renews at once when the old connection ends early, skipping at most one GOP', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 30));
      final run = _Run(cdn, refreshIn: const Duration(hours: 1));
      async.elapse(const Duration(seconds: 45));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      final switched = run.switches.single;
      expect(switched.oldEnded, isTrue);
      expect(run.events.whereType<SpliceRenewing>().single.oldEnded, isTrue);
      expect(run.output.videoMonotonic, isTrue);
      expect(run.output.repeatedVideo, 0);
      expect(run.output.maxVideoGap, lessThanOrEqualTo(1000 + 40));
    });
  });

  test('keeps the old connection when a renewal fails, retries after 10 s, and succeeds before the cut', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300))..failing.add(1);
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 290));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.events.whereType<SpliceRenewFailed>(), hasLength(1));
      expect(run.switches, hasLength(1));
      expect(cdn.connections, hasLength(3));
      expect(run.output.maxVideoGap, 40);
    });
  });

  test('ends the output when no successor can be opened after the old connection ends', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300));
      final run = _Run(cdn, renew: (current) async => throw const NetworkFailure('douyu', 'offline'));
      async.elapse(const Duration(seconds: 320));

      expect(run.finished, isTrue);
      expect(run.switches, isEmpty);
      expect(run.events.whereType<SpliceRenewFailed>().length, greaterThanOrEqualTo(4));
      expect(run.events.last, isA<SpliceEnded>());
      expect(run.output.maxVideoGap, 40);
      expect(run.output.video.last - run.output.video.first, closeTo(300000, 1000));
    });
  });

  test('cancel drops every connection and completes run', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300));
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 5));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();
      expect(run.finished, isTrue);
      expect(cdn.connections.single.cancelled, isTrue);
    });
  });
}
