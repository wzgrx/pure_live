import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/discover/discover_page.dart';
import 'package:pure_live_app/features/discover/followed_areas.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';

import 'fakes.dart';

void main() {
  testWidgets('推荐 and 分区 start at the page edge like the platform tabs above them', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({
            for (final id in ['bilibili', 'douyu'])
              id: PlatformSite(
                FakeSite(
                  id,
                  pages: [
                    Page([FakeSite(id).card('$id-1')]),
                  ],
                ),
              ),
          }),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
          followedAreasProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const DiscoverPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final platformTab = tester.getTopLeft(find.text('哔哩哔哩'));
    final recommended = tester.getTopLeft(find.text('推荐'));
    expect(recommended.dx, lessThan(platformTab.dx + 24), reason: 'aligned to the start, not centred');
    expect(tester.getTopLeft(find.text('分区')).dx, greaterThan(recommended.dx));
  });
}
