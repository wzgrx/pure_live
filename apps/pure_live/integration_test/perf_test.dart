// Frame benchmarks of UI_PLAN §9.4 (P05; research 2026-10-02 §4.3 item 3):
// the hot list flung fast, 50 and 200 danmaku a second in a room, four
// multi-view cells, the settings flung, a room opened and closed 20 times,
// and the covers' rounded corners three ways (P4). Each run's build and
// raster P90/P99 and janky frames go to the report as JSON, with research
// §4.1's marks; a run fails only when the app breaks, not on slow frames.
//
// On a phone, in profile mode (docs/cloud/records/P05.md):
//   flutter drive --profile -d <device> \
//     --driver=integration_test/perf_driver.dart \
//     --target=integration_test/perf_test.dart
// The driver writes build/perf/perf-<time>.json. Headless, to check that it
// runs (debug mode, and the tester drops the raster of a view resized to a
// phone's, so the figures mean nothing there):
//   flutter test integration_test/perf_test.dart -d flutter-tester \
//     --dart-define=PERF_QUICK=true
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import 'perf/bench_app.dart';
import 'perf/frame_report.dart';
import 'perf/frame_requests.dart';

/// How long the steady scenarios run.
const Duration _window = perfQuick ? Duration(seconds: 3) : Duration(seconds: 10);

/// Flings each way.
const int _flings = perfQuick ? 3 : 12;

/// Rooms opened and closed.
const int _visits = perfQuick ? 3 : 20;

