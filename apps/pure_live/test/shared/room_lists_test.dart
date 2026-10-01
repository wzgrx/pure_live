// F.5a item 3: the time on air on the cards of every list page, and the
// search pages sharing the platform's snapshot (UPGRADES 7-9, 10-3, 25-12,
// 33-7; 19-1, 24-5, 26-1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../support.dart';

final DateTime _now = DateTime.utc(2026, 10, 1, 12);

LiveRoom _room(String id, {LiveStatus status = LiveStatus.live, DateTime? startedAt}) => LiveRoom(
  platform: SiteIds.acfun,
  roomId: id,
  title: 'title $id',
  nick: 'anchor $id',
  liveStatus: status,
  startedAt: startedAt,
);

void main() {
  setUpAll(loadStrings);

  testWidgets('c1: a card without a time of its own takes the shared clock: live rooms say how long they are on', (
    tester,
  ) async {
    final services = (await tester.runAsync(testServices))!;
    addTearDown(() => tester.runAsync(services.close));
    final strings = (await tester.runAsync(loadStrings))!;
    final started = _now.subtract(const Duration(minutes: 12));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services), roomClockProvider.overrideWithValue(() => _now)],
        child: LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  for (final room in [
                    _room('1', startedAt: started),
                    _room('2', status: LiveStatus.offline, startedAt: started),
                    _room('3'),
                  ])
                    Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(width: 200, height: 190, child: RoomGridCard(room: room)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('anchor 1 · 已播 12 分钟'), findsOneWidget);
    // Offline, or live without a known start: the streamer alone.
    expect(find.text('anchor 2'), findsOneWidget);
    expect(find.text('anchor 3'), findsOneWidget);
  });

  test('c4: the search pages share the platform snapshot; a new search takes a new one (19-1)', () async {
    var now = DateTime.utc(2026, 9, 28);
    final http = ReplayHttp([ReplaySample.load('../../fixtures/showroom/S01-onlives')]);
    final model = SearchModel(
      sites: [ShowroomSite(http, now: () => now)],
      audienceCompare: (a, b) => 0,
      // The sample has 12 rooms with an "a": three pages.
      pageSize: 5,
    );
    addTearDown(model.dispose);

    await model.search('a');
    expect(http.requests, hasLength(1));
    final first = model.results.length;
    expect(first, 5);
    expect(model.hasMore, isTrue);
    now = now.add(const Duration(seconds: 10));
    await model.loadMore();
    expect(http.requests, hasLength(1), reason: 'page 2 comes from the snapshot of page 1');
    expect(model.results.length, greaterThan(first));
    final ids = [for (final room in model.results) room.roomId];
    expect(ids.toSet(), hasLength(ids.length), reason: 'one snapshot: no room twice');

    await model.search('b');
    expect(http.requests, hasLength(2), reason: 'a new search is page 1: a new snapshot');
  });
}
