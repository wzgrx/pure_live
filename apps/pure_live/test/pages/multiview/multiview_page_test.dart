import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/pages/multiview/multiview_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../live_play_support.dart';
import '../../support.dart';
import 'multiview_support.dart';

Future<AppServices> _pump(WidgetTester tester, {required double width}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() async {
    await services.store.follows.add(pickRoom('1'));
    await services.store.follows.add(pickRoom('2'));
  });
  final site = RoomsSite();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
      ),
    ),
  );
  await _wait(tester);
  return services;
}

Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

void main() {
  testWidgets('phone: pick a room for a cell, its menu closes it; back leaves immersive mode first', (tester) async {
    final services = await _pump(tester, width: 400);
    AppNavigator.toast = (_) {};
    expect(find.text('多画面'), findsOneWidget);
    expect(find.text('点击选台'), findsNWidgets(4));
    expect(find.text('2×2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiview-cell-1')));
    await _wait(tester);
    await tester.pumpAndSettle();
    expect(find.text('主播1'), findsOneWidget);
    expect(find.text('主播2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('multiview-pick-bilibili:1')));
    await tester.pumpAndSettle();
    await _wait(tester);

    expect(find.text('点击选台'), findsNWidgets(3));
    expect(find.text('主播1'), findsOneWidget);
    expect(find.byKey(const ValueKey('multiview-audio-badge')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiview-cell-more-1')));
    await tester.pumpAndSettle();
    expect(find.text('进入直播间'), findsOneWidget);
    expect(find.text('选择清晰度'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('multiview-action-close')));
    await tester.pumpAndSettle();
    await _wait(tester);
    expect(find.text('点击选台'), findsNWidgets(4));

    await tester.tap(find.byKey(const ValueKey('multiview-immersive')));
    await tester.pump();
    expect(find.byKey(const ValueKey('multiview-immersive-exit')), findsOneWidget);
    expect(find.text('多画面'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('多画面'), findsOneWidget);

    await _close(tester, services);
  });

  testWidgets('desktop: the picker stays beside the grid and fills the cells in turn', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final toasts = <String>[];
    AppNavigator.toast = toasts.add;
    final services = await _pump(tester, width: 1200);
    expect(find.text('为格子 1 选台'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiview-pick-bilibili:1')));
    await _wait(tester);
    expect(find.text('为格子 2 选台'), findsOneWidget);
    // The room plays in cell 1 and the picker marks it.
    expect(find.text('第 1 格'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('multiview-pick-bilibili:1')));
    await _wait(tester);
    expect(toasts, ['这个直播间已在第 1 格播放']);

    await tester.tap(find.text('1+3'));
    await _wait(tester);
    expect(find.byKey(const ValueKey('multiview-add-cell')), findsOneWidget);
    expect(find.byKey(const ValueKey('multiview-quality-chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('multiview-cell-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('multiview-control-bar')), findsOneWidget);

    await _close(tester, services);
    debugDefaultTargetPlatformOverride = null;
  });
}
