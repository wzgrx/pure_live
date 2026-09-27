import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_discover.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_room.dart';

/// The site only needs its clock for the sheet (availability).
final class _NoRepository implements IptvRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('pages', () {
    IptvPlaylistRecord playlist(int id, String name, {String? error, DateTime? synced, bool remote = true}) =>
        IptvPlaylistRecord(
          id: id,
          name: name,
          source: remote ? 'https://lists.fixture/$id.m3u' : '/data/IPTV/playlists/$id.txt',
          order: id,
          lastSyncAt: synced,
          lastError: error,
          entryCount: 12,
          channelCount: 10,
        );

    Future<LiveStore> openStore(WidgetTester tester) async {
      final store = (await tester.runAsync(LiveStore.inMemory))!;
      addTearDown(() => tester.runAsync(store.close));
      return store;
    }

    testWidgets('the playlist page lists playlists, their state and the actions', (tester) async {
      final store = await openStore(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            iptvPlaylistsProvider.overrideWith(
              (ref) => Stream.value([
                playlist(1, '央视源', synced: DateTime.now().subtract(const Duration(hours: 2))),
                playlist(2, '本地列表', remote: false, error: '网络连接失败，检查网络或代理后重试'),
              ]),
            ),
            iptvGuideSourcesProvider.overrideWith(
              (ref) => Stream.value(const [
                IptvGuideSourceRecord(
                  id: 1,
                  name: 'e.xml',
                  source: 'https://epg.fixture/e.xml',
                  order: 0,
                  selected: true,
                ),
              ]),
            ),
          ],
          child: const MaterialApp(home: IptvPage()),
        ),
      );
      await tester.pump();
      expect(find.text('央视源'), findsOneWidget);
      expect(find.text('10 个频道 · 2 小时前同步'), findsOneWidget);
      expect(find.text('上次同步失败：网络连接失败，检查网络或代理后重试'), findsOneWidget);
      expect(find.text('当前：e.xml'), findsOneWidget);
      expect(find.text('自动同步'), findsOneWidget);
      expect(find.text('每天'), findsOneWidget, reason: 'default interval 24 h');

      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      expect(find.text('复制来源地址'), findsOneWidget);
      expect(find.text('User-Agent'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.text('从网址导入'));
      await tester.pumpAndSettle();
      expect(find.text('网址'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('without playlists the page and the discover tab explain what to do', (tester) async {
      final store = await openStore(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            iptvPlaylistsProvider.overrideWith((ref) => Stream.value(const [])),
            iptvGuideSourcesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const MaterialApp(home: Scaffold(body: IptvDiscover())),
        ),
      );
      await tester.pump();
      expect(find.text('还没有播放列表'), findsOneWidget);
      expect(find.text('导入播放列表'), findsOneWidget);
    });
  });

  testWidgets('the programme sheet marks days, the programme on air and what can be replayed', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day, now.hour);
    final room = IptvSite.refOf('CCTV-1 综合');
    IptvProgramme programme(int hours, String title) => IptvProgramme(
      channelId: 'CCTV1',
      start: start.add(Duration(hours: hours)),
      stop: start.add(Duration(hours: hours + 1)),
      title: title,
    );
    IptvChannel channel(IptvCatchup catchup) => IptvChannel(
      ref: room,
      sources: [
        IptvSource(
          entry: IptvEntry(name: 'CCTV-1 综合', url: 'http://a.fixture/1.m3u8', catchup: catchup),
          playlistId: '1',
        ),
      ],
      guideId: '1',
      guideChannelId: 'CCTV1',
    );
    Future<void> show(IptvCatchup catchup) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            iptvSiteProvider.overrideWithValue(IptvSite(_NoRepository(), now: () => now)),
            iptvChannelProvider.overrideWith((ref, room) async => channel(catchup)),
            iptvGuideProvider.overrideWith(
              (ref, room) async => [programme(-2, '早间新闻'), programme(0, '正在播出的节目'), programme(1, '下一个节目')],
            ),
          ],
          child: MaterialApp(
            theme: themesFor(AppThemeMode.light, pureBlack: false).$1,
            home: Scaffold(
              body: IptvGuideSheet(room: room, now: now),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await show(IptvCatchup.none);
    expect(find.textContaining('今天'), findsWidgets);
    expect(find.text('正在播出的节目'), findsOneWidget);
    expect(find.text('直播'), findsOneWidget, reason: 'the live badge');
    expect(find.byIcon(Icons.replay), findsOneWidget, reason: 'playseek rule: the past programme can be replayed');

    await show(IptvCatchup.disabled);
    expect(find.text('不可回看'), findsOneWidget);
  });
}
