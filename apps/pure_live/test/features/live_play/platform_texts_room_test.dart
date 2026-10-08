// Z05.2: a room in the English interface shows the adapter's notice, area,
// qualities and chat notices in English.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  testWidgets('English: the notice, area, qualities and chat notices the adapter wrote are English', (tester) async {
    final en = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, Object?>;
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RoomOrientationChoice.clearSession();
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(() => loadStrings(AppLanguage.en));
    const own = '主播公告：今晚八点';
    final site = FakeSite(
      LiveRoom(
        platform: SiteIds.pandaLive,
        roomId: '6',
        nick: 'streamer',
        title: 'tonight',
        area: PandaLiveApi.areaNames['talk'],
        liveStatus: LiveStatus.live,
        notice: '${PandaLiveApi.adultNotice}\n$own',
        danmakuData: 'args-6',
      ),
    )..siteId = SiteIds.pandaLive;
    final danmaku = FakeDanmaku();
    final engine = FakeEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          sitesProvider.overrideWithValue(SiteRegistry({SiteIds.pandaLive: () => site})),
          danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.pandaLive: () => danmaku})),
          playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
        ],
        child: MaterialApp(
          theme: const LiveTheme().light,
          home: LivePlayPage(
            route: RouteArgs(
              RoutePath.kLivePlay,
              arguments: LiveRoom(platform: SiteIds.pandaLive, roomId: '6', nick: 'streamer'),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    // The quality button: 原画 is "Source".
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-play-quality')),
        matching: find.text('${en['quality_name_original']}'),
      ),
      findsOneWidget,
    );
    // A notice the connection wrote, in the chat.
    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.notice,
          userName: '',
          message: KickDanmakuProtocol.streamEndedNotice,
          color: LiveMessageColor.white,
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('${en['kick_stream_ended_notice']}'), findsOneWidget);
    expect(find.textContaining(KickDanmakuProtocol.streamEndedNotice), findsNothing);

    // The details: the adapter's notice in English, the streamer's own line
    // as written; the area in English.
    await tester.tap(find.byKey(const ValueKey('live-play-info')));
    await tester.pumpAndSettle();
    expect(find.textContaining('${en['pandalive_adult_notice']}'), findsOneWidget);
    expect(find.textContaining(own), findsOneWidget);
    expect(find.textContaining(PandaLiveApi.adultNotice), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-play-details-area')),
        matching: find.textContaining('${en['pandalive_category_talk']}', findRichText: true),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(services.close);
    await tester.runAsync(loadStrings);
  });
}
