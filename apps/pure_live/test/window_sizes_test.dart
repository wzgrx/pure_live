import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import 'support.dart';

// A04.1 (docs/A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配; research V03.2
// §3.3 D1, D3, D4): the app at the sizes of phones, a phone's split screen,
// foldables and tablets.

Future<AppServices> _pumpApp(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  double appTextScale = 1,
  List<DisplayFeature> features = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..displayFeatures = features;
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    // The floating-window danmaku preview of the settings stands still.
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.settings.set(Settings.showSplashPage, false);
    await services.store.settings.set(Settings.textScaleFactor, appTextScale);
    return services;
  }))!;
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await _settle(tester);
  return services;
}

/// Lets the store's and the (failing) network's real async work finish,
/// then the frames; a spinner that never stops (a page still loading) does
/// not hold the test up.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 2; round++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    for (var i = 0; i < 30 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _open(WidgetTester tester, String path, {Object? arguments}) async {
  unawaited(AppNavigator.toNamed<void>(path, arguments: arguments));
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  AppNavigator.back<void>();
  await _settle(tester);
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

void main() {
  group('height classes (stage 1)', () {
    testWidgets("a phone's split screen keeps the upright layout: the bottom bar, short app bars", (tester) async {
      final services = await _pumpApp(tester, const Size(400, 420));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('home-rail')), findsNothing);
      for (final page in [RoutePath.kAbout, RoutePath.kToolbox, RoutePath.kSettingsTags, RoutePath.kRecordSettings]) {
        await _open(tester, page);
        expect(tester.getSize(find.byType(AppBar).last).height, compactToolbarHeight, reason: page);
        await _back(tester);
      }
      // Upright and tall: the full app bar.
      tester.view.physicalSize = const Size(400, 869);
      await _settle(tester);
      await _open(tester, RoutePath.kAbout);
      expect(tester.getSize(find.byType(AppBar).last).height, kToolbarHeight);
      await _back(tester);
      // Sideways (821×400) it is a landscape phone: the rail, short app bars.
      tester.view.physicalSize = const Size(821, 400);
      await _settle(tester);
      expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
      await _open(tester, RoutePath.kVersionPage);
      expect(tester.getSize(find.byType(AppBar).last).height, compactToolbarHeight);
      await _back(tester);
      await _close(tester, services);
    });

    testWidgets('a foldable half open like a book: the settings on the two halves, nothing under the fold', (
      tester,
    ) async {
      const fold = DisplayFeature(
        bounds: Rect.fromLTWH(336.5, 0, 0, 841),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      final services = await _pumpApp(tester, const Size(673, 841), features: [fold]);
      await _open(tester, RoutePath.kSettings);
      final overview = tester.getRect(find.byKey(const ValueKey('settings-overview')));
      final pane = tester.getRect(find.byType(SettingsPane));
      expect(overview.right, lessThanOrEqualTo(336.5));
      expect(pane.left, greaterThanOrEqualTo(336.5));
      // Open flat, the fold splits nothing: one page, as before.
      tester.view.displayFeatures = [
        const DisplayFeature(
          bounds: Rect.fromLTWH(336.5, 0, 0, 841),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ];
      await _settle(tester);
      expect(find.byType(SettingsPane), findsNothing);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
      await _close(tester, services);
    });
  });
}
