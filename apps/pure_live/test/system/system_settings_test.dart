import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/system_settings.dart';

void main() {
  testWidgets('system tiles per platform; the close behaviour maps to two settings', (tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));

    Future<void> show(List<Widget> tiles) => tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(body: ListView(children: tiles)),
        ),
      ),
    );

    await show([...systemGeneralTiles(windows: false), ...systemPlaybackTiles(android: false, windows: false)]);
    expect(find.text('离开直播间时小窗播放'), findsOneWidget);
    expect(find.text('开机自启'), findsNothing);
    expect(find.text('离开应用时自动画中画'), findsNothing);
    expect(find.text('画中画窗口置顶'), findsNothing);

    await show(systemPlaybackTiles(android: true, windows: false));
    expect(find.text('离开应用时自动画中画'), findsOneWidget);

    await show([...systemGeneralTiles(windows: true), ...systemPlaybackTiles(android: false, windows: true)]);
    expect(find.text('开机自启'), findsOneWidget);
    expect(find.text('画中画窗口置顶'), findsOneWidget);
    expect(find.text('每次询问'), findsOneWidget);

    Future<void> choose(String label) async {
      await tester.tap(find.text('关闭窗口时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      // The database write completes outside the fake clock.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    await choose('最小化到托盘');
    expect(store.settings.get(Settings.closeDontAsk), isTrue);
    expect(store.settings.get(Settings.closeAction), CloseAction.minimize);
    expect(find.text('最小化到托盘'), findsOneWidget);

    await choose('每次询问');
    expect(store.settings.get(Settings.closeDontAsk), isFalse);
    expect(find.text('每次询问'), findsOneWidget);
  });
}
