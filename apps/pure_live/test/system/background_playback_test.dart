import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/system/background_playback.dart';

import 'session_harness.dart';

void main() {
  group('BackgroundPlayback (INT-3, PERF-2)', () {
    late bool allow;
    late bool pip;
    late bool mini;

    BackgroundPlayback policy() =>
        BackgroundPlayback(allowBackground: () => allow, pipActive: () => pip, miniWindowShowing: () => mini);

    setUp(() {
      allow = false;
      pip = false;
      mini = false;
    });

    void goBackground(BackgroundPlayback policy) {
      policy
        ..lifecycleChanged(AppLifecycleState.inactive)
        ..lifecycleChanged(AppLifecycleState.hidden)
        ..lifecycleChanged(AppLifecycleState.paused);
    }

    void goForeground(BackgroundPlayback policy) {
      policy
        ..lifecycleChanged(AppLifecycleState.hidden)
        ..lifecycleChanged(AppLifecycleState.inactive)
        ..lifecycleChanged(AppLifecycleState.resumed);
    }

    test('suspends 1.5 s after the app is hidden and resumes in the foreground', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final background = policy()..attach(h.session);
        goBackground(background);
        h.settle(const Duration(milliseconds: 1400));
        expect(h.state.phase, PlaybackPhase.playing, reason: 'not before 1.5 s');
        h.settle(const Duration(milliseconds: 200));
        expect(h.state.phase, PlaybackPhase.suspended);
        expect(h.state.wantsPlay, isTrue, reason: 'a suspension keeps the intent (INT-2)');
        expect(h.commands.last, 'pause');

        goForeground(background);
        h.settle();
        expect(h.commands.last, 'play');
        expect(h.state.phase, isNot(PlaybackPhase.suspended));
      });
    });

    test('a short hidden phase (rotation, PiP entry, Surface swap) changes nothing', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final background = policy()..attach(h.session);
        final commands = h.commands.length;
        goBackground(background);
        h.settle(const Duration(milliseconds: 800));
        goForeground(background);
        h.settle(const Duration(seconds: 3));
        expect(h.commands, hasLength(commands));
        expect(h.state.phase, PlaybackPhase.playing);
      });
    });

    test('with background play, video output goes off and comes back', () {
      fakeAsync((async) {
        allow = true;
        final h = SessionHarness(async)..openAndPlay();
        final background = policy()..attach(h.session);
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        expect(h.commands.last, 'audioOnly true');
        expect(h.state.phase, isNot(PlaybackPhase.suspended));
        expect(h.state.audioOnly, isTrue);

        goForeground(background);
        h.settle();
        expect(h.commands.last, 'audioOnly false');
      });
    });

    test('background play leaves a user-chosen audio-only mode alone', () {
      fakeAsync((async) {
        allow = true;
        final h = SessionHarness(async)..openAndPlay();
        unawaited(h.session.setAudioOnly(enabled: true));
        h.settle();
        final background = policy()..attach(h.session);
        final commands = h.commands.length;
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        goForeground(background);
        h.settle();
        expect(h.commands, hasLength(commands));
        expect(h.state.audioOnly, isTrue);
      });
    });

    test('picture-in-picture and the mini window keep playing (PIP-5)', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final background = policy()..attach(h.session);
        pip = true;
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        expect(h.state.phase, PlaybackPhase.playing);
        goForeground(background);

        pip = false;
        mini = true;
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        expect(h.state.phase, PlaybackPhase.playing);
        expect(h.commands, isNot(contains('audioOnly true')));
      });
    });

    test('a user command during the suspension makes the token stale (INT-2)', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final background = policy()..attach(h.session);
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        unawaited(h.session.pause());
        h.settle();
        goForeground(background);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused, reason: 'the old token must not resume a user pause');
      });
    });

    test('a paused room is left alone; a room attached while hidden is scheduled', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        unawaited(h.session.pause());
        h.settle();
        final background = policy()..attach(h.session);
        goBackground(background);
        h.settle(const Duration(seconds: 2));
        expect(h.state.phase, PlaybackPhase.paused);

        final other = SessionHarness(async)..openAndPlay(room: 'douyu:2');
        background.attach(other.session);
        other.settle(const Duration(seconds: 2));
        expect(other.state.phase, PlaybackPhase.suspended);
      });
    });

    test('the Wi-Fi lock is wanted only while hidden and delivering', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        expect(wantsWifiLock(hidden: false, state: h.state), isFalse);
        expect(wantsWifiLock(hidden: true, state: h.state), isTrue);
        expect(wantsWifiLock(hidden: true, state: null), isFalse);
        h.session.suspend(SuspendReason.background);
        h.settle();
        expect(wantsWifiLock(hidden: true, state: h.state), isFalse);
      });
    });
  });
}