/// The pause after a fling: long enough for most of the glide.
const Duration _glide = Duration(milliseconds: 900);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final requests = FrameRequests.install();
  final scenarios = <String, Object?>{};
  final summaries = <String>[];
  late BenchEnvironment environment;
  Map<String, Object?>? device;

  setUpAll(() async => environment = await BenchEnvironment.start());

  setUp(() {
    // Frames come when the engine and the app ask, as in the app; the test's
    // pumps only wait (Flutter's policy for benchmarks on a device).
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  });

  tearDownAll(() async {
    await environment.close();
    for (final line in summaries) {
      debugPrint('perf: $line');
    }
    // A phone's report goes to the driver; elsewhere it is written here.
    if (!Platform.isAndroid) {
      final file = File('build/perf/perf-${Platform.operatingSystem}.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(binding.reportData));
      debugPrint('perf: wrote ${file.absolute.path}');
    }
  });

  /// Lays the app out as the K90 in portrait (400×869 at 3×) where the view
  /// is not a phone's.
  void phoneView(WidgetTester tester) {
    if (Platform.isAndroid) return;
    tester.view
      ..physicalSize = const Size(1200, 2607)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Records the frames of [action] as scenario [name].
  Future<FrameReport> measure(
    WidgetTester tester,
    String name,
    Future<Map<String, Object?>> Function() action, {
    double rasterShare = 1,
    double? buildLimitMs,
  }) async {
    final recorder = FrameRecorder(requested: requests.frames)..start();
    final extra = await action();
    final recorded = await recorder.stop();
    final report = FrameReport.fromTimings(
      name,
      recorded.frames,
      refreshRate: refreshRateOf(tester.view),
      rasterShare: rasterShare,
      buildLimitMs: buildLimitMs,
      extra: {...extra, 'idleFramesLeftOut': recorded.idleLeftOut},
    );
    device ??= environment.deviceJson(tester.view);
    scenarios[name] = report.toJson();
    binding.reportData = {'device': device, 'scenarios': scenarios};
    summaries.add(report.summary);
    debugPrint('perf: ${report.summary}');
    return report;
  }

  /// Flings [target] [count] times up the screen, then as many back down.
  Future<void> flingBothWays(WidgetTester tester, Finder target, int count) async {
    for (final offset in [const Offset(0, -700), const Offset(0, 700)]) {
      for (var i = 0; i < count; i++) {
        await tester.fling(target, offset, 5000, warnIfMissed: false);
        await idle(tester, _glide);
      }
    }
  }

  testWidgets('hot list: fast flings down 300 rooms and back up', (tester) async {
    phoneView(tester);
    final app = await BenchApp.pump(tester, environment);
    final grid = find.byKey(const ValueKey('popular-grid'));
    await measure(tester, 'hot_scroll', () async {
      await flingBothWays(tester, grid, _flings);
      // Rooms the platform handed out, repeats included (the list holds 300).
      return {'roomsServed': app.site.roomsServed};
    });
    await app.close(tester);
  });

  for (final rate in const [50, 200]) {
    testWidgets('live room: $rate danmaku a second in the chat and on the video', (tester) async {
      phoneView(tester);
      final app = await BenchApp.pump(tester, environment);
      await tester.tap(find.byType(LiveRoomCard).first);
      await waitFor(tester, find.byType(LivePlayPage));
      await waitUntil(tester, () => app.danmaku.connections.isNotEmpty);
      await idle(tester, const Duration(milliseconds: 1500));
      await measure(
        tester,
        'danmaku_$rate',
        () async => {'perSecond': rate, 'sent': await app.danmaku.send(perSecond: rate, duration: _window)},
        // Research §4.1: the room's raster within 0.6 of a period (the video
        // redraws the screen; it plays nothing here); UI_PLAN §9.4: 200 a
        // second within 3 ms of UI time.
        rasterShare: 0.6,
        buildLimitMs: rate >= 200 ? 3 : null,
      );
      AppNavigator.back();
      await idle(tester, const Duration(seconds: 1));
      await app.close(tester);
    });
  }

  testWidgets("multi-view: four cells, the selected cell's danmaku at 50 a second", (tester) async {
    phoneView(tester);
    final app = await BenchApp.pump(tester, environment, follows: 4);
    await AppNavigator.toMultiview();
    await waitFor(tester, find.byType(MultiviewPage));
    for (var id = 1; id <= 4; id++) {
      final pick = find.byKey(ValueKey('multiview-pick-bilibili:$id'));
      await waitFor(tester, pick);
      await tester.ensureVisible(pick);
      await idle(tester, const Duration(milliseconds: 300));
      await tester.tap(pick, warnIfMissed: false);
      await idle(tester, const Duration(milliseconds: 600));
    }
    final filled = [
      for (var cell = 1; cell <= 4; cell++)
        if (find
            .descendant(of: find.byKey(ValueKey('multiview-cell-$cell')), matching: find.textContaining('主播'))
            .evaluate()
            .isNotEmpty)
          cell,
    ];
    // Multi-view shows the selected cell's danmaku (3.x).
    await tester.tap(find.byKey(const ValueKey('multiview-danmaku')), warnIfMissed: false);
    await waitUntil(tester, () => app.danmaku.connections.isNotEmpty, what: 'the danmaku connection');
    await idle(tester, const Duration(seconds: 1));
    await measure(
      tester,
      'multiview_4',
      () async => {
        'cellsWithRooms': filled.length,
        'perSecond': 50,
        'sent': await app.danmaku.send(perSecond: 50, duration: _window),
      },
      rasterShare: 0.6,
    );
    AppNavigator.back();
    await idle(tester, const Duration(seconds: 1));
    await app.close(tester);
  });

  testWidgets('settings: fast flings down and back up', (tester) async {
    phoneView(tester);
    final app = await BenchApp.pump(tester, environment);
    // Completes when the page closes.
    unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings));
    await waitFor(tester, find.byType(SettingsPage));
    await idle(tester, const Duration(seconds: 1));
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first;
    await measure(tester, 'settings_scroll', () async {
      await flingBothWays(tester, list, (_flings / 2).ceil());
      return {};
    });
    AppNavigator.back();
    await idle(tester, const Duration(milliseconds: 500));
    await app.close(tester);
  });

  testWidgets('a room opened from the hot list and closed $_visits times', (tester) async {
    phoneView(tester);
    final app = await BenchApp.pump(tester, environment);
    final resident = [residentMiB()];
    await measure(tester, 'room_enter_exit_$_visits', () async {
      for (var i = 0; i < _visits; i++) {
        await tester.tap(find.byType(LiveRoomCard).at(i % 4), warnIfMissed: false);
        await waitFor(tester, find.byType(LivePlayPage));
        await idle(tester, const Duration(milliseconds: 1500));
        AppNavigator.back();
        await waitUntil(tester, () => find.byType(LivePlayPage).evaluate().isEmpty);
        // Past AppNavigator.openGuard.
        await idle(tester, const Duration(milliseconds: 900));
        resident.add(residentMiB());
      }
      return {
        'visits': _visits,
        'residentMiB': {
          'start': resident.first,
          'end': resident.last,
          'max': resident.reduce((a, b) => a > b ? a : b),
          'samples': resident,
        },
      };
    });
    await app.close(tester);
  });

  testWidgets('P4: cover corners by clip (with and without a fade layer) or by decoration', (tester) async {
    phoneView(tester);
    // 24 distinct pictures, decoded before each run: only the corners differ.
    final pictures = [
      for (var i = 0; i < 24; i++) Uint8List.fromList(environment.covers.covers[i % environment.covers.covers.length]),
    ];
    for (final corners in CoverCorners.values) {
      final grid = ValueKey(corners);
      await tester.pumpWidget(CornerGrid(key: grid, pictures: pictures, corners: corners));
      // The test's pumps only wait: the grid comes with the next frame.
      await waitFor(tester, find.descendant(of: find.byKey(grid), matching: find.byType(GridView)));
      final context = tester.element(find.byKey(grid));
      for (final image in CornerGrid.providersOf(context, pictures)) {
        await precacheImage(image, context);
      }
      await idle(tester, const Duration(milliseconds: 500));
      await measure(tester, 'cover_corners_${corners.name}', () async {
        await flingBothWays(tester, find.byType(GridView), (_flings / 2).ceil());
        return {};
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// How the covers of [CornerGrid] get their rounded corners.
enum CoverCorners {
  /// `ClipRRect` over a fade at full opacity: the cards today, where
  /// cached_network_image fades a cover in that arrived after the first
  /// frame (an opacity layer, so the clip is a layer of its own).
  clipOverFade,

  /// `ClipRRect` over the picture alone.
  clip,

  /// The picture painted by a `BoxDecoration` with a radius (no clip).
  decoration,
}

/// A two-column grid of 16:9 covers with two lines under each, like the hot
/// list on a phone, its covers' corners rounded the [corners] way.
class CornerGrid extends StatelessWidget {
  /// Creates the grid over [pictures] (PNG).
  const new({required this.pictures, required this.corners, super.key});

  /// The pictures, used in turn.
  final List<Uint8List> pictures;

  /// How the corners are rounded.
  final CoverCorners corners;

  /// The pictures as the cards decode them: as wide as a card on screen.
  static List<ImageProvider> providersOf(BuildContext context, List<Uint8List> pictures) {
    final media = MediaQuery.of(context);
    final width = ((media.size.width - 18) / 2 * media.devicePixelRatio).round().clamp(240, 720);
    return [for (final bytes in pictures) ResizeImage(MemoryImage(bytes), width: width)];
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) {
        final images = providersOf(context, pictures);
        final radius = BorderRadius.circular(20);
        Widget cover(ImageProvider image) => switch (corners) {
          CoverCorners.clipOverFade => ClipRRect(
            borderRadius: radius,
            child: FadeTransition(
              opacity: kAlwaysCompleteAnimation,
              child: Image(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
            ),
          ),
          CoverCorners.clip => ClipRRect(
            borderRadius: radius,
            child: Image(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
          ),
          CoverCorners.decoration => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              image: DecorationImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
            ),
          ),
        };
        return Scaffold(
          body: GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.9,
            ),
            itemCount: 300,
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: cover(images[index % images.length])),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text('主播$index · 已播 ${index % 90} 分钟', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('标题 $index：今晚冲分', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
