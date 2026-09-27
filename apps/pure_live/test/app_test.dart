import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/search/search_page.dart';

import 'fakes.dart';

void main() {
  test('link detection', () {
    expect(looksLikeLink('https://www.douyu.com/288016'), isTrue);
    expect(looksLikeLink('复制打开抖音 v.douyin.com/abc'), isTrue);
    expect(looksLikeLink('英雄联盟'), isFalse);
    expect(looksLikeLink('288016'), isFalse);
  });

  testWidgets('starts on 关注, discovers rooms and opens one', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sites = {
      for (final id in platformOrder)
        id: PlatformSite(
          FakeSite(
            id,
            pages: [
              Page([FakeSite(id).card('$id-1')]),
            ],
          ),
        ),
    };
    await tester.pumpWidget(
      ProviderScope(overrides: [sitesProvider.overrideWithValue(sites)], child: const PureLiveApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有关注的主播'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('去发现'));
    await tester.pumpAndSettle();
    expect(find.text('主播bilibili-1'), findsOneWidget);

    await tester.tap(find.text('主播bilibili-1'));
    await tester.pumpAndSettle();
    expect(find.text('标题bilibili-1'), findsOneWidget);
    expect(find.text('打开原站'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
