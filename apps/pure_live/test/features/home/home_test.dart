import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/images.dart';

import '../../support.dart';

Future<AppServices> _pump(WidgetTester tester, {required double width, List<String>? menus}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.settings.set(Settings.showSplashPage, false);
    if (menus != null) await services.store.settings.set(Settings.savedMenuIds, menus);
    return services;
  }))!;
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

void main() {
  test("every page 3.x registered has a route, each built by its page folder's class", () {
    expect(
      {RoutePath.kInitial, ...pageRoutes.keys},
      {
        RoutePath.kInitial, RoutePath.kSignIn, RoutePath.kMine, RoutePath.kUserManage, RoutePath.kFavorite, //
        RoutePath.kPopular, RoutePath.kAreas, RoutePath.kSettings, RoutePath.kHistory, RoutePath.kSearch,
        RoutePath.kBackup, RoutePath.kIptv, RoutePath.kAbout, RoutePath.kAreaRooms, RoutePath.kLivePlay,
        RoutePath.kMultiview, RoutePath.kSettingsAccount, RoutePath.kBiliBiliWebLogin, RoutePath.kBiliBiliQRLogin,
        RoutePath.kSettingsDanmuShield, RoutePath.kSettingsHotAreas, RoutePath.kVersionHistory, RoutePath.kToolbox,
        RoutePath.kFavoriteAreas, RoutePath.kHuyaCookie, RoutePath.kDouyuAccountCookie, RoutePath.kDouyinCookie,
        RoutePath.kDouyuCookie, RoutePath.kTwitchCookie, RoutePath.kYyCookie, RoutePath.kSoop,
        RoutePath.kKuaishouCookie, RoutePath.kWebDavPage, RoutePath.kSplash, RoutePath.kVersionPage,
        RoutePath.kRecordPage, RoutePath.kRecordSettings, RoutePath.kWebSearch, RoutePath.kSettingsTags,
        RoutePath.kRemoteSync,
      },
    );
  });

  test('menus: saved order, unknown and repeated ids dropped, no recording centre on the rail', () {
    expect(HomeMenu.fromIds(['areas', 'bogus', 'favorites', 'areas']), [HomeMenu.areas, HomeMenu.favorites]);
    expect(visibleHomeMenus(['record', 'popular'], tablet: true), [HomeMenu.popular]);
    expect(visibleHomeMenus(['record', 'popular'], tablet: false), [HomeMenu.record, HomeMenu.popular]);
  });

  testWidgets('phone: bottom bar of the saved menus; follows again refreshes them', (tester) async {
    final services = await _pump(tester, width: 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.widgetWithText(AppBar, '已开播'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '热门'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '热门'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '关注'));
    await tester.pumpAndSettle();
    final before = HomeSignals.favoritesReselected.value;
    await tester.tap(find.widgetWithText(NavigationDestination, '关注'));
    await tester.pumpAndSettle();
    expect(HomeSignals.favoritesReselected.value, before + 1);

    // One destination: no bar (3.x).
    await tester.runAsync(() => services.store.settings.set(Settings.savedMenuIds, ['popular']));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(AppBar, '热门'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('tablet: side rail without the recording centre, which becomes an action', (tester) async {
    final services = await _pump(tester, width: 1000);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(3));
    expect(find.byTooltip('录制中心'), findsOneWidget);
    expect(find.byTooltip('搜索直播'), findsOneWidget);

    await tester.runAsync(() => services.store.settings.set(Settings.savedMenuIds, <String>[]));
    await tester.pumpAndSettle();
    expect(find.text('尚未选择任何菜单'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('a live room opens with its room; a retired platform is refused', (tester) async {
    final services = await _pump(tester, width: 400);
    final toasts = <String>[];
    AppNavigator.toast = toasts.add;

    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'huajiao', roomId: 'x'),
    );
    await tester.pumpAndSettle();
    expect(toasts.single, contains('下线'));
    expect(find.byType(LivePlayPage), findsNothing);

    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'Bilibili', roomId: '23030429', nick: '主播'),
    );
    // A second tap while the room comes in is ignored (3.x).
    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'huya', roomId: '1'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LivePlayPage), findsOneWidget);
    expect(find.text('主播'), findsWidgets);

    AppNavigator.back();
    await tester.pumpAndSettle();
    expect(find.byType(LivePlayPage), findsNothing);
    await tester.pump(AppNavigator.openGuard);
    await tester.runAsync(services.close);
  });

  testWidgets('splash first when it is on, then home; start-up work and image settings are wired', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    );
    await tester.pump();
    expect(find.text('欢迎使用'), findsOneWidget);
    // The follow check starts after the first frame; the splash waits for it.
    expect(AppStartup.followCheck, isNotNull);
    final config = LiveUiScope.of(tester.element(find.text('欢迎使用')));
    expect(config.imageHeaders?.call('https://i0.hdslb.com/a.jpg')?['Referer'], 'https://live.bilibili.com/');
    expect(config.imageHeaders?.call('https://img.example.com/a.jpg')?.containsKey('Referer'), isFalse);
    final epoch = config.imageCacheEpoch;
    imageCacheEpoch.value++;
    await tester.pump();
    expect(LiveUiScope.of(tester.element(find.text('欢迎使用'))).imageCacheEpoch, epoch + 1);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用'), findsNothing);
    expect(find.widgetWithText(AppBar, '已开播'), findsOneWidget);
    // The update check after two seconds stays quiet without a network.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}
