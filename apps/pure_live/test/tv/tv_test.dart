import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

import '../features/live_play/live_play_support.dart';
import '../support.dart';

/// A platform with [count] recommended rooms that all play.
final class _TvSite extends LiveSite {
  new(this.count);

  final int count;

  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => '哔哩哔哩';

  LiveRoom room(int n) => LiveRoom(
    platform: SiteIds.bilibili,
    roomId: '$n',
    title: '直播 $n',
    nick: '主播$n',
    popularity: '${1000 - n}',
    audienceMetricType: AudienceMetricType.popularity,
    liveStatus: LiveStatus.live,
  );

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var n = 0; n < count; n++) room(n)] : const [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => room(int.parse(roomId));

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async => [
    if (page == 1)
      for (var n = 0; n < count; n++)
        if (room(n).title.contains(keyword)) room(n),
  ];

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '原画', id: 10000),
    LivePlayQuality(quality: '流畅', id: 80),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${detail.roomId}/${quality.id}.flv',
  ];
}

final List<String> _toasts = [];

/// The app on a 1080p panel in [mode] (`uiMode`), on a device that is
/// [television] or not.
Future<AppServices> _pumpApp(WidgetTester tester, {String mode = 'tv', bool television = false, int rooms = 10}) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final base = (await tester.runAsync(testServices))!;
  await tester.runAsync(() async {
    final settings = base.store.settings;
    await settings.set(Settings.showSplashPage, false);
    await settings.set(Settings.enableAutoCheckUpdate, false);
    await settings.set(Settings.hotAreasList, [SiteIds.bilibili]);
    await settings.set(Settings.uiMode, mode);
    await settings.set(Settings.language, '简体中文');
  });
  final site = _TvSite(rooms);
  final services = AppServices(
    store: base.store,
    cipher: base.cipher,
    http: base.http,
    proxy: base.proxy,
    cookies: base.cookies,
    sites: SiteRegistry({SiteIds.bilibili: () => site}),
    danmaku: base.danmaku,
    launch: base.launch,
    dataRoot: base.dataRoot,
    followsReady: base.followsReady,
    mediaOpener: base.mediaOpener,
  );
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        televisionDeviceProvider.overrideWithValue(television),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await _settle(tester);
  AppNavigator.toast = _toasts.add;
  return services;
}

/// Lets the store and the fakes answer (real time) and the frames run.
Future<void> _settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

