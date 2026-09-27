import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show Appearance, PureTheme;
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/room_page.dart';
import 'package:pure_live_app/features/system/mini_player.dart';
import 'package:pure_live_app/features/system/now_playing.dart';

import '../danmaku/fake_danmaku.dart';
import '../system/session_harness.dart';

/// Counts stream requests: a room taken back from the mini window must not
/// be opened again.
final class _CountingSite implements RoomSource, StreamSource {
  int streamRequests = 0;

  @override
  Future<RoomDetail> detail(RoomRef ref) async => liveRoom(id: ref.roomId);

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) {
    streamRequests++;
    return Completer<StreamSet>().future;
  }
}

void main() {
  testWidgets('SES-9 / PIP-4: the room takes its playback back from the mini window and hands it over again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.runAsync(() => store.settings.set(Settings.miniPlayerOnLeave, true));
    final site = _CountingSite();
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
        roomDetailProvider.overrideWith((ref, room) async => liveRoom(id: room.roomId)),
        isFollowedProvider.overrideWith((ref, room) => Stream.value(false)),
        danmakuSourceProvider.overrideWithValue(FakeDanmakuSource()),
        blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
        followsProvider.overrideWith((ref) => Stream.value(const [])),
        historyProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    // The mini window plays douyu:1.
    final session = await playingSession(tester);
    final playing = NowPlaying.fromDetail(session, liveRoom());
    container.read(nowPlayingProvider.notifier).attach(playing);
    expect(container.read(miniPlayerProvider.notifier).adopt(playing), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => RoomPage(room: RoomRef('douyu', '1')))),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(container.read(miniPlayerProvider)?.surfaceReady, isTrue);

    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = tester.widget<PlayerView>(find.byType(PlayerView));
    expect(view.session, same(session), reason: 'same session, commit, quality and line');
    expect(view.resume, isTrue);
    expect(view.surfaceReady, isTrue, reason: 'the mini window let go of the surface');
    expect(site.streamRequests, 0, reason: 'not opened again');
    expect(container.read(miniPlayerProvider), isNull);
    expect(container.read(nowPlayingProvider)?.session, same(session));

    // Leaving hands the playing room to the mini window again; the session lives on.
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RoomPage), findsNothing);
    expect(container.read(miniPlayerProvider.notifier).owns(session), isTrue);
    expect(container.read(miniPlayerProvider)?.surfaceReady, isTrue);
    expect(container.read(nowPlayingProvider)?.session, same(session));
    expect(session.state.hasPicture, isTrue, reason: 'not disposed with the page');

    // Released a frame after the window unmounts (PIP-6).
    final closed = container.read(miniPlayerProvider.notifier).close();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await closed;
    expect(container.read(nowPlayingProvider), isNull);
  });
}
