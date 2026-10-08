import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import 'support.dart';

// A04.1 (docs/A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配; research V03.2
// §3.3 D1, D3, D4): the app at the sizes of phones, a phone's split screen,
// foldables and tablets.

/// The sizes of the research's D1, in logical pixels.
const List<Size> _sizes = [
  Size(360, 400), // a small free window
  Size(400, 420), // a phone's split screen
  Size(400, 869), // K90 upright
  Size(821, 400), // K90 sideways, less the camera hole
  Size(673, 841), // a foldable's inner screen
  Size(841, 673), // the same, sideways
  Size(1280, 800), // a tablet
  Size(1500, 1000), // a large tablet
];

const List<double> _textScales = [1.3, 1.5, 2];

/// The pages opened on top of the home (whose follows are the first page):
/// its other destinations, the tools and the settings-like pages. Not the
/// live room (its own layout tests, live_play_layouts_test.dart).
const List<String> _pages = [
  RoutePath.kPopular,
  RoutePath.kAreas,
  RoutePath.kRecordPage,
  RoutePath.kSearch,
  RoutePath.kHistory,
  RoutePath.kMultiview,
  RoutePath.kSettings,
  RoutePath.kAbout,
  RoutePath.kToolbox,
  RoutePath.kVersionPage,
  RoutePath.kVersionHistory,
  RoutePath.kSettingsTags,
  RoutePath.kSettingsDanmuShield,
  RoutePath.kSettingsAccount,
  RoutePath.kSettingsHotAreas,
  RoutePath.kBackup,
  RoutePath.kIptv,
  RoutePath.kRecordSettings,
  RoutePath.kRemoteSync,
  RoutePath.kWebDavPage,
  RoutePath.kLogs,
];

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
  group('text size (stage 2)', () {
    // D1: every page at every size with the system text 1.3, 1.5 and 2
    // times as large (2 is the most it gets, the app's factor included),
    // without an overflow.
    for (final size in _sizes) {
      final name = '${size.width.toInt()}×${size.height.toInt()}';
      testWidgets('$name: the main pages and every settings page fit at 1.3, 1.5 and 2× text', (tester) async {
        final services = await _pumpApp(tester, size, textScale: _textScales.first);
        final problems = <String>[];
        // Where an overflow was laid out, for the message.
        final where = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final match = RegExp(r'file:///\S+/lib/(\S+)').firstMatch(details.toString());
          where.add(match?.group(1) ?? details.exceptionAsString().split('\n').first);
          original?.call(details);
        };
        addTearDown(() => FlutterError.onError = original);
        for (final scale in _textScales) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await _settle(tester);
          void fits(String page) {
            if (tester.takeException() case final problem?) problems.add('$page ×$scale: $problem $where');
            where.clear();
          }

          fits('home');
          for (final page in _pages) {
            await _open(tester, page);
            fits(page);
            await _back(tester);
          }
          for (final section in SettingsSection.values.where((section) => section.route == null)) {
            await _open(tester, RoutePath.kSettings, arguments: section.name);
            fits('settings ${section.name}');
            await _back(tester);
          }
        }
        FlutterError.onError = original;
        await _close(tester, services);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }

    testWidgets('the system text 2× and the app text 2× make text 2×, not 4× (D3)', (tester) async {
      final services = await _pumpApp(tester, const Size(400, 869), textScale: 2, appTextScale: 2);
      await _open(tester, RoutePath.kAbout);
      final scaler = MediaQuery.textScalerOf(tester.element(find.byKey(const ValueKey('about-version'))));
      expect(scaler.scale(14), 28);
      expect(tester.takeException(), isNull);
      await _close(tester, services);
      // Below the limit both still count: 1.3 × 1.5.
      final again = await _pumpApp(tester, const Size(400, 869), textScale: 1.3, appTextScale: 1.5);
      expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)).scale(10), closeTo(19.5, 1e-9));
      await _close(tester, again);
    });
  });
}
