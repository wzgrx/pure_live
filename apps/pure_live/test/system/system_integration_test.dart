import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/audio_focus.dart';
import 'package:pure_live_app/features/system/media_controls.dart';
import 'package:pure_live_app/features/system/now_playing.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:pure_live_app/features/system/system_integration.dart';

import 'session_harness.dart';

final class _Controls implements MediaControls {
  final shown = <String>[];

  @override
  Stream<MediaCommand> get commands => const Stream.empty();

  @override
  Future<void> show(MediaInfo info, {required bool playing}) async => shown.add('${info.id} $playing');

  @override
  Future<void> hide() async => shown.add('hidden');
}

final class _Focus implements AudioFocusPort {
  final calls = <String>[];

  @override
  Future<bool> activate() async {
    calls.add('activate');
    return true;
  }

  @override
  Future<void> deactivate() async => calls.add('deactivate');

  @override
  Stream<FocusEvent> get events => const Stream.empty();
}

final class _Pip implements PipPlatform {
  final updates = <PipRequest>[];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter(PipRequest request) async => true;

  @override
  Future<void> update(PipRequest request) async => updates.add(request);

  @override
  Future<bool> exit() async => true;

  @override
  Stream<PipEvent> get events => const Stream.empty();
}

void main() {
  testWidgets('follows the playing room: controls, focus, PiP ratio and the background policy', (tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final controls = _Controls();
    final focus = _Focus();
    final pip = _Pip();
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        mediaControlsProvider.overrideWithValue(controls),
        audioFocusPortProvider.overrideWithValue(focus),
        pipPlatformProvider.overrideWithValue(pip),
        windowsShellEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(systemIntegrationProvider);
            return const SizedBox();
          },
        ),
      ),
    );

    final session = await playingSession(tester, width: 720, height: 1280);
    final engine = session.engine! as FakeEngine;

    container
        .read(nowPlayingProvider.notifier)
        .attach(NowPlaying(session: session, room: RoomRef('douyu', '1'), title: '标题', anchor: '主播'));
    await tester.pump();
    await tester.pump();
    expect(controls.shown.last, 'douyu:1 true');
    expect(focus.calls, ['activate']);
    expect(pip.updates.last.aspect, closeTo(720 / 1280, 1e-9));
    expect(pip.updates.last.autoEnter, isFalse, reason: 'automatic PiP is Android only');

    // Hidden for 1.5 s: the room is suspended; back in front it plays (INT-3).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state.phase, PlaybackPhase.suspended);
    expect(controls.shown.last, 'douyu:1 false');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.commands.last, 'play');
    expect(controls.shown.last, 'douyu:1 true');

    // With background play the video goes off instead (F-BG-01, PERF-2).
    await tester.runAsync(() => store.settings.set(Settings.backgroundPlay, true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 2));
    expect(engine.commands.last, 'audioOnly true');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.commands.last, 'audioOnly false');

    container.read(nowPlayingProvider.notifier).detach(session);
    await tester.pump();
    expect(controls.shown.last, 'hidden');
    expect(focus.calls.last, 'deactivate');
    unawaited(session.dispose());
    await tester.pump(const Duration(seconds: 1));
  });
}
