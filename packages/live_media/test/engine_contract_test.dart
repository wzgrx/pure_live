import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:test/test.dart';

/// Recorded real-libmpv scenarios (fixtures/player, spec §4).
EngineTrace _trace(String name) => EngineTrace.load('../../fixtures/player/$name');

/// Only the state events that the session reacts to, without position noise.
List<String> _states(Iterable<EngineEvent> events) => [
  for (final event in events)
    if (event is! EnginePosition && event is! EngineDuration) '$event',
];

List<String> _after(EngineTrace trace, String command) {
  final index = trace.steps.indexWhere((step) => step.command == command);
  final next = trace.steps.indexWhere((step) => step.command != null, index + 1);
  return _states([for (final step in trace.steps.sublist(index + 1, next < 0 ? null : next)) ?step.event]);
}

void main() {
  group('recorded traces (EVT-13 to EVT-19)', () {
    test('open resets state, then reports playing and buffering before any data (EVT-13)', () {
      for (final name in ['eof', 'stall', 'reset', 'http403', 'garbage', 'pause_resume', 'stop_while_buffering']) {
        final events = _after(_trace(name), 'open');
        expect(events.take(6), [
          'playing=false',
          'completed=false',
          'buffering=false',
          'tracks=v0/a0',
          'size=nullxnull',
          'playing=true',
        ], reason: name);
        expect(events[6], 'buffering=true', reason: name);
      }
    });

    test('end of stream: buffering, playing=false, completed, buffering off, tracks reset (EVT-1, EVT-14)', () {
      for (final name in ['eof', 'reset', 'pause_resume']) {
        final events = _states(_trace(name).events);
        final completed = events.lastIndexOf('completed=true');
        expect(events.sublist(completed - 2, completed + 3), [
          'buffering=true',
          'playing=false',
          'completed=true',
          'buffering=false',
          'tracks=v0/a0',
        ], reason: name);
        expect(events.where((event) => event.startsWith('error')), isEmpty, reason: '$name: EVT-16, no error');
      }
    });

    test('a stalled connection ends as completed without an error (EVT-15)', () {
      final events = _states(_trace('stall').events);
      expect(events.skipWhile((event) => event != 'tracks=v1/a1').skip(1), [
        'buffering=true',
        'buffering=false',
        'playing=false',
        'completed=true',
        'tracks=v0/a0',
        'buffering=true',
      ]);
    });

    test('a failed open reports only an error; playing and buffering stay true (EVT-17)', () {
      expect(_after(_trace('http403'), 'open').last, startsWith('error=[cplayer] Failed to open http://'));
      expect(_after(_trace('garbage'), 'open').last, 'error=[cplayer] Failed to recognize file format.');
      final reopen = _trace('reopen_after_403');
      expect(reopen.commands, ['open', 'open', 'dispose']);
    });

    test('pause and play only toggle playing; stop reports no completed (EVT-18)', () {
      final trace = _trace('pause_resume');
      expect(_after(trace, 'pause'), ['playing=false']);
      expect(_after(trace, 'play').first, 'playing=true');
      expect(_after(_trace('stop_while_buffering'), 'stop'), ['playing=false', 'buffering=false', 'tracks=v0/a0']);
    });

    test('duration grows on a live stream without metadata (EVT-19)', () {
      final durations = _trace('eof').events.whereType<EngineDuration>().map((event) => event.duration).toList();
      expect(durations.where((duration) => duration > Duration.zero).length, greaterThan(5));
    });
  });

  group('FakeEngine', () {
    test('replays a trace at its recorded offsets as the commands arrive', () {
      fakeAsync((async) {
        final trace = _trace('pause_resume');
        final engine = FakeEngine.replay(trace);
        final seen = <EngineEvent>[];
        engine.events.listen(seen.add);
        unawaited(engine.open(EngineMedia(uri: Uri.parse('http://127.0.0.1/live.flv'))));
        async.elapse(const Duration(seconds: 3));
        unawaited(engine.pause());
        async.elapse(const Duration(seconds: 3));
        expect(seen.whereType<EnginePlaying>().last.playing, isFalse);
        unawaited(engine.play());
        async.elapse(const Duration(seconds: 20));
        final expected = _states(trace.events);
        expect(_states(seen), expected);
      });
    });

    test('scripted reactions follow the recorded orders', () {
      fakeAsync((async) {
        final engine = FakeEngine();
        final seen = <EngineEvent>[];
        engine.events.listen(seen.add);
        unawaited(engine.open(EngineMedia(uri: Uri.parse('http://127.0.0.1/live.flv'))));
        async.elapse(const Duration(milliseconds: 20));
        expect(_states(seen), _after(_trace('eof'), 'open').take(7).toList());

        seen.clear();
        engine
          ..startStreaming(width: 320, height: 180)
          ..endOfStream();
        async.flushMicrotasks();
        expect(_states(seen), [
          'buffering=false',
          'tracks=v1/a1',
          'size=320x180',
          ..._states(_trace('eof').events).skip(9),
        ]);

        seen.clear();
        unawaited(engine.open(EngineMedia(uri: Uri.parse('http://127.0.0.1/1.flv'))));
        async.elapse(const Duration(milliseconds: 20));
        engine
          ..startStreaming()
          ..stallBegin()
          ..networkTimeout();
        async.flushMicrotasks();
        expect(_states(seen).skip(_states(seen).indexOf('tracks=v1/a1') + 2), _states(_trace('stall').events).skip(9));

        seen.clear();
        unawaited(engine.pause());
        unawaited(engine.stop());
        async.flushMicrotasks();
        expect(_states(seen), ['buffering=false'], reason: 'not playing after the timeout; stop ends the buffering');
      });
    });

    test('a failing open emits only the error after the start events (EVT-17)', () {
      fakeAsync((async) {
        final engine = FakeEngine()..failNextOpen();
        final seen = <EngineEvent>[];
        engine.events.listen(seen.add);
        unawaited(engine.open(EngineMedia(uri: Uri.parse('http://127.0.0.1/live.flv'))));
        async.elapse(const Duration(milliseconds: 20));
        expect(_states(seen).skip(5), [
          'playing=true',
          'buffering=true',
          'error=[cplayer] Failed to open http://127.0.0.1/live.flv.',
        ]);
      });
    });
  });

  group('diagnostics (EVT-7, EVT-12)', () {
    test('only error lines from player, decoder, stream and tcp sources enter classification', () {
      for (final prefix in ['file', 'vd', 'ad', 'ffmpeg/video', 'ffmpeg/audio', 'cplayer', 'stream']) {
        expect(isActionableDiagnostic(prefix, 'x'), isTrue, reason: prefix);
      }
      expect(isActionableDiagnostic('ffmpeg', 'tcp: Connection refused'), isTrue);
      expect(isActionableDiagnostic('ffmpeg', 'http: HTTP error 403'), isFalse);
      expect(isActionableDiagnostic('ao/audiotrack', 'x'), isFalse);
      expect(isActionableDiagnostic('vo/gpu', 'x'), isFalse);
    });

    test('classifies terminal and recoverable diagnostics', () {
      Diagnosis classify(String text, [String? prefix]) => classifyDiagnostic(text, prefix: prefix);
      expect(classify('Failed to open http://127.0.0.1:46387/live/0.flv.', 'cplayer').kind, DiagnosticKind.sourceOpen);
      expect(classify('Failed to recognize file format.', 'cplayer').kind, DiagnosticKind.sourceOpen);
      expect(classify('tcp: Connection refused', 'ffmpeg').kind, DiagnosticKind.transport);
      expect(classify('HTTP error 503 Service Unavailable', 'ffmpeg').kind, DiagnosticKind.transport);
      expect(classify('Server returned 403 Forbidden (access denied)', 'stream').kind, DiagnosticKind.sourceOpen);
      expect(classify('Player has been disposed').kind, DiagnosticKind.lifecycle);
      expect(classify('Failed to create texture', 'vo').kind, DiagnosticKind.videoOutput);
      final decode = classify('Error while decoding frame!', 'ffmpeg/video');
      expect(decode.kind, DiagnosticKind.decoderRuntime);
      expect(decode.component, DiagnosticComponent.video);
      expect(decode.code, 'video_decoderRuntime');
      expect(classify('Could not open codec.', 'ad').component, DiagnosticComponent.audio);
      expect(classify('Could not open codec.', 'ad').kind.terminal, isTrue);
      expect(classify('demuxer read failed', 'stream').kind, DiagnosticKind.sourceRuntime);
      expect(classify('something odd').kind, DiagnosticKind.other);
      expect(DiagnosticKind.decoderRuntime.terminal, isFalse);
      expect(DiagnosticKind.transport.terminal, isTrue);
    });
  });
}
