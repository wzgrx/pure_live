// The live room for the local interaction's tests (U.2k).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A room opened by [pumpLocalRoom].
final class LocalRoom {
  new(this.services, this.engine, this.danmaku, this.toasts);

  /// The app's services.
  final AppServices services;

  /// The player.
  final FakeEngine engine;

  /// The danmaku connection.
  final FakeDanmaku danmaku;

  /// Toasts shown so far.
  final List<String> toasts;

  /// The settings.
  SettingsStore get settings => services.store.settings;
}

/// Opens a live Bilibili room [width] × [height] wide, with [settings]
/// stored first and [prepare] run on the store (D08.1: what was sent
/// before). [reuse] enters again with the services of an earlier room
/// (left with [leaveLocalRoom]). [interaction] makes the app's local
/// interaction (D08.3: one with a fake clock). The room is on [platform]
/// (D08.6: its pack).
Future<LocalRoom> pumpLocalRoom(
  WidgetTester tester, {
  String platform = SiteIds.bilibili,
  double width = 400,
  double height = 900,
  Map<Setting<Object>, Object> settings = const {},
  ThemeData? theme,
  Widget Function(Widget child)? wrap,
  Future<void> Function(LiveStore store)? prepare,
  AppServices? reuse,
  LocalInteraction Function(LiveStore store)? interaction,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(() async {
    final services = reuse ?? await testServices();
    if (settings.isNotEmpty) await services.store.settings.setAll(settings);
    await prepare?.call(services.store);
    return services;
  }))!;
  await tester.runAsync(loadStrings);
  final engine = FakeEngine();
  final danmaku = FakeDanmaku();
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30)), platform: platform))
    ..siteId = platform;
  final page = LivePlayPage(
    route: RouteArgs(
      RoutePath.kLivePlay,
      arguments: LiveRoom(platform: platform, roomId: '6', nick: '主播'),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({platform: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({platform: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
        if (interaction != null)
          localInteractionProvider.overrideWith((ref) {
            final local = interaction(services.store);
            unawaited(local.start());
            ref.onDispose(local.dispose);
            return local;
          }),
      ],
      child: MaterialApp(
        theme: theme ?? const LiveTheme().light,
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: wrap == null ? page : wrap(page),
      ),
    ),
  );
  await settleLocal(tester);
  return LocalRoom(services, engine, danmaku, toasts);
}

/// Lets the store and the streams catch up.
Future<void> settleLocal(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Leaves the room and keeps its services (to enter again).
Future<void> leaveLocalRoom(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
}

/// Closes [room] and its services.
Future<void> closeLocalRoom(WidgetTester tester, LocalRoom room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
}
