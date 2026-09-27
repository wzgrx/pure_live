import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/alerts/alert_startup.dart';
import 'package:pure_live_app/features/alerts/alert_tiles.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/alerts/programme_reminders.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/follows/groups.dart';

import 'fake_notifier.dart';

/// A refresh that finishes at once; drift's real asynchronous work does not
/// complete on the widget tests' fake clock.
class _NoRefresh extends FollowRefreshNotifier {
  int builds = 0;

  @override
  Future<FollowRefreshResult?> build() async {
    builds++;
    return null;
  }
}

/// A router with stand-in pages that show where a tap led.
GoRouter _router() => GoRouter(
  initialLocation: '/follows',
  routes: [
    GoRoute(
      path: '/follows',
      builder: (context, state) =>
          Text('关注页 ${state.uri.queryParameters['filter'] ?? '-'} ${state.uri.queryParameters['at'] ?? '-'}'),
    ),
    GoRoute(
      path: '/room/:platform/:roomId',
      builder: (context, state) => Text('直播间 ${state.pathParameters['platform']} ${state.pathParameters['roomId']}'),
    ),
  ],
);

Future<LiveStore> _store(WidgetTester tester) async {
  final store = (await tester.runAsync(LiveStore.inMemory))!;
  addTearDown(() => tester.runAsync(store.close));
  return store;
}

/// Lets drift finish writes started by the widgets.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
}

