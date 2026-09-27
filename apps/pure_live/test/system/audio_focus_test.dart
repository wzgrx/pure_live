import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/system/audio_focus.dart';

import 'session_harness.dart';

final class _FakePort implements AudioFocusPort {
  final calls = <String>[];
  final _events = StreamController<FocusEvent>.broadcast(sync: true);

  void emit(FocusEvent event) => _events.add(event);

  @override
  Future<bool> activate() async {
    calls.add('activate');
    return true;
  }

  @override
  Future<void> deactivate() async => calls.add('deactivate');

  @override
  Stream<FocusEvent> get events => _events.stream;
}

void main() {
  group('AudioFocusCoordinator (INT-4)', () {
    test('holds the focus while the user wants to play', () {
      fakeAsync((async) {
        final port = _FakePort();
        final focus = AudioFocusCoordinator(port);
        final h = SessionHarness(async)..openAndPlay();
        focus.attach(h.session);
        h.settle();
        expect(port.calls, ['activate']);
        unawaited(h.session.pause());
        h.settle();
        expect(port.calls, ['activate', 'deactivate']);
        unawaited(h.session.play());
        h.settle();
        expect(port.calls.last, 'activate');
        focus.attach(null);
        expect(port.calls.last, 'deactivate');
      });
    });

    test('a transient loss suspends with a token; the regained focus resumes', () {
      fakeAsync((async) {
        final port = _FakePort();
        final focus = AudioFocusCoordinator(port);
        final h = SessionHarness(async)..openAndPlay();
        focus.attach(h.session);
        port.emit(FocusEvent.lostTransient);
        h.settle();
        expect(h.state.phase, PlaybackPhase.suspended);
        expect(h.commands.last, 'pause');
        port.emit(FocusEvent.regained);
        h.settle();
        expect(h.commands.last, 'play');
        expect(h.state.phase, isNot(PlaybackPhase.suspended));
      });
    });

    test('a user command during the interruption wins over the regained focus', () {
      fakeAsync((async) {
        final port = _FakePort();
        final focus = AudioFocusCoordinator(port);
        final h = SessionHarness(async)..openAndPlay();
        focus.attach(h.session);
        port.emit(FocusEvent.lostTransient);
        h.settle();
        unawaited(h.session.pause());
        h.settle();
        port.emit(FocusEvent.regained);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
      });
    });

    test('a permanent loss and unplugged headphones pause like the user', () {
      fakeAsync((async) {
        final port = _FakePort();
        final focus = AudioFocusCoordinator(port);
        final h = SessionHarness(async)..openAndPlay();
        focus.attach(h.session);
        port.emit(FocusEvent.lost);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
        expect(h.state.wantsPlay, isFalse);

        unawaited(h.session.play());
        h.settle();
        port.emit(FocusEvent.becameNoisy);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
      });
    });

    test('suspension and background suspension stack: both must end (INT-2)', () {
      fakeAsync((async) {
        final port = _FakePort();
        final focus = AudioFocusCoordinator(port);
        final h = SessionHarness(async)..openAndPlay();
        focus.attach(h.session);
        final background = h.session.suspend(SuspendReason.background);
        port
          ..emit(FocusEvent.lostTransient)
          ..emit(FocusEvent.regained);
        h.settle();
        expect(h.state.phase, PlaybackPhase.suspended, reason: 'the background suspension still holds');
        h.session.resume(background);
        h.settle();
        expect(h.state.phase, isNot(PlaybackPhase.suspended));
      });
    });
  });

  test('audio_session interruptions map to focus events; ducking is left to the system', () {
    expect(focusEventOf(AudioInterruptionEvent(true, AudioInterruptionType.pause)), FocusEvent.lostTransient);
    expect(focusEventOf(AudioInterruptionEvent(true, AudioInterruptionType.unknown)), FocusEvent.lost);
    expect(focusEventOf(AudioInterruptionEvent(false, AudioInterruptionType.pause)), FocusEvent.regained);
    expect(focusEventOf(AudioInterruptionEvent(true, AudioInterruptionType.duck)), isNull);
    expect(focusEventOf(AudioInterruptionEvent(false, AudioInterruptionType.duck)), isNull);
  });
}
