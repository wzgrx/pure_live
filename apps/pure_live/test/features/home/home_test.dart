import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/images.dart';

import '../../support.dart';

Future<AppServices> _pump(
  WidgetTester tester, {
  required double width,
  double height = 900,
  List<String>? menus,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
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
        // U.2k: the local interaction settings (3.x pushed the page directly).
        RoutePath.kLocalInteraction,
        // U.11a: the log page moved out of the backup page (3.x) into settings.
        RoutePath.kLogs,
      },
    );
  });

  test('menus: saved order, unknown and repeated ids dropped, the same on the bar and the rail', () {
    expect(HomeMenu.fromIds(['areas', 'bogus', 'favorites', 'areas']), [HomeMenu.areas, HomeMenu.favorites]);
    // U.3b c3: the recording centre is a destination on the rail too.
    expect(visibleHomeMenus(['record', 'popular']), [HomeMenu.record, HomeMenu.popular]);
    // Nothing usable saved: every destination (3.x showed an empty page).
    expect(visibleHomeMenus(['bogus']), HomeMenu.values);
  });

  testWidgets('phone: bottom bar of the saved menus; follows again refreshes them', (tester) async {
    final services = await _pump(tester, width: 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.widgetWithText(AppBar, '已开播'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '热门'));
    await tester.pumpAndSettle();
    // U.4b: the popular page's title place holds its platform tabs (3.x).
    expect(find.byType(PopularPage), findsOneWidget);

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
    // U.4b: the popular page's title place holds its platform tabs (3.x).
    expect(find.byType(PopularPage), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('phone bar: menu at the left; search and more at the right, in this order (U.3a c4)', (tester) async {
    final services = await _pump(tester, width: 393);
    final bar = find.widgetWithText(AppBar, '已开播');
    final menu = find.descendant(of: bar, matching: find.byTooltip('菜单'));
    final search = find.descendant(of: bar, matching: find.byTooltip('搜索直播'));
    final more = find.descendant(of: bar, matching: find.byTooltip('更多'));
    expect(menu, findsOneWidget);
    expect(search, findsOneWidget);
    expect(more, findsOneWidget);
    expect(find.descendant(of: menu, matching: find.byIcon(AppIcons.appMenu)), findsOneWidget);
    expect(find.descendant(of: search, matching: find.byIcon(AppIcons.search)), findsOneWidget);
    expect(find.descendant(of: more, matching: find.byIcon(AppIcons.more)), findsOneWidget);
    // 3.x's menu-and-magnifier button is gone.
    expect(find.byIcon(Remix.menu_search_line), findsNothing);
    expect(tester.getCenter(menu).dx, lessThan(60));
    expect(tester.getCenter(search).dx, lessThan(tester.getCenter(more).dx));
    expect(tester.getRect(more).right, greaterThan(380));
    // Touch targets of at least 48.
    for (final button in [menu, search, more]) {
      final target = find.ancestor(of: button, matching: find.byType(IconButton)).first;
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }

    // Search is one tap.
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(liveRouteObserver.currentRoute.value, RoutePath.kSearch);
    AppNavigator.back();
    await tester.pumpAndSettle();
    await tester.runAsync(services.close);
  });

  testWidgets('phone bottom bar: four destinations, their order and icons; areas has the shapes (U.3a c7)', (
    tester,
  ) async {
    final services = await _pump(tester, width: 393);
    final ids = ['favorites', 'popular', 'areas', 'record'];
    final rects = [for (final id in ids) tester.getRect(find.byKey(ValueKey('home-nav-$id')))];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left));
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-nav-favorites')),
        matching: find.byIcon(AppIcons.homeFavoritesSelected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('home-nav-areas')), matching: find.byIcon(Remix.shapes_line)),
      findsOneWidget,
    );
    expect(find.byIcon(Remix.apps_2_line), findsNothing);
    expect(
      find.descendant(of: find.byKey(const ValueKey('home-nav-record')), matching: find.byIcon(Remix.download_2_line)),
      findsOneWidget,
    );
    await tester.runAsync(services.close);
  });

  testWidgets(
    'phone menus: the same small menu; settings, about, backup at the left, history, link, multi-view in more',
    (tester) async {
      final services = await _pump(tester, width: 393);
      final scheme = Theme.of(tester.element(find.byType(HomePage))).colorScheme;
      final bar = find.widgetWithText(AppBar, '已开播');

      Future<void> checkMenu(Finder button, List<(String, String, IconData)> rows, {required bool right}) async {
        await tester.tap(button);
        await tester.pumpAndSettle();
        final buttonRect = tester.getRect(find.ancestor(of: button, matching: find.byType(IconButton)).first);
        double? top;
        for (final (key, label, icon) in rows) {
          final row = find.byKey(ValueKey(key));
          expect(row, findsOneWidget, reason: label);
          final rect = tester.getRect(row);
          expect(rect.height, 48, reason: label);
          if (top != null) expect(rect.top, greaterThan(top), reason: label);
          top = rect.top;
          final text = tester.widget<Text>(find.descendant(of: row, matching: find.text(label)));
          expect(text.style?.fontSize, 14, reason: label);
          final iconWidget = tester.widget<Icon>(find.descendant(of: row, matching: find.byIcon(icon)));
          expect(iconWidget.size, 24, reason: label);
          expect(iconWidget.color, scheme.onSurfaceVariant, reason: label);
          // Next to the button, below it.
          expect(rect.top, greaterThan(buttonRect.bottom), reason: label);
          // Lined up with the button, but Material keeps menus 8 from the
          // screen's edge.
          if (right) {
            expect(rect.right, closeTo(math.min(buttonRect.right, 393 - 8), 1), reason: label);
          } else {
            expect(rect.left, closeTo(math.max(buttonRect.left, 8), 1), reason: label);
          }
        }
        final menuMaterial = tester.widget<Material>(
          find.ancestor(of: find.byKey(ValueKey(rows.first.$1)), matching: find.byType(Material)).first,
        );
        expect(menuMaterial.color, scheme.surfaceContainerHighest);
        expect((menuMaterial.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
        await tester.tapAt(const Offset(200, 600));
        await tester.pumpAndSettle();
      }

      await checkMenu(find.descendant(of: bar, matching: find.byTooltip('菜单')), [
        ('home-menu-settings', '设置', AppIcons.settings),
        ('home-menu-about', '关于', AppIcons.about),
        ('home-menu-backup', '备份与恢复', AppIcons.backup),
      ], right: false);
      // The watch history moved to "more" (U.3a c3) and is called 观看记录 (U.5c).
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('菜单')));
      await tester.pumpAndSettle();
      expect(find.text('历史记录'), findsNothing);
      expect(find.text('观看记录'), findsNothing);
      await tester.tapAt(const Offset(200, 600));
      await tester.pumpAndSettle();

      await checkMenu(find.descendant(of: bar, matching: find.byTooltip('更多')), [
        ('home-more-history', '观看记录', AppIcons.watchHistory),
        ('home-more-openLink', '链接解析', AppIcons.openLink),
        ('home-more-multiview', '多画面', AppIcons.multiview),
      ], right: true);
      expect(find.text('链接访问'), findsNothing);

      // Multi-view off: two rows.
      await tester.runAsync(() => services.store.settings.set(Settings.enableMultiView, false));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('更多')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-more-multiview')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-more-history')));
      await tester.pumpAndSettle();
      expect(liveRouteObserver.currentRoute.value, RoutePath.kHistory);
      AppNavigator.back();
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('菜单')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-menu-about')));
      await tester.pumpAndSettle();
      expect(liveRouteObserver.currentRoute.value, RoutePath.kAbout);
      AppNavigator.back();
      await tester.pumpAndSettle();
      await tester.runAsync(services.close);
    },
  );

  test('the app menu: Windows with the setting adds the independent window last', () {
    expect(appMenuItems(newWindow: false), [AppMenuItem.settings, AppMenuItem.about, AppMenuItem.backup]);
    expect(appMenuItems(newWindow: true).last, AppMenuItem.newWindow);
    expect(AppMenuItem.newWindow.icon, AppIcons.newPlayerWindow);
    expect(homeActions(multiView: true), HomeAction.values);
    expect(homeActions(multiView: false), [HomeAction.search, HomeAction.history, HomeAction.openLink]);
  });

  testWidgets('phone recording tab: folder and settings, then search and more (U.3a c6)', (tester) async {
    final services = await _pump(tester, width: 393);
    await tester.tap(find.byKey(const ValueKey('home-nav-record')));
    await tester.pumpAndSettle();
    final bar = find.widgetWithText(AppBar, '录制中心');
    expect(find.descendant(of: bar, matching: find.byTooltip('菜单')), findsOneWidget);
    final settings = tester.getCenter(
      find.descendant(of: bar, matching: find.byKey(const ValueKey('recorder-settings'))),
    );
    final search = tester.getCenter(find.descendant(of: bar, matching: find.byTooltip('搜索直播')));
    final more = tester.getCenter(find.descendant(of: bar, matching: find.byTooltip('更多')));
    expect(settings.dx, lessThan(search.dx));
    expect(search.dx, lessThan(more.dx));
    await tester.runAsync(services.close);
  });

  testWidgets('rail from 600: menu, four tools with names, a line, then the four destinations (U.3b)', (tester) async {
    final services = await _pump(tester, width: 1280, height: 800);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // The page bars have no menu buttons on the rail (3.x).
    expect(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('更多')), findsNothing);
    final rail = find.byKey(const ValueKey('home-rail'));
    expect(tester.getSize(rail).width, 80);
    final order = [
      'home-menu',
      'home-rail-search',
      'home-rail-history',
      'home-rail-openLink',
      'home-rail-multiview',
      'home-rail-separator',
      'home-nav-favorites',
      'home-nav-popular',
      'home-nav-areas',
      'home-nav-record',
    ];
    final tops = [for (final key in order) tester.getRect(find.byKey(ValueKey(key))).top];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
    }
    // Tools carry their names under the icons (U.3b c2), same icons as the phone.
    for (final (key, label, icon) in [
      ('home-rail-search', '搜索直播', AppIcons.search),
      ('home-rail-history', '观看记录', AppIcons.watchHistory),
      ('home-rail-openLink', '链接解析', AppIcons.openLink),
      ('home-rail-multiview', '多画面', AppIcons.multiview),
    ]) {
      final tool = find.byKey(ValueKey(key));
      expect(find.descendant(of: tool, matching: find.text(label)), findsOneWidget);
      expect(
        tester.getCenter(find.descendant(of: tool, matching: find.text(label))).dy,
        greaterThan(tester.getCenter(find.descendant(of: tool, matching: find.byIcon(icon))).dy),
      );
    }
    expect(find.descendant(of: rail, matching: find.byIcon(Remix.shapes_line)), findsOneWidget);

    // The recording centre is a destination: the rail stays, no page is pushed.
    await tester.tap(find.byKey(const ValueKey('home-nav-record')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '录制中心'), findsOneWidget);
    expect(rail, findsOneWidget);
    expect(liveRouteObserver.currentRoute.value, RoutePath.kInitial);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(BackButton)), findsNothing);

    // The rail's menu is the same small menu.
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-menu-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-menu-backup')), findsOneWidget);
    await tester.tapAt(const Offset(600, 600));
    await tester.pumpAndSettle();

    // A rail tool opens its page.
    await tester.tap(find.byKey(const ValueKey('home-rail-history')));
    await tester.pumpAndSettle();
    expect(liveRouteObserver.currentRoute.value, RoutePath.kHistory);
    AppNavigator.back();
    await tester.pumpAndSettle();

    // Only the recording centre saved: one destination, never an empty page.
    await tester.runAsync(() => services.store.settings.set(Settings.savedMenuIds, ['record']));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-nav-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-favorites')), findsNothing);
    expect(find.text('尚未选择任何菜单'), findsNothing);
    await tester.runAsync(services.close);
  });

  testWidgets('the rail starts at 600 wide (U.3b c6; 3.x: above 680)', (tester) async {
    var services = await _pump(tester, width: 600);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());

    services = await _pump(tester, width: 599);
    expect(find.byKey(const ValueKey('home-rail')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('landscape phone: the destinations stay on screen, the tools above them scroll (U.4b)', (tester) async {
    final services = await _pump(tester, width: 852, height: 393);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    for (final id in ['favorites', 'popular', 'areas', 'record']) {
      final rect = tester.getRect(find.byKey(ValueKey('home-nav-$id')));
      expect(rect.bottom, lessThanOrEqualTo(393), reason: id);
      expect(rect.top, greaterThanOrEqualTo(0), reason: id);
    }
    expect(tester.getRect(find.byKey(const ValueKey('home-menu'))).top, greaterThanOrEqualTo(0));
    // The tools scroll to the multi-view button.
    final multiview = find.byKey(const ValueKey('home-rail-multiview'));
    await tester.ensureVisible(multiview);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(multiview).bottom,
      lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('home-rail-separator'))).top),
    );
    await tester.runAsync(services.close);
  });

  testWidgets('a larger system font: bar, menus and rail do not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var services = await _pump(tester, width: 1280, height: 800);
    expect(tester.takeException(), isNull);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());
    services = await _pump(tester, width: 393);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(200, 600));
    await tester.pumpAndSettle();
    await tester.runAsync(services.close);
  });

  testWidgets('crossing the rail width keeps the page (its state is not rebuilt)', (tester) async {
    final services = await _pump(tester, width: 393);
    final before = tester.state(find.byType(FavoritePage));
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(tester.state(find.byType(FavoritePage)), same(before));
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
