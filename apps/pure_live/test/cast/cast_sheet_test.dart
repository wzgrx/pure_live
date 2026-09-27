import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/cast/cast_controller.dart';
import 'package:pure_live_app/features/cast/cast_sheet.dart';

import '../danmaku/fake_danmaku.dart' show liveRoom;
import 'fake_cast.dart';

final CastDevice _tv = castDevice('客厅电视', id: 'uuid:tv', manufacturer: 'Xiaomi');
final CastDevice _box = castDevice('卧室盒子', id: 'uuid:box', host: '192.168.1.21');

void main() {
  late FakeSearches searches;
  late FakeRenderers renderers;

  setUp(() {
    searches = FakeSearches();
    renderers = FakeRenderers();
  });

  /// Pumps a page whose button opens the sheet for [state]; the progress
  /// bar animates while searching, so every wait is a fixed pump.
  Future<void> openSheet(WidgetTester tester, {PlaybackState? state}) async {
    if (tester.any(find.byType(ProviderScope))) {
      await tester.tap(find.text('打开投屏'));
    } else {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            castSearchProvider.overrideWithValue(searches.call),
            castRendererProvider.overrideWithValue(renderers.call),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () => showCastSheet(context, ref, detail: liveRoom(), state: state ?? playingState()),
                    child: const Text('打开投屏'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开投屏'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

  testWidgets('no device: searches on open, then says so and searches again on request', (tester) async {
    await openSheet(tester);
    expect(searches.searches, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('正在搜索同一 Wi-Fi 下的电视和盒子…'), findsOneWidget);

    await searches.last.close();
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('没有找到可投屏的设备'), findsOneWidget);
    expect(find.textContaining('同一个 Wi-Fi'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重新搜索'));
    await settle(tester);
    expect(searches.searches, hasLength(2));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('没有找到可投屏的设备'), findsNothing);
  });

  testWidgets('search failure has its own message and a retry', (tester) async {
    await openSheet(tester);
    searches.last.addError(const CastSearchFailure('no UDP socket'));
    await searches.last.close();
    await settle(tester);
    expect(find.text('搜索失败'), findsOneWidget);
    expect(find.text('没有找到可投屏的设备'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await settle(tester);
    expect(searches.searches, hasLength(2));
  });

  testWidgets('devices: casts the upstream URL, shows 已投到, switches, and stops', (tester) async {
    await openSheet(tester);
    searches.last
      ..add(_tv)
      ..add(_box);
    await settle(tester);
    expect(find.text('客厅电视'), findsOneWidget);
    expect(find.text('Xiaomi · 192.168.1.20'), findsOneWidget);
    expect(find.text('卧室盒子'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'still searching');

    await tester.tap(find.text('客厅电视'));
    await settle(tester);
    expect(renderers.log, ['set 客厅电视 $upstreamUrl video/x-flv', 'play 客厅电视']);
    expect(find.text('已投到 客厅电视'), findsOneWidget);
    expect(find.text('正在投这个直播间 · 电视正在播放'), findsOneWidget);
    expect(find.text('停止投屏'), findsOneWidget);

    // Another renderer: the first one is stopped first (REG-ROOM-016).
    await tester.tap(find.text('卧室盒子'));
    await settle(tester);
    expect(renderers.log.skip(2), ['stop 客厅电视', 'set 卧室盒子 $upstreamUrl video/x-flv', 'play 卧室盒子']);
    expect(find.text('已投到 卧室盒子'), findsOneWidget);

    // Closing the sheet keeps the cast.
    await searches.last.close();
    Navigator.of(tester.element(find.text('卧室盒子'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container(tester).read(castProvider).casting, isTrue);

    // Reopened: the cast is shown with what the renderer says.
    await openSheet(tester);
    await settle(tester);
    expect(find.text('已投到 卧室盒子'), findsOneWidget);
    expect(find.text('正在投这个直播间 · 电视已暂停'), findsOneWidget);
    await tester.tap(find.text('停止投屏'));
    await settle(tester);
    expect(renderers.log.last, 'stop 卧室盒子');
    expect(find.text('停止投屏'), findsNothing);
    expect(container(tester).read(castProvider).phase, CastPhase.idle);
  });

  testWidgets('cast failure: explains it, keeps the list, no 已投到', (tester) async {
    renderers.failures['set 客厅电视'] = const UpnpActionFailure('SetAVTransportURI', 716, 'Resource not found');
    renderers.failures['play 卧室盒子'] = const CastTimeoutFailure(Duration(seconds: 6));
    await openSheet(tester);
    searches.last
      ..add(_tv)
      ..add(_box);
    await searches.last.close();
    await settle(tester);

    await tester.tap(find.text('客厅电视'));
    await settle(tester);
    expect(renderers.log, ['set 客厅电视 $upstreamUrl video/x-flv']);
    expect(find.text('投屏失败：设备打不开这个直播地址，换一条线路试试'), findsOneWidget);
    expect(find.textContaining('已投到'), findsNothing);
    expect(find.text('客厅电视'), findsOneWidget);

    await tester.tap(find.text('卧室盒子'));
    await settle(tester);
    expect(find.text('投屏失败：连不上这台设备，确认它开着，并且和手机连着同一个 Wi-Fi'), findsOneWidget);
    expect(container(tester).read(castProvider).phase, CastPhase.failed);
  });

  testWidgets('invalid addresses are explained and nothing is searched', (tester) async {
    await openSheet(tester, state: playingState(url: Uri.parse('http://127.0.0.1:38211/relay/7f3a')));
    expect(find.text('当前地址不能投屏'), findsOneWidget);
    expect(find.text('当前线路是本机地址，电视访问不到'), findsOneWidget);
    expect(searches.searches, isEmpty);
    expect(find.byTooltip('重新搜索'), findsNothing);
  });

  testWidgets('no line yet is explained too', (tester) async {
    await openSheet(tester, state: const PlaybackState(phase: PlaybackPhase.resolving, wantsPlay: true));
    expect(find.text('还没有拿到直播地址，等画面出来后再投屏'), findsOneWidget);
    expect(searches.searches, isEmpty);
  });

  testWidgets('lines with request headers or a lease warn but still cast', (tester) async {
    await openSheet(
      tester,
      state: playingState(
        url: Uri.parse('https://cn-gd.bilivideo.com/live-bvc/1.m3u8?expires=1'),
        format: StreamFormat.hls,
        headers: const {'referer': 'https://live.bilibili.com', 'user-agent': 'Mozilla/5.0'},
        lease: Lease(refreshAt: DateTime(2026, 9, 28, 12), cutsConnection: false),
      ),
    );
    expect(find.text('这个平台的直播流可能需要特殊请求头，电视上不一定能播'), findsOneWidget);
    expect(find.text('直播地址有时效，过期后电视会停止播放，重新投屏即可'), findsOneWidget);
    searches.last.add(_tv);
    await settle(tester);
    await tester.tap(find.text('客厅电视'));
    await settle(tester);
    expect(renderers.log.first, 'set 客厅电视 https://cn-gd.bilivideo.com/live-bvc/1.m3u8?expires=1 ${CastMime.hls}');
    expect(find.text('已投到 客厅电视'), findsOneWidget);
    await searches.last.close();
  });

  testWidgets('closing the sheet cancels the search', (tester) async {
    await openSheet(tester);
    final search = searches.last;
    var cancelled = false;
    search.onCancel = () => cancelled = true;
    Navigator.of(tester.element(find.text('投屏'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(cancelled, isTrue);
    expect(container(tester).read(castProvider).phase, CastPhase.idle);
  });

  testWidgets('a cast of another room names it', (tester) async {
    await openSheet(tester);
    searches.last.add(_tv);
    await settle(tester);
    await container(tester)
        .read(castProvider.notifier)
        .cast(
          _tv,
          CastMedia(url: upstreamUrl, title: '主播9'),
          room: RoomRef('douyu', '9'),
          roomTitle: '主播9',
        );
    await settle(tester);
    expect(find.text('正在投：主播9 · 电视正在播放'), findsOneWidget);
    await searches.last.close();
  });
}
