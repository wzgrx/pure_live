import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/splash/splash_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

Future<void> _pump(WidgetTester tester) async {
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
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(strings: strings.ui),
      child: MaterialApp.router(
        theme: const LiveTheme(primaryColor: Colors.blue).light,
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

  testWidgets('a tap skips the wait', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('splash')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
