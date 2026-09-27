import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/multiview/multiview_page.dart';
import 'package:pure_live_app/features/multiview/multiview_sheets.dart';

import '../fakes.dart';

/// Multiview on TV (principles §5.3, §6.3; multiview.md TV rows): fixed
/// 2×2, the D-pad moves between cells, OK sets the sound focus.
void main() {
  testWidgets('fixed 2×2; the D-pad moves between the cells; OK gives a playing cell the sound', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(FakeSite('douyu'))}),
          engineFactoryProvider.overrideWithValue(FakeEngine.new),
        ],
        child: MaterialApp(
          theme: PureTheme.tv(Appearance.dark),
          builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
          home: const MultiviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MultiviewPage)));
    expect(container.read(multiviewProvider).layout, MultiviewLayout.four);
    expect(find.byTooltip('布局'), findsNothing, reason: 'no other layouts on TV');
    expect(find.byTooltip('沉浸模式'), findsNothing, reason: 'TV is fullscreen already (OPS-6)');
    expect(find.byTooltip('全屏'), findsNothing);
    expect(find.byType(MultiviewRoomPicker), findsNothing, reason: 'TV picks in a sheet, no panel (LYT-7)');
    expect(find.text('添加直播间'), findsNWidgets(4));

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    expect(focused(), 'multiview-cell-0');
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'multiview-cell-1');
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'multiview-cell-1', reason: 'the row end holds');
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'multiview-cell-3');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'multiview-cell-2');
    await press(LogicalKeyboardKey.arrowUp);
    expect(focused(), 'multiview-cell-0');

    // Two playing cells: the newest has the sound (AUD-2); OK on the other
    // moves it (OPS-1), up and down never switch rooms.
    final controller = container.read(multiviewProvider.notifier);
    await tester.runAsync(() => controller.assign(0, RoomRef('douyu', 'a')));
    await tester.runAsync(() => controller.assign(1, RoomRef('douyu', 'b')));
    await tester.pump();
    expect(container.read(multiviewProvider).audioFocus, 1);
    await press(LogicalKeyboardKey.select);
    expect(container.read(multiviewProvider).audioFocus, 0);
    expect(container.read(multiviewProvider).cells[0].room, RoomRef('douyu', 'a'));
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'multiview-cell-2');
    expect(container.read(multiviewProvider).cells[0].room, RoomRef('douyu', 'a'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