void main() {
  group('settings switch', () {
    Future<LiveStore> show(WidgetTester tester, FakeAlertNotifier notifier) async {
      final store = await _store(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store), alertNotifierProvider.overrideWithValue(notifier)],
          child: const MaterialApp(home: Scaffold(body: LiveAlertsTile())),
        ),
      );
      return store;
    }

    testWidgets('turning it on asks for the permission and turns on when granted', (tester) async {
      final notifier = FakeAlertNotifier(allowed: false);
      final store = await show(tester, notifier);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse, reason: 'off by default');
      await tester.tap(find.text('开播提醒'));
      await tester.pump();
      await _settle(tester);
      expect(notifier.requests, 1);
      expect(store.settings.get(Settings.liveAlerts), isTrue);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

      await tester.tap(find.text('开播提醒'));
      await _settle(tester);
      expect(store.settings.get(Settings.liveAlerts), isFalse);
      expect(notifier.requests, 1, reason: 'turning off asks nothing');
    });

    testWidgets('a refused permission leaves it off and says why', (tester) async {
      final notifier = FakeAlertNotifier(grant: false, allowed: false);
      final store = await show(tester, notifier);
      await tester.tap(find.text('开播提醒'));
      await tester.pump();
      await _settle(tester);
      expect(notifier.requests, 1);
      expect(store.settings.get(Settings.liveAlerts), isFalse);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
      expect(find.text(notificationsDeniedText), findsOneWidget);
    });

    testWidgets('platforms without notifications show it disabled', (tester) async {
      final store = await _store(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: const MaterialApp(home: Scaffold(body: LiveAlertsTile())),
        ),
      );
      expect(find.text('这个系统上不支持通知'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    });
  });

  group('per-room switch', () {
    // The opt-out list as a plain stream: drift's watch timers do not run on
    // the fake clock. Tests push what the store holds after each write.
    Future<(LiveStore, StreamController<Set<RoomRef>>)> show(
      WidgetTester tester,
      RoomRef room, {
      bool global = true,
    }) async {
      final store = await _store(tester);
      if (global) await tester.runAsync(() => store.settings.set(Settings.liveAlerts, true));
      final optedOut = StreamController<Set<RoomRef>>();
      // Not awaited: a stream nobody listened to never finishes closing.
      addTearDown(() => unawaited(optedOut.close()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            liveAlertsOffProvider.overrideWith((ref) => optedOut.stream),
          ],
          child: MaterialApp(
            home: Scaffold(body: RoomAlertSwitch(room: room)),
          ),
        ),
      );
      optedOut.add(const {});
      await tester.pump();
      return (store, optedOut);
    }

    testWidgets('turns one room off and back on', (tester) async {
      final room = RoomRef('douyu', '5526219');
      final (store, optedOut) = await show(tester, room);
      expect(find.text('开播时发通知'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await _settle(tester);
      final off = (await tester.runAsync(store.roomPrefs.liveAlertsOff))!;
      expect(off, {room});
      optedOut.add(off);
      await tester.pump();
      expect(find.text('这个主播开播时不提醒'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await _settle(tester);
      expect(await tester.runAsync(store.roomPrefs.liveAlertsOff), isEmpty);
    });

    testWidgets('with the global switch off it is disabled and says where to turn it on', (tester) async {
      await show(tester, RoomRef('douyu', '1'), global: false);
      expect(find.text('先在 设置 › 通用 打开开播提醒'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    });

    testWidgets('IPTV channels have no switch', (tester) async {
      await show(tester, IptvSite.refOf('CCTV-1'));
      expect(find.byType(SwitchListTile), findsNothing);
    });
  });

  group('taps', () {
    testWidgets('a room notice opens the room; the combined one opens the live tab each time', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('关注页 - -'), findsOneWidget);

      openAlertPayload(router, roomLocation(IptvSite.refOf('CCTV-1 综合')));
      await tester.pumpAndSettle();
      expect(find.text('直播间 iptv CCTV-1 综合'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      var clock = DateTime.utc(2026, 9, 28, 20);
      openAlertPayload(router, followsLiveLocation, now: () => clock);
      await tester.pumpAndSettle();
      expect(find.text('关注页 live ${clock.millisecondsSinceEpoch}'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 1));
      openAlertPayload(router, followsLiveLocation, now: () => clock);
      await tester.pumpAndSettle();
      expect(find.text('关注页 live ${clock.millisecondsSinceEpoch}'), findsOneWidget);

      openAlertPayload(router, 'https://example.com/room/a/b');
      openAlertPayload(router, '/me/settings');
      await tester.pumpAndSettle();
      expect(
        find.text('关注页 live ${clock.millisecondsSinceEpoch}'),
        findsOneWidget,
        reason: 'unknown payloads do nothing',
      );
    });

    Future<(ProviderContainer, GoRouter)> start(
      WidgetTester tester,
      LiveStore store,
      FakeAlertNotifier notifier, {
      _NoRefresh? refresh,
    }) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            routerProvider.overrideWithValue(router),
            alertNotifierProvider.overrideWithValue(notifier),
            programmeReminderStorageProvider.overrideWithValue(
              ReminderStorage(read: () async => null, write: (_) async {}),
            ),
            followRefreshProvider.overrideWith(() => refresh ?? _NoRefresh()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(Router<Object>)))
        ..read(alertStartupProvider);
      await tester.pumpAndSettle();
      return (container, router);
    }

    testWidgets('taps while running open their location', (tester) async {
      final store = await _store(tester);
      final notifier = FakeAlertNotifier();
      await start(tester, store, notifier);
      expect(notifier.starts, 0, reason: 'nothing starts while no notification feature is in use');
      notifier.tap(roomLocation(RoomRef('douyu', '5526219')));
      await tester.pumpAndSettle();
      expect(find.text('直播间 douyu 5526219'), findsOneWidget);
    });

    testWidgets('with live alerts on, the notice that launched the app opens and the refresh runs', (tester) async {
      final store = await _store(tester);
      await tester.runAsync(() => store.settings.set(Settings.liveAlerts, true));
      final notifier = FakeAlertNotifier(launchPayload: followsLiveLocation);
      final refresh = _NoRefresh();
      await start(tester, store, notifier, refresh: refresh);
      expect(notifier.starts, greaterThan(0));
      expect(find.textContaining('关注页 live'), findsOneWidget);
      expect(refresh.builds, 1, reason: 'the follow refresh (and its timer) runs without the follows page');
    });

    testWidgets('notifications turned off in the system turn the switch off at start', (tester) async {
      final store = await _store(tester);
      await tester.runAsync(() => store.settings.set(Settings.liveAlerts, true));
      final notifier = FakeAlertNotifier(allowed: false);
      await start(tester, store, notifier);
      await _settle(tester);
      expect(store.settings.get(Settings.liveAlerts), isFalse);
    });
  });

  group('follows page', () {
    testWidgets('opens on the live tab when asked, again after the user switched tabs', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await _store(tester);
      final now = DateTime.now().toUtc();
      FollowedRoom follow(String id, LiveState state) => FollowedRoom(
        room: StoredRoom(
          ref: RoomRef('douyu', id),
          anchorName: '主播$id',
          title: '标题$id',
          updatedAt: now,
          lastState: state,
        ),
        followedAt: now,
        order: 0,
      );
      Future<void> pump({String? filter, String? request}) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            followsProvider.overrideWith(
              (ref) => Stream.value([follow('1', LiveState.live), follow('2', LiveState.offline)]),
            ),
            followRefreshProvider.overrideWith(_NoRefresh.new),
            tagsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
            home: FollowsPage(filter: filter, request: request),
          ),
        ),
      );
      bool liveSelected() => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '开播 1')).selected;

      await pump();
      await tester.pump();
      expect(liveSelected(), isFalse, reason: 'all by default');
      expect(find.text('未开播 1'), findsOneWidget);

      await pump(filter: 'live', request: '1');
      await tester.pump();
      expect(liveSelected(), isTrue);
      expect(find.text('未开播 1'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
      await tester.pump();
      expect(liveSelected(), isFalse);

      await pump(filter: 'live', request: '2');
      await tester.pump();
      expect(liveSelected(), isTrue, reason: 'a second notice tap applies the tab again');
    });
  });
}