/// Presses [key] (down and up) and lets the app follow.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, rounds: 2);
}

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  setUp(_toasts.clear);

  test('interface mode: auto follows the device, phone and tv are fixed; rules of the grid', () {
    expect(UiMode.parse('tv'), UiMode.tv);
    expect(UiMode.parse('watch'), UiMode.auto);
    expect(UiMode.auto.showsTv(television: true), isTrue);
    expect(UiMode.auto.showsTv(television: false), isFalse);
    expect(UiMode.phone.showsTv(television: true), isFalse);
    expect(UiMode.tv.showsTv(television: false), isTrue);
    // pure_live_TV: four columns, one fewer up to 130 %, two fewer above.
    expect([1.0, 1.15, 1.3, 1.45, 1.6].map(tvRoomColumns), [4, 3, 3, 2, 2]);
    // A card is its 16:9 cover over two lines (U.15a): at 184 wide on a
    // 1080p television (unit 0.5) the cover is 103.5 high.
    const scale = TvScale(unit: 0.5, textScale: 1);
    expect(TvRoomCard.heightFor(184, scale), closeTo(184 * 9 / 16 + 16 + 42 + 1, 0.01));
    // The settings page has the row.
    expect(settingsCatalog.where((entry) => entry.id == 'ui_mode'), hasLength(1));
  });

  testWidgets('auto shows the TV interface on a television; switching the setting rebuilds at once', (tester) async {
    final services = await _pumpApp(tester, mode: 'auto', television: true);
    expect(find.byType(TvHomePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(MediaQuery.of(tester.element(find.byType(TvHomePage))).navigationMode, NavigationMode.directional);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'phone'));
    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(TvHomePage), findsNothing);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
    await _settle(tester);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('home: the menu, OK into a destination, the grid by index, Left back to the menu', (tester) async {
    final services = await _pumpApp(tester);
    expect(_focused, 'tv menu favorites');
    expect(find.text('还没有关注的直播间，在房间卡片上长按 OK 可以关注'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.select);
    // OK opened the destination and moved into it (the platform tab).
    expect(_focused, 'tab bilibili');
    expect(find.text('直播 0'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 5');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // The last row ends at room 9.
    expect(_focused, 'cell 9');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab bilibili');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 1', reason: 'back into the grid on the card left last');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 0', reason: 'Right enters the destination on its last item');

    // Back steps out: the destination, then the menu, then a hint to leave.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'tv menu popular');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_toasts, ['再按一次返回键退出']);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('room: OK opens it full screen; Up/Down switch; OK shows controls; Back returns to the card', (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final room = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    expect(room.index, 1);
    expect(room.playlist, hasLength(10));
    expect(room.controller!.room.roomId, '1');
    // D05.2: the picture's danmaku follow "同屏最大弹幕条数" (48 by default).
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 48);
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuMaxVisibleCount, 30));
    await _settle(tester);
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 30);

    // Two presses inside the window: one switch of two rooms.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(room.index, 3);
    expect(room.controller!.room.roomId, '3');
    expect(find.byKey(const ValueKey('tv-room-banner')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, rounds: 10);
    expect(room.index, 2);
    expect(room.controller!.stage, RoomStage.playing);
    // History records the rooms shown.
    final history = (await tester.runAsync(services.store.history.all))!;
    expect(history.map((room) => room.roomId), containsAll(['1', '2', '3']));

    // OK: the controls, focus on the first button; Back hides them.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsOneWidget);
    expect(find.text('画质 原画'), findsOneWidget);
    expect(_focused, 'tv room first control');
    // Left and Right walk the buttons; Up/Down still switch rooms.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<TvLivePlayPage>()));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsNothing);

    // Right: the room list with the room shown; OK on another switches.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsOneWidget);
    expect(_focused, 'tv room list current');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(room.index, 3);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsNothing);

    // Back leaves; the grid's focus lands on the room shown last.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.byType(TvLivePlayPage), findsNothing);
    expect(_focused, 'cell 3');
    await _close(tester, services);
  });

  testWidgets('a held OK opens the card dialog instead of the room; the menu key too', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    expect(find.byType(TvLivePlayPage), findsNothing);
    // The dialog took the focus (no arrow needed): "设置标签" (U.15a c9).
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Dialog>(), isNotNull);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key,
      const ValueKey('tv-room-dialog-tags'),
    );

    await _press(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsNothing);
    expect(_focused, 'cell 0');

    // The remote's menu key is the same as a held OK (U.15a c10).
    await _press(tester, LogicalKeyboardKey.contextMenu);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'cell 0');
    await _close(tester, services);
  });

  testWidgets('search: OK on the field types through the input, results in a grid, Back to the history', (
    tester,
  ) async {
    final asked = <String>[];
    TvTextInput.prompt =
        (context, {required title, hint = '', text = '', subtitle, numeric = false, suffix, maxLength}) async {
          asked.add(title);
          return ' 直播 7 ';
        };
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final services = await _pumpApp(tester);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu search');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('按 OK 打开输入框，用遥控器或语音输入要找的内容'), findsOneWidget);
    expect(_focused, 'tv search field');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(asked, ['搜索直播间、主播或房间号']);
    expect(find.text('直播 7'), findsWidgets);
    expect(find.text('主播7'), findsOneWidget);

    // Back: from the results to the field, the word kept in the history.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-search-word-直播 7')), findsOneWidget);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('TV settings: OK opens the choices on the current value; picking phone switches', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu settings');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-setting-ui_mode')), findsOneWidget);
    // The first row has the focus; OK opens the choices with the focus on
    // the current one (tv), Up moves to phone, OK picks it (U.15a row 13).
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>()?.key,
      const ValueKey('tv-choice-2'),
    );
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(services.store.settings.get(Settings.uiMode), 'phone');
    expect(find.byType(HomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('a focusable: OK taps at once without a long press; with one, a hold never also taps', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TvFocusable(autofocus: true, onTap: () => taps++, builder: (_, _) => const Text('plain')),
            TvFocusable(onTap: () => taps++, onLongPress: () => holds++, builder: (_, _) => const Text('card')),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect((taps, holds), (2, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect((taps, holds), (2, 1));
  });
}
