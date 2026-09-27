import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/discover/discover_refresh.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';

import 'fakes.dart';

void main() {
  group('F-APP-03 home resume', () {
    Future<Future<void> Function(Duration away)> pumpShell(WidgetTester tester, {required int tab}) async {
      var now = DateTime(2026, 9, 28, 12);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clockProvider.overrideWithValue(() => now)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) =>
                  HomeResumeRefresh(tab: tab, child: Text('requests ${ref.watch(discoverRefreshProvider)}')),
            ),
          ),
        ),
      );
      // The system steps through every state, as AppLifecycleListener expects.
      void go(List<AppLifecycleState> states) => states.forEach(tester.binding.handleAppLifecycleStateChanged);

      Future<void> leave(Duration away) async {
        go(const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
        now = now.add(away);
        go(const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
        await tester.pump(const Duration(milliseconds: 400));
      }

      return leave;
    }

    testWidgets('discover reloads 450 ms after coming back from 15 s away', (tester) async {
      final leave = await pumpShell(tester, tab: discoverTab);
      await leave(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('requests 0'), findsOneWidget, reason: 'away for 10 s');

      await leave(const Duration(seconds: 15));
      expect(find.text('requests 0'), findsOneWidget, reason: 'waits 450 ms');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('requests 1'), findsOneWidget);
    });

    testWidgets('other tabs do not reload discover', (tester) async {
      final leave = await pumpShell(tester, tab: 0);
      await leave(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('requests 0'), findsOneWidget);
    });
  });

  testWidgets('F-APP-03: a discover grid loads again on request', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final site = FakeSite(
      'douyu',
      pages: [
        Page([FakeSite('douyu').card('1')]),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: Scaffold(
            body: RoomGrid(query: const RecommendedQuery('douyu'), refreshOn: discoverRefreshProvider),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(site.cursors, [null]);
    expect(find.text('主播1'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(RoomGrid)));
    container.read(discoverRefreshProvider.notifier).request();
    await tester.pump();
    await tester.pump();
    expect(site.cursors, [null, null]);
    expect(find.text('主播1'), findsOneWidget, reason: 'the old list stays while the new one loads');
  });
}
