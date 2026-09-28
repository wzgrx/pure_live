import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_media/testing.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/retry.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/discover/followed_areas.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/fonts/fonts.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/multiview/multiview_page.dart';
import 'package:pure_live_app/features/room/room_page.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import '../danmaku/fake_danmaku.dart';
import '../multiview_fakes.dart';
import 'shot_fonts.dart';
import 'shot_world.dart';

export 'shot_world.dart';

/// Window sizes, one per class of spec/design/principles.md §5.1, plus the
/// landscape phone (compact height wins) and the TV canvas (§5.3).
enum ShotScreen {
  /// Compact width: a 393 dp phone held upright (principles rule 2).
  phone('phone', Size(393, 852), 1.5),

  /// Compact height: the same phone on its side.
  phoneLandscape('phoneland', Size(852, 393), 1.5),

  /// Medium width: a small tablet upright.
  medium('medium', Size(768, 1024), 1),

  /// Expanded width: a tablet on its side.
  expanded('expanded', Size(1024, 768), 1),

  /// Large width: a Windows desktop window.
  large('large', Size(1440, 900), 1, desktop: true),

  /// Extra-large width: a maximised 1080p Windows window.
  extraLarge('xlarge', Size(1920, 1080), 1, desktop: true),

  /// TV mode on the 960×540 canvas.
  tv('tv', Size(960, 540), 1.5, television: true);

  new(this.id, this.size, this.pixelRatio, {this.desktop = false, this.television = false});

  /// Part of the file name.
  final String id;

  /// Logical size.
  final Size size;

  /// Device pixel ratio: the golden is [size] × this.
  final double pixelRatio;

  /// Windows (desktop density, pointer controls, the YaHei family).
  final bool desktop;

  /// A television: TV mode starts by itself.
  final bool television;
}

/// The appearances of principles §2.2.
enum ShotTheme { light, dark, black }

/// Why screenshots skip here, or null.
final String? shotSkipReason = ShotFonts.missing;

/// Loads the fonts once per file and puts the language back after each test.
void screenshotSetUp() {
  if (shotSkipReason != null) {
    // A visible note on machines without the fonts (Windows hosts).
    // ignore: avoid_print
    print('screenshots skipped: $shotSkipReason');
    return;
  }
  setUpAll(ShotFonts.load);
  tearDown(() => applyAppLocale(AppLocale.zhHans));
}

/// The golden file name of one screenshot.
String shotName(
  String page,
  ShotScreen screen, {
  ShotTheme theme = ShotTheme.light,
  AppLocale locale = AppLocale.zhHans,
  double textScale = 1,
}) => [
  page,
  screen.id,
  theme.name,
  locale.languageTag,
  if (textScale != 1) 'text${textScale.toStringAsFixed(1)}',
].join('_');

/// Declares one screenshot: the app on [screen] in [theme] and [locale],
/// [show] brings the page up, then the whole window is compared with
/// `goldens/<name>.png`. [textScale] is the product of the system and the
/// in-app text size (principles §2.3: at most 2.0).
void screenshot(
  String page,
  ShotScreen screen,
  Future<void> Function(ShotApp app) show, {
  ShotTheme theme = ShotTheme.light,
  AppLocale locale = AppLocale.zhHans,
  double textScale = 1,
  ShotWorld Function()? world,
  List<Override> Function(ShotWorld world)? overrides,
  Future<RecordManager> Function()? recorder,
}) {
  final name = shotName(page, screen, theme: theme, locale: locale, textScale: textScale);
  testWidgets(name, skip: shotSkipReason != null, (tester) async {
    final app = await ShotApp.pump(
      tester,
      screen: screen,
      theme: theme,
      locale: locale,
      textScale: textScale,
      world: world?.call() ?? ShotWorld(),
      overrides: overrides,
      recorder: recorder,
    );
    try {
      await show(app);
      await app.capture(name);
    } finally {
      await app.close();
    }
  });
}

/// The interface font of Android and TV screenshots (see [ShotFonts]).
class _ShotAppFont extends SettingNotifier<String> {
  new() : super(Settings.appFontFamily);

