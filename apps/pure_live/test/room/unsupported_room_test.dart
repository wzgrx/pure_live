import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show Appearance, PureTheme;
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/room/playback.dart';
import 'package:pure_live_app/features/room/room_page.dart';

import '../danmaku/fake_danmaku.dart';
import '../fakes.dart';

void main() {
  test('F-FAV-08: a missing adapter is a typed error with its own notice', () {
    final sites = {'douyu': PlatformSite(FakeSite('douyu'))};
    expect(sites.of('douyu'), same(sites['douyu']));
    expect(
      () => sites.of('huajiao'),
      throwsA(isA<PlatformUnsupported>().having((e) => e.platform, 'platform', 'huajiao')),
    );
    final text = describeError(const PlatformUnsupported('huajiao'));
    expect(text.title, '平台暂不支持');
    expect(text.message, contains('花椒'));
    expect(text.retryable, isFalse);
  });

  testWidgets('F-FAV-08: a room of an unsupported platform opens on a notice page, not a crash', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        // A typed failure does not heal by itself; no retry timers either.
        retry: (_, _) => null,
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(FakeSite('douyu'))}),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(true)),
          danmakuSourceProvider.overrideWithValue(FakeDanmakuSource()),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
          playbackSessionProvider.overrideWith(
            (ref) => PlaybackSession(engine: () => throw UnimplementedError('no engine in widget tests')),
          ),
          followsProvider.overrideWith((ref) => Stream.value(const [])),
          historyProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: RoomPage(room: RoomRef('huajiao', '361433')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('平台暂不支持'), findsOneWidget);
    expect(find.textContaining('花椒已下线'), findsOneWidget);
    expect(find.text('返回'), findsWidgets);
    expect(find.text('重试'), findsNothing, reason: 'retrying cannot help');
  });
}
