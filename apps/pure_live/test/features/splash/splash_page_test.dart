import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/splash/splash_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

Future<void> _pump(WidgetTester tester, {bool dark = false, Size size = const Size(393, 852)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final strings = (await tester.runAsync(loadStrings))!;
  final router = GoRouter(
    initialLocation: RoutePath.kSplash,
    routes: [
      GoRoute(
        path: RoutePath.kInitial,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: RoutePath.kSplash,
        builder: (_, _) => const SplashPage(route: RouteArgs(RoutePath.kSplash)),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  const theme = LiveTheme(primaryColor: Colors.blue);
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(strings: strings.ui),
      child: MaterialApp.router(
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('starts on the splash page only with the setting on', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    expect(splashInitialLocation(store.settings), RoutePath.kSplash);
    await store.settings.set(Settings.showSplashPage, false);
    expect(splashInitialLocation(store.settings), RoutePath.kInitial);
  });

  testWidgets('shows the welcome and goes home after a second', (tester) async {
    await _pump(tester);
    expect(find.text('欢迎使用'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('home'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('A06.5 c2: see-through system bars, icons for the theme (no black navigation bar)', (tester) async {
    for (final dark in [false, true]) {
      await _pump(tester, dark: dark);
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byWidgetPredicate((widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      final style = region.value;
      final icons = dark ? Brightness.light : Brightness.dark;
      expect(style.systemNavigationBarColor, const Color(0x00000000), reason: 'dark $dark');
      expect(style.systemNavigationBarDividerColor, const Color(0x00000000), reason: 'dark $dark');
      expect(style.systemNavigationBarIconBrightness, icons, reason: 'dark $dark');
      expect(style.statusBarColor, const Color(0x00000000), reason: 'dark $dark');
      expect(style.statusBarIconBrightness, icons, reason: 'dark $dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a tap skips the wait', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('splash')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('any key skips the wait (computers, U.3c)', (tester) async {
    await _pump(tester, size: const Size(1280, 800));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the icon and the text are whole after 0.4 s, without overshoot (U.3c c2)', (tester) async {
    await _pump(tester);
    final fade = find.ancestor(of: find.byKey(const ValueKey('splash-logo')), matching: find.byType(FadeTransition));
    final scale = find.ancestor(of: find.byKey(const ValueKey('splash-logo')), matching: find.byType(ScaleTransition));
    var opacity = 0.0;
    var size = 0.9;
    for (var ms = 50; ms <= 400; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      final o = tester.widget<FadeTransition>(fade.first).opacity.value;
      final s = tester.widget<ScaleTransition>(scale.first).scale.value;
      expect(o, greaterThanOrEqualTo(opacity));
      expect(s, lessThanOrEqualTo(1));
      expect(s, greaterThanOrEqualTo(size));
      opacity = o;
      size = s;
    }
    expect(opacity, 1);
    expect(size, 1);
    // Leaving after a second shows them whole (3.x: a third of the way in).
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
  });

  testWidgets('layout: icon 150, the text 16 under it, the bar 200 wide 32 under the text (U.3c c4, c5)', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pump(SplashPage.animation);
    final logo = tester.getRect(find.byKey(const ValueKey('splash-logo')));
    final text = tester.getRect(find.text('欢迎使用'));
    final bar = tester.getRect(find.byKey(const ValueKey('splash-progress')));
    expect(logo.size, const Size(150, 150));
    expect(text.top - logo.bottom, closeTo(16, 0.5));
    expect(bar.width, 200);
    expect(bar.top - text.bottom, closeTo(32, 0.5));
    expect(logo.center.dx, closeTo(393 / 2, 0.5));
    // 3.x had only the welcome; v4's extra app name is gone.
    expect(find.text('纯粹直播'), findsNothing);
    final scheme = Theme.of(tester.element(find.text('欢迎使用'))).colorScheme;
    final progress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.color, scheme.primary);
    expect(progress.backgroundColor, scheme.primary.withValues(alpha: 0.15));
    expect(tester.widget<Text>(find.text('欢迎使用')).style?.fontWeight, FontWeight.w600);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  for (final dark in [false, true]) {
    testWidgets('the background follows the theme (${dark ? 'dark' : 'light'}, U.3c c3)', (tester) async {
      await _pump(tester, dark: dark);
      final scheme = Theme.of(tester.element(find.text('欢迎使用'))).colorScheme;
      expect(scheme.brightness, dark ? Brightness.dark : Brightness.light);
      final box = tester.widget<DecoratedBox>(find.byKey(const ValueKey('splash-background')));
      final gradient = (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, scheme.surface);
      expect(
        gradient.colors.last,
        Color.alphaBlend(scheme.primaryContainer.withValues(alpha: dark ? 0.45 : 0.7), scheme.surface),
      );
      // No fixed cyan of 3.x.
      expect(gradient.colors, isNot(contains(const Color(0xFF80DEEA))));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
  }
}