  @override
  String build() => ShotFonts.appFontId;
}

/// A refresh that already published [value].
class _Done extends FollowRefreshNotifier {
  new(this.value);

  final FollowRefreshResult? value;

  @override
  Future<FollowRefreshResult?> build() async => value;
}

/// The whole app on fakes, ready for one screenshot.
final class ShotApp {
  new _(this.tester, this.world, this.container, this.engines, this.chats, this.screen);

  final WidgetTester tester;
  final ShotWorld world;
  final ProviderContainer container;

  /// Engines the app created, in order (the fake plays nothing: black video).
  final List<FakeEngine> engines;

  /// Chat connections the app opened.
  final FakeDanmakuSource chats;

  final ShotScreen screen;

  /// The app's router.
  GoRouter get router => container.read(routerProvider);

  static Future<ShotApp> pump(
    WidgetTester tester, {
    required ShotScreen screen,
    required ShotTheme theme,
    required AppLocale locale,
    required double textScale,
    required ShotWorld world,
    List<Override> Function(ShotWorld world)? overrides,
    Future<RecordManager> Function()? recorder,
  }) async {
    tester.view
      ..physicalSize = screen.size * screen.pixelRatio
      ..devicePixelRatio = screen.pixelRatio;
    addTearDown(tester.view.reset);
    // TV mode switches focus highlighting to the remote's; the next test starts fresh.
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    // The in-app size goes up to 1.3; the rest comes from the system.
    final inApp = textScale.clamp(0.85, 1.3);
    if (textScale != inApp) tester.platformDispatcher.textScaleFactorTestValue = textScale / inApp;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    // The quiet recorder has read its (empty) task list, as the app's has
    // by the time anyone opens the recording center.
    final manager = await tester.runAsync(recorder ?? _quietRecorder);
    await tester.runAsync(() async {
      final settings = store.settings;
      await settings.set(Settings.themeMode, theme == ShotTheme.light ? AppThemeMode.light : AppThemeMode.dark);
      await settings.set(Settings.pureBlack, theme == ShotTheme.black);
      await settings.set(Settings.locale, locale.languageTag);
      await settings.set(Settings.textScale, inApp);
      await settings.set(Settings.danmakuFontFamily, ShotFonts.danmakuFontId);
    });
    if (screen.desktop) debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // Real elevation shadows: the test binding otherwise draws them as solid
    // black outlines.
    debugDisableShadows = false;
    final engines = <FakeEngine>[];
    final chats = FakeDanmakuSource();
    final sites = {for (final id in platformOrder) id: PlatformSite(ShotSite(id, world))};
    await tester.pumpWidget(
      ProviderScope(
        // The app's retry policy (main.dart).
        retry: networkRetry,
        overrides: [
          // Past the first run: no one-time tips over the pages (principles §6.5).
          appPrefsProvider.overrideWith(
            () => AppPrefsNotifier(
              AppPrefs(firstRunDone: true, switchGestureHinted: true, tips: {for (final tip in Tip.values) tip.name}),
            ),
          ),
          if (screen.television) tvDeviceProvider.overrideWithValue(const TvDevice(television: true)),
          if (!screen.desktop) appFontFamilySetting.overrideWith(_ShotAppFont.new),
          sitesProvider.overrideWithValue(sites),
          storeProvider.overrideWithValue(store),
          // The fullscreen clock (F-ROOM-17) reads the same on every run.
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 20, 30)),
          recordManagerProvider.overrideWithValue(manager!),
          engineFactoryProvider.overrideWithValue(() {
            final engine = FakeEngine();
            engines.add(engine);
            return engine;
          }),
          networkKindProvider.overrideWith((ref) => Stream.value(NetworkKind.unmetered)),
          followsProvider.overrideWith((ref) => world.followsStream),
          followRefreshProvider.overrideWith(() => _Done(world.follows ? world.refresh : null)),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          recordingRoomsProvider.overrideWith((ref) => Stream.value({'${shotRooms[1].platform}:${shotRooms[1].id}'})),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(true)),
          roomDetailProvider.overrideWith((ref, room) => sites[room.platform]!.rooms.detail(room)),
          danmakuSourceProvider.overrideWithValue(chats),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
          historyProvider.overrideWith((ref) => Stream.value(const [])),
          followedAreasProvider.overrideWith((ref) => Stream.value(const [])),
          liveAlertsOffProvider.overrideWith((ref) => Stream.value(const {})),
          roomVolumesProvider.overrideWithValue(MemoryRoomVolumes()),
          multiviewSystemFullscreenProvider.overrideWithValue(({required enabled, required phone}) async {}),
          iptvPlaylistsProvider.overrideWith((ref) => Stream.value(world.iptvPlaylists)),
          iptvGuideSourcesProvider.overrideWith((ref) => Stream.value(world.iptvGuides)),
          ...?overrides?.call(world),
        ],
        child: const PureLiveApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(PureLiveApp)));
    return ShotApp._(tester, world, container, engines, chats, screen);
  }

  /// A recorder with no tasks that never touches the disk or the network,
  /// its (empty) task list read.
  static Future<RecordManager> _quietRecorder() async {
    final manager = unreadRecorder();
    await manager.init();
    return manager;
  }

  /// A recorder that has not read its tasks yet (the recording center's
  /// loading state).
  static RecordManager unreadRecorder() => RecordManager(
    rooms: SiteRecordRooms((_) => null),
    store: MemoryRecordTaskStore(),
    root: '/nonexistent',
    opener: httpRecordOpener(),
  );

  /// Lets time pass: routes finish their transitions, futures answer.
  /// Spinners never settle, so this pumps fixed frames.
  Future<void> frames([int count = 10, Duration step = const Duration(milliseconds: 100)]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(step);
    }
  }

  /// Goes to [location] (a page of the shell) and waits for it.
  Future<void> go(String location) async {
    router.go(location);
    await frames();
  }

  /// Opens a full-screen route and waits for it.
  Future<void> push(String location, {Object? extra}) async {
    unawaited(router.push(location, extra: extra));
    await frames();
  }

  /// Every engine starts playing a 1080p picture (the fake shows black).
  Future<void> play() async {
    for (final engine in engines) {
      if (!engine.disposed) engine.startStreaming();
    }
    await frames(3);
  }

  /// Delivers the world's chat to every open chat connection.
  Future<void> chat() async {
    for (final feed in chats.feeds) {
      feed.emit(world.chat());
    }
    await frames(3);
  }

  /// Decodes the images on screen outside the fake clock: [Image] widgets
  /// and images that fill decorations (platform logos, principles §7.11).
  Future<void> _images() async {
    final images = [
      for (final element in find.byType(Image).evaluate()) ((element.widget as Image).image, element),
      for (final element in find.byType(DecoratedBox).evaluate())
        if ((element.widget as DecoratedBox).decoration case BoxDecoration(:final image?)) (image.image, element),
    ];
    if (images.isEmpty) return;
    await tester.runAsync(() => Future.wait([for (final (image, element) in images) precacheImage(image, element)]));
    await tester.pump();
  }

  /// Compares the window with `goldens/<name>.png`, after checking that no
  /// Material Icons glyph is on screen (principles §2.6: every icon is
  /// Material Symbols Rounded; Material's own widgets default to Material
  /// Icons, and that font is not loaded here).
  Future<void> capture(String name) async {
    final material = [
      for (final text in tester.widgetList<RichText>(find.byType(RichText, skipOffstage: false)))
        if (text.text.style?.fontFamily == 'MaterialIcons')
          'U+${text.text.toPlainText().runes.first.toRadixString(16)}',
    ];
    expect(material, isEmpty, reason: 'Material Icons glyphs on screen: ${material.join(', ')}');
    await _images();
    final view = tester.binding.renderViews.single;
    final layer = view.debugLayer! as OffsetLayer;
    await expectLater(layer.toImage(view.paintBounds), matchesGoldenFile('goldens/$name.png'));
  }

  /// Unmounts the app so its timers end, and restores the platform.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }
}
