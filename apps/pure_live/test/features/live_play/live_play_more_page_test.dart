import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A receiver that records what it was asked to do.
final class _Receiver implements DlnaCastDevice {
  final List<String> calls = [];

  @override
  String get id => 'uuid:tv';

  @override
  String get name => '客厅电视';

  @override
  String get address => 'http://192.168.1.20:49152';

  @override
  Future<void> setSource(String source) async => calls.add('source $source');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<TransportInfo> transportInfo() => throw UnimplementedError();
}

final class _Discovery implements DlnaDiscoverySession {
  new(this.receiver);

  final _Receiver receiver;
  final StreamController<List<DlnaCastDevice>> _devices = StreamController();

  @override
  Stream<List<DlnaCastDevice>> get devices {
    scheduleMicrotask(() => _devices.add([receiver]));
    return _devices.stream;
  }

  @override
  Future<void> stop() => _devices.close();
}

Future<AppServices> _pump(WidgetTester tester, {required FakeDanmaku danmaku}) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => FakeSite(liveRoom())})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return services;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

Future<void> _menu(WidgetTester tester, String entry) async {
  await tester.tap(find.byKey(const ValueKey('live-play-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('room-menu-$entry')));
  await tester.pumpAndSettle();
}

void main() {
  final toasts = <String>[];

  setUp(() {
    toasts.clear();
    AppNavigator.toast = toasts.add;
  });

  testWidgets('menu: the sleep timer starts; a stream address is copied after picking quality and line', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final services = await _pump(tester, danmaku: FakeDanmaku());
    // No FFmpeg in tests: the record button is not offered.
    expect(find.byKey(const ValueKey('live-play-record')), findsNothing);

    await _menu(tester, 'timer');
    expect(find.text('当前直播间播放定时器'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-timer-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-timer-preset-30')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-timer-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-play-menu')));
    await tester.pumpAndSettle();
    expect(find.text('30 分钟后暂停'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-menu-streamLink')));
    await tester.pumpAndSettle();

    expect(find.text('获取直链'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stream-quality-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stream-line-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(copied, 'https://b.example/250.flv');
    expect(toasts, contains('已复制直链'));
    await _close(tester, services);
  });

  testWidgets('cast: the receiver found is listed and gets the chosen address', (tester) async {
    final receiver = _Receiver();
    castDiscovery = () async => _Discovery(receiver);
    final services = await _pump(tester, danmaku: FakeDanmaku());

    await tester.tap(find.byKey(const ValueKey('live-play-cast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stream-quality-0')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stream-line-0')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('客厅电视'), findsOneWidget);

    await tester.tap(find.text('客厅电视'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(receiver.calls, ['source https://a.example/10000.flv', 'play']);
    expect(toasts, contains('已开始投屏'));
    await tester.tap(find.text('关闭'));
    await tester.pump(const Duration(seconds: 1));
    await _close(tester, services);
  });

  testWidgets('gifts show in the chat and the settings tab hides them; audio only shows the cover', (tester) async {
    final danmaku = FakeDanmaku();
    final services = await _pump(tester, danmaku: danmaku);
    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(type: LiveMessageType.gift, userName: '观众', message: '辣条 ×10', color: LiveMessageColor.white),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('live-play-gift-line')), findsOneWidget);
    expect(find.textContaining('辣条 ×10', findRichText: true), findsOneWidget);

    await tester.tap(find.text('弹幕设置'));
    await tester.pumpAndSettle();
    // U.2f: the tab shows the danmaku settings panel's content, templates
    // first ("观看模板"), the chat list's own switches last.
    expect(find.text('观看模板'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('在聊天列表显示礼物'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('live-play-danmaku-settings')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('在聊天列表显示礼物'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => services.store.meta.get('live_play.showGifts')), '0');

    await tester.tap(find.byKey(const ValueKey('live-play-audio-only')));
    await tester.pump();
    // U.2a E5: the cover says "纯音频播放中" (was "纯音频模式"), and 3.x's
    // filled headphone marks the button.
    expect(find.text('纯音频播放中'), findsOneWidget);
    expect(find.byIcon(AppIcons.audioOnlyActive), findsWidgets);
    expect(ChatLineKind.values, contains(ChatLineKind.gift));
    await _close(tester, services);
  });
}
