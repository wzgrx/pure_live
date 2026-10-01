// The settings page over an in-memory store, shared by the settings tests.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// What a test reads back: the services, the toasts, the routes opened.
final class SettingsHarness {
  /// Creates the harness.
  new(this.services, this.toasts, this.opened);

  /// The services.
  final AppServices services;

  /// The toasts shown.
  final List<String> toasts;

  /// The routes opened.
  final List<String> opened;

  /// The settings.
  SettingsStore get settings => services.store.settings;
}

/// Pumps the settings page over an in-memory store at [width] × [height];
/// other routes show their path (so links can be checked).
Future<SettingsHarness> pumpSettings(
  WidgetTester tester, {
  double width = 400,
  double height = 1600,
  Object? arguments,
  Future<void> Function(SettingsStore settings)? seed,
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The floating-window danmaku preview stands still (as with the system's
  // "remove animations"), so frames settle.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await seed?.call(services.store.settings);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  addTearDown(AutoExitTimer.instance.detach);
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final opened = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => SettingsPage(route: RouteArgs(RoutePath.kSettings, arguments: arguments)),
      ),
      for (final path in [
        RoutePath.kSettingsDanmuShield,
        RoutePath.kSettingsAccount,
        RoutePath.kBackup,
        RoutePath.kIptv,
        RoutePath.kRecordSettings,
        RoutePath.kSettingsHotAreas,
        RoutePath.kSettingsTags,
      ])
        GoRoute(
          path: path,
          builder: (_, _) {
            opened.add(path);
            return Scaffold(body: Text('page $path'));
          },
        ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services), ...overrides],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await settleSettings(tester);
  return SettingsHarness(services, toasts, opened);
}

/// Lets the store's writes (real async work) finish, then the frames.
Future<void> settleSettings(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

/// The row of a catalogue entry.
Finder settingsRow(String id) => find.byKey(ValueKey('settings-entry-$id'));

/// The overview row of a page.
Finder settingsSection(SettingsSection section) => find.byKey(ValueKey('settings-section-${section.name}'));

/// Taps [finder] after scrolling it into view, then settles.
Future<void> tapSettings(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await settleSettings(tester);
}

/// Types a search.
Future<void> searchSettingsFor(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('settings-search')), text);
  // The search waits for a pause in typing.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The top of [finder].
double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// [finders] from top to bottom.
void expectInOrder(WidgetTester tester, List<Finder> finders) {
  for (var i = 1; i < finders.length; i++) {
    expect(topOf(tester, finders[i]), greaterThan(topOf(tester, finders[i - 1])), reason: '$i');
  }
}

/// Runs [body] as if on [platform].
Future<void> withPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
