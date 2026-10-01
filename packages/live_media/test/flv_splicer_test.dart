import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

import 'support/synthetic_flv.dart';

/// A Douyu-like line: issued now, `expire=300`, refreshed 45 s early.
LivePlayLine _line(int serial, {Duration refreshIn = const Duration(seconds: 255)}) {
  final issued = clock.now();
  return LivePlayLine(
    'https://cdn.test/live/$serial.flv?expire=300',
    format: StreamFormat.flv,
    lineId: 'hw',
    lease: PlayLease(
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

// Ported from archive v4 (packages/live_media/test/flv_splicer_test.dart);
// 3.x's flv_splice_relay_test covered the same main path.
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
      final out = run.output;
      expect(out.videoMonotonic, isTrue);
      expect(out.audioMonotonic, isTrue);
      expect(out.repeatedVideo, 0);
      expect(out.maxVideoGap, 40, reason: 'one frame interval across both switches');
      expect(out.scripts, 1, reason: 'script tags are not repeated after a switch');
      expect(out.videoConfigs, 1, reason: 'an unchanged configuration is not re-sent');
      expect(run.splicer.line.url, contains('/live/2.flv'));
    });
  });

  test('renews at once when the old connection ends early, skipping at most one GOP', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 30));
      final run = _Run(cdn, refreshIn: const Duration(hours: 1));
      async.elapse(const Duration(seconds: 45));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.switches.single.oldEnded, isTrue);
      expect(run.output.videoMonotonic, isTrue);
      expect(run.output.repeatedVideo, 0);
      expect(run.output.maxVideoGap, lessThanOrEqualTo(1000 + 40));
    });
  });

  test('keeps the old connection when a renewal fails and retries before the cut', () {
    fakeAsync((async) {
      final cdn = FakeCdn(flv: const SyntheticFlv(), cutAfter: const Duration(seconds: 300))..failing.add(1);
      final run = _Run(cdn);
      async.elapse(const Duration(seconds: 290));
      unawaited(run.splicer.cancel());
      async.flushMicrotasks();

      expect(run.events.whereType<SpliceRenewFailed>(), hasLength(1));
      expect(run.switches, hasLength(1));
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
      expect(run.events.last, isA<SpliceEnded>());
    });
  });
}
