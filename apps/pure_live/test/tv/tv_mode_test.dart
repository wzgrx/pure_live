import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/room/gestures.dart';
import 'package:pure_live_app/features/room/room_switch.dart';

/// TV mode resolution (principles §5.1 rule 1) and room switching
/// (F-NEW-04, live-room T-05, principles §6.1, §6.3).
void main() {
  group('TV mode', () {
    test('自动 follows the device; 开启 and 关闭 force it', () {
      const tv = TvDevice(television: true);
      const box = TvDevice(leanback: true);
      const phone = TvDevice.none;
      expect(resolveTvMode(TvMode.auto, tv), isTrue, reason: 'UI_MODE_TYPE_TELEVISION');
      expect(resolveTvMode(TvMode.auto, box), isTrue, reason: 'leanback feature alone');
      expect(resolveTvMode(TvMode.auto, phone), isFalse);
      expect(resolveTvMode(TvMode.on, phone), isTrue, reason: 'projectors and misreporting boxes');
      expect(resolveTvMode(TvMode.off, tv), isFalse);
    });

    test('the configuration follows the stored setting and performance mode', () async {
      final store = await LiveStore.inMemory();
      addTearDown(store.close);
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          tvDeviceProvider.overrideWithValue(const TvDevice(television: true)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tvConfigProvider, (_, _) {});
      expect(container.read(tvConfigProvider).enabled, isTrue, reason: 'auto on a TV');
      expect(container.read(tvConfigProvider).focusGrowth, isTrue);

      await store.settings.set(Settings.tvMode, TvMode.off);
      await store.settings.set(Settings.tvPerformanceMode, true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(tvConfigProvider).enabled, isFalse);
      expect(container.read(tvConfigProvider).focusGrowth, isFalse, reason: 'ring only');
    });

    test('TV themes are dark or pure black only', () {
      final (light, dark, mode) = themesFor(AppThemeMode.light, pureBlack: false, tv: true);
      expect(mode, ThemeMode.dark);
      expect(light.brightness, Brightness.dark);
      expect(dark.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(14));
      final (_, black, _) = themesFor(AppThemeMode.system, pureBlack: true, tv: true);
      expect(black.colorScheme.surface, const Color(0xFF000000));
    });
  });

  group('room switching', () {
    RoomEntry entry(String id) => RoomEntry(RoomRef('douyu', id), name: '主播$id');
    final list = [entry('1'), entry('2'), entry('3')];

    test('up is the previous room, down the next, in list order', () {
      expect(neighborRoom(list, RoomRef('douyu', '2'), 1)?.ref.roomId, '3');
      expect(neighborRoom(list, RoomRef('douyu', '2'), -1)?.ref.roomId, '1');
    });

    test('the ends do not wrap around', () {
      expect(neighborRoom(list, RoomRef('douyu', '3'), 1), isNull);
      expect(neighborRoom(list, RoomRef('douyu', '1'), -1), isNull);
      expect(neighborRoom(const [], RoomRef('douyu', '1'), 1), isNull);
    });

    test('a room outside the list enters it at the first or the last entry', () {
      expect(neighborRoom(list, RoomRef('huya', '9'), 1)?.ref.roomId, '1');
      expect(neighborRoom(list, RoomRef('huya', '9'), -1)?.ref.roomId, '3');
    });

    test('lists hold live rooms only, follows in the follows page order', () {
      RoomCard card(String id, LiveState state) =>
          RoomCard(ref: RoomRef('douyu', id), title: 't$id', anchorName: 'a$id', state: state);
      final origin = RoomOrigin.fromCards([
        card('1', LiveState.live),
        card('2', LiveState.offline),
        card('3', LiveState.live),
      ]);
      expect(origin.entries.map((e) => e.ref.roomId), ['1', '3']);

      FollowedRoom follow(String id, int online, LiveState state) => FollowedRoom(
        room: StoredRoom(
          ref: RoomRef('douyu', id),
          anchorName: 'a$id',
          title: 't$id',
          updatedAt: DateTime(2026),
          audience: Audience(online: online),
          lastState: state,
        ),
        followedAt: DateTime(2026),
        order: 0,
      );
      final entries = liveFollowEntries([
        follow('small', 10, LiveState.live),
        follow('off', 999, LiveState.offline),
        follow('big', 500, LiveState.live),
      ]);
      expect(entries.map((e) => e.ref.roomId), ['big', 'small'], reason: 'by audience, offline left out');
    });

    test('portrait swipe: the whole picture switches when on; up is next, down previous', () {
      expect(swipeTarget(x: 10, width: 400, touch: true, switchRooms: true), SwipeTarget.switchRoom);
      expect(swipeTarget(x: 390, width: 400, touch: true, switchRooms: true), SwipeTarget.switchRoom);
      expect(swipeTarget(x: 10, width: 400, touch: true), SwipeTarget.brightness, reason: 'off: brightness');
      expect(roomSwipeStep(dy: -120, velocity: 0), 1);
      expect(roomSwipeStep(dy: 120, velocity: 0), -1);
      expect(roomSwipeStep(dy: -30, velocity: -1200), 1, reason: 'a fling');
      expect(roomSwipeStep(dy: -30, velocity: -200), isNull, reason: 'too short and slow');
      expect(roomSwipeStep(dy: -30, velocity: 1200), isNull, reason: 'a fling against the travel');
    });
  });
}
