import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/mini_player.dart';
import 'package:pure_live_app/features/system/mini_player_host.dart';
import 'package:pure_live_app/features/system/now_playing.dart';

import 'session_harness.dart';

NowPlaying _playing(PlaybackSession session, {String roomId = '1'}) =>
    NowPlaying(session: session, room: RoomRef('douyu', roomId), title: '标题', anchor: '主播');

void main() {
  group('rules (PIP-4)', () {
    test('the window shows with a ready surface, no popup and no PiP layout', () {
      final mini = MiniPlayerState(playing: _playing(PlaybackSession(engine: FakeEngine.new)), surfaceReady: true);
      expect(miniWindowVisible(mini: mini, openPopups: 0, pipVideoOnly: false), isTrue);
      expect(miniWindowVisible(mini: mini, openPopups: 1, pipVideoOnly: false), isFalse);
      expect(miniWindowVisible(mini: mini, openPopups: 0, pipVideoOnly: true), isFalse);
      expect(
        miniWindowVisible(mini: MiniPlayerState(playing: mini.playing), openPopups: 0, pipVideoOnly: false),
        isFalse,
      );
      expect(miniWindowVisible(mini: null, openPopups: 0, pipVideoOnly: false), isFalse);
    });

    test('only a room with a picture and no error shrinks to the mini window', () {
      expect(MiniPlayerController.canAdopt(const PlaybackState()), isFalse);
      expect(
        MiniPlayerController.canAdopt(
          const PlaybackState(phase: PlaybackPhase.playing, wantsPlay: true, hasPicture: true),
        ),
        isTrue,
      );
      expect(
        MiniPlayerController.canAdopt(const PlaybackState(phase: PlaybackPhase.paused, hasPicture: true)),
        isTrue,
        reason: 'a paused room keeps its picture',
      );
      expect(
        MiniPlayerController.canAdopt(const PlaybackState(phase: PlaybackPhase.playing, wantsPlay: true)),
        isFalse,
        reason: 'no picture yet: a black window would stay',
      );
      expect(
        MiniPlayerController.canAdopt(
          const PlaybackState(
            phase: PlaybackPhase.error,
            hasPicture: true,
            failure: PlaybackFailure(FailureKind.network, 'x'),
          ),
        ),
        isFalse,
      );
      expect(
        MiniPlayerController.canAdopt(
          const PlaybackState(phase: PlaybackPhase.playing, wantsPlay: true, hasPicture: true, audioOnly: true),
        ),
        isFalse,
      );
      expect(miniWindowSize(aspect: 16 / 9, desktop: true), const Size(350, 196.875));
      expect(miniWindowSize(aspect: 9 / 16, desktop: false), const Size(123.75, 220));
    });
  });

  group('MiniPlayerController hand-off', () {
    late LiveStore store;
    late List<VoidCallback> frames;
    late ProviderContainer container;

    setUp(() async {
      store = await LiveStore.inMemory();
      await store.settings.set(Settings.miniPlayerOnLeave, true);
      frames = [];
      container = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store), frameSchedulerProvider.overrideWithValue(frames.add)],
      );
    });

    tearDown(() async {
      container.dispose();
      await store.close();
    });

    MiniPlayerController mini() => container.read(miniPlayerProvider.notifier);

    void nextFrame() {
      final due = [...frames];
      frames.clear();
      for (final callback in due) {
        callback();
      }
    }

    test('adopts at once, mounts the surface two frames later and hands the session back', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final playing = _playing(h.session);
        container.read(nowPlayingProvider.notifier).attach(playing);
        expect(mini().adopt(playing), isTrue);
        expect(mini().owns(h.session), isTrue, reason: 'the session provider asks at once');
        expect(container.read(miniPlayerProvider), isNull, reason: 'no provider change inside dispose()');
        nextFrame();
        expect(container.read(miniPlayerProvider)?.surfaceReady, isFalse);
        nextFrame();
        expect(container.read(miniPlayerProvider)?.surfaceReady, isTrue);

        final back = mini().reclaim(RoomRef('douyu', '1'))!;
        expect(back.playing.session, same(h.session), reason: 'SES-9: the same session comes back');
        expect(mini().owns(h.session), isFalse);
        var released = false;
        unawaited(back.surfaceReleased.then((_) => released = true));
        nextFrame();
        expect(container.read(miniPlayerProvider), isNull);
        async.flushMicrotasks();
        expect(released, isFalse, reason: 'the mini view unmounts in the frame after the state change');
        nextFrame();
        async.flushMicrotasks();
        expect(released, isTrue);
        expect(h.engine.disposed, isFalse);
        expect(container.read(nowPlayingProvider), same(playing));
      });
    });

    test('another room closes the mini window: view first, then the session', () {
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        final playing = _playing(h.session);
        container.read(nowPlayingProvider.notifier).attach(playing);
        mini().adopt(playing);
        nextFrame();
        nextFrame();
        expect(mini().reclaim(RoomRef('douyu', '2')), isNull);
        expect(mini().holding, isFalse);
        nextFrame();
        expect(container.read(miniPlayerProvider), isNull);
        expect(container.read(nowPlayingProvider), isNull);
        expect(h.engine.disposed, isFalse, reason: 'PIP-6: the engine goes after the view');
        nextFrame();
        async.elapse(const Duration(milliseconds: 50));
        expect(h.engine.disposed, isTrue);
      });
    });

    test('declines a room without a picture yet', () {
      fakeAsync((async) {
        final starting = SessionHarness(async);
        unawaited(
          starting.session.open(
            PlaybackRequest(site: 'douyu', roomKey: 'douyu:3', resolve: (_) => Completer<StreamSet>().future),
          ),
        );
        async.flushMicrotasks();
        expect(mini().adopt(_playing(starting.session, roomId: '3')), isFalse);
        expect(frames, isEmpty);
      });
    });

    test('declines without the setting', () async {
      await store.settings.set(Settings.miniPlayerOnLeave, false);
      fakeAsync((async) {
        final h = SessionHarness(async)..openAndPlay();
        expect(mini().adopt(_playing(h.session)), isFalse);
        expect(frames, isEmpty);
      });
    });
  });

  group('MiniPlayerHost', () {
    testWidgets('floats above pages, hides under popups and returns to the room', (tester) async {
      final store = (await tester.runAsync(LiveStore.inMemory))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.runAsync(() => store.settings.set(Settings.miniPlayerOnLeave, true));

      final session = await playingSession(tester);
      expect(session.state.hasPicture, isTrue);

      final reclaimed = <bool>[];
      final tracker = PopupRouteTracker();
      addTearDown(tracker.dispose);
      final router = GoRouter(
        observers: [PopupRouteObserver(tracker)],
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭对话框')),
                    ),
                  ),
                  child: const Text('打开对话框'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/room/:platform/:roomId',
            builder: (context, state) => _RoomProbe(
              room: RoomRef(state.pathParameters['platform']!, state.pathParameters['roomId']!),
              onReclaim: reclaimed.add,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          routerProvider.overrideWithValue(router),
          popupTrackerProvider.overrideWithValue(tracker),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MiniPlayerHost(child: child!),
          ),
        ),
      );
      expect(find.byType(LiveVideoView), findsNothing);

      final playing = _playing(session);
      container.read(nowPlayingProvider.notifier).attach(playing);
      expect(container.read(miniPlayerProvider.notifier).adopt(playing), isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(LiveVideoView), findsOneWidget);
      expect(_offstage(tester), isFalse);

      // A dialog: the whole mini window goes offstage (REG-PLAY-017).
      await tester.tap(find.text('打开对话框'));
      await _settle(tester);
      expect(tracker.value, 1);
      expect(_offstage(tester), isTrue);
      await tester.tap(find.text('关闭对话框'));
      await _settle(tester);
      expect(tracker.value, 0);
      expect(_offstage(tester), isFalse);

      // Tapping returns to the room, which takes the same session back (SES-9).
      await tester.tap(find.byType(LiveVideoView));
      await _settle(tester);
      expect(find.text('直播间 douyu:1'), findsOneWidget);
      expect(reclaimed, [true]);
      expect(find.byType(LiveVideoView), findsNothing);
      expect(container.read(miniPlayerProvider), isNull);

      // The room page owns the session again and releases it.
      unawaited(session.dispose());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

/// Pumps through route transitions without waiting for endless animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _offstage(WidgetTester tester) => tester
    .widget<Offstage>(
      find
          .ancestor(
            of: find.byType(LiveVideoView, skipOffstage: false),
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .first,
    )
    .offstage;

class _RoomProbe extends ConsumerStatefulWidget {
  const new({required this.room, required this.onReclaim});

  final RoomRef room;
  final ValueChanged<bool> onReclaim;

  @override
  ConsumerState<_RoomProbe> createState() => _RoomProbeState();
}

class _RoomProbeState extends ConsumerState<_RoomProbe> {
  @override
  void initState() {
    super.initState();
    widget.onReclaim(ref.read(miniPlayerProvider.notifier).reclaim(widget.room) != null);
  }

  @override
  Widget build(BuildContext context) => Text('直播间 ${widget.room.key}');
}
