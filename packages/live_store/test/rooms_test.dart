import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

RoomSnapshot snapshot(
  String platform,
  String roomId, {
  String? nick,
  String? title,
  LiveState? state,
  Audience audience = Audience.none,
  Uri? avatar,
}) => RoomSnapshot(
  ref: RoomRef(platform, roomId),
  anchorName: nick,
  title: title,
  state: state,
  audience: audience,
  avatar: avatar,
);

void main() {
  late LiveStore store;

  setUp(() async => store = await LiveStore.inMemory());
  tearDown(() => store.close());

  group('FollowStore', () {
    test('follows in order, once per room, and keeps room id case', () async {
      await store.follows.follow(snapshot('douyu', '1', nick: 'A'));
      await store.follows.follow(snapshot('kick', 'Abc', nick: 'B'));
      await store.follows.follow(snapshot('kick', 'abc', nick: 'C'));
      await store.follows.follow(snapshot('DOUYU', ' 1 ', title: 'again'));
      final follows = await store.follows.all();
      expect(follows.map((follow) => follow.ref.key), ['douyu:1', 'kick:Abc', 'kick:abc']);
      expect(follows.first.room.anchorName, 'A', reason: 'a null field keeps the stored value');
      expect(follows.first.room.title, 'again');
      expect(follows.map((follow) => follow.order), [0, 1, 2]);
      expect(await store.follows.count(), 3);
      expect(await store.follows.contains(RoomRef('kick', 'ABC')), isFalse);
    });

    test('card data from a card and live time', () async {
      final at = DateTime.utc(2026, 9, 27, 12);
      await store.follows.follow(
        RoomSnapshot.fromCard(
          RoomCard(
            ref: RoomRef('huya', '998'),
            title: 'Live now',
            anchorName: 'Streamer',
            state: LiveState.live,
            cover: Uri.parse('https://example.invalid/c.jpg'),
            audience: const Audience(popularity: 1200),
          ),
        ),
        at: at,
      );
      final room = (await store.follows.get(RoomRef('huya', '998')))!.room;
      expect(room.lastState, LiveState.live);
      expect(room.lastLiveAt, at);
      expect(room.cover, Uri.parse('https://example.invalid/c.jpg'));
      expect(room.audience.popularity, 1200);
      expect(room.audience.online, isNull);
    });

    test('unfollow returns the entry for undo; restore puts it back', () async {
      await store.follows.follow(snapshot('douyu', '1'));
      await store.follows.follow(snapshot('douyu', '2'));
      final removed = await store.follows.unfollow(RoomRef('douyu', '1'));
      expect(removed?.ref, RoomRef('douyu', '1'));
      expect(await store.follows.unfollow(RoomRef('douyu', '1')), isNull);
      expect((await store.follows.all()).map((follow) => follow.ref.roomId), ['2']);
      await store.follows.restore([removed!]);
      expect((await store.follows.all()).map((follow) => follow.ref.roomId), ['1', '2']);
    });

    test('reorder puts the given rooms first', () async {
      for (final id in ['1', '2', '3']) {
        await store.follows.follow(snapshot('douyu', id));
      }
      await store.follows.reorder([RoomRef('douyu', '3'), RoomRef('huya', 'x')]);
      expect((await store.follows.all()).map((follow) => follow.ref.roomId), ['3', '1', '2']);
    });

    test('watchAll emits after follows, refreshes and tag changes', () async {
      final emissions = <List<FollowedRoom>>[];
      final subscription = store.follows.watchAll().listen(emissions.add);
      await pumpEventQueue();
      await store.follows.follow(snapshot('douyu', '1', nick: 'A'));
      await pumpEventQueue();
      await store.rooms.update([snapshot('douyu', '1', state: LiveState.offline), snapshot('douyu', 'unknown')]);
      await pumpEventQueue();
      final tag = await store.tags.create('Games');
      await store.tags.setTagsOf(RoomRef('douyu', '1'), {tag.id});
      await pumpEventQueue();
      expect(emissions.first, isEmpty);
      expect(emissions.last.single.room.lastState, LiveState.offline);
      expect(emissions.last.single.tagIds, {tag.id});
      expect(await store.rooms.get(RoomRef('douyu', 'unknown')), isNull, reason: 'refresh never adds rooms');
      await subscription.cancel();
    });

    test('watchContains follows the follow state', () async {
      final states = <bool>[];
      final subscription = store.follows.watchContains(RoomRef('douyu', '1')).listen(states.add);
      await pumpEventQueue();
      await store.follows.follow(snapshot('douyu', '1'));
      await pumpEventQueue();
      await store.follows.unfollow(RoomRef('douyu', '1'));
      await pumpEventQueue();
      expect(states, [false, true, false]);
      await subscription.cancel();
    });
  });

  group('HistoryStore', () {
    test('newest first, one entry per room', () async {
      await store.history.record(snapshot('douyu', '1'), at: DateTime.utc(2026));
      await store.history.record(snapshot('douyu', '2'), at: DateTime.utc(2026, 2));
      await store.history.record(snapshot('douyu', '1', title: 'again'), at: DateTime.utc(2026, 3));
      final entries = await store.history.all();
      expect(entries.map((entry) => entry.ref.roomId), ['1', '2']);
      expect(entries.first.lastWatchedAt, DateTime.utc(2026, 3));
      expect(entries.first.room.title, 'again');
    });

    test('the limit trims the oldest entries; 0 keeps everything', () async {
      await store.settings.set(Settings.historyLimit, 2);
      for (var i = 1; i <= 4; i++) {
        await store.history.record(snapshot('douyu', '$i'), at: DateTime.utc(2026, i));
      }
      expect((await store.history.all()).map((entry) => entry.ref.roomId), ['4', '3']);
      await store.settings.set(Settings.historyLimit, 0);
      for (var i = 5; i <= 60; i++) {
        await store.history.record(snapshot('douyu', '$i'), at: DateTime.utc(2026, 5, i));
      }
      expect(await store.history.all(), hasLength(58));
      await store.settings.set(Settings.historyLimit, 10);
      expect(await store.history.trim(), 48);
    });

    test('clear removes only the snapshot and supports undo', () async {
      await store.history.record(snapshot('douyu', '1'), at: DateTime.utc(2026));
      await store.history.record(snapshot('douyu', '2'), at: DateTime.utc(2026, 2));
      final shown = await store.history.all();
      await store.history.record(snapshot('douyu', '1'), at: DateTime.utc(2026, 3));
      await store.history.record(snapshot('douyu', '3'), at: DateTime.utc(2026, 4));
      final removed = await store.history.clear(shown);
      expect(removed.map((entry) => entry.ref.roomId), ['2']);
      expect((await store.history.all()).map((entry) => entry.ref.roomId), ['3', '1']);
      await store.history.restore(removed);
      expect((await store.history.all()).map((entry) => entry.ref.roomId), ['3', '1', '2']);
    });

    test('remove returns the entry', () async {
      await store.history.record(snapshot('douyu', '1'));
      expect((await store.history.remove(RoomRef('douyu', '1')))?.ref.roomId, '1');
      expect(await store.history.all(), isEmpty);
    });
  });

  group('TagStore', () {
    test('names are unique regardless of case', () async {
      final games = await store.tags.create(' Games ');
      expect(games.name, 'Games');
      await expectLater(store.tags.create('games'), throwsA(isA<TagNameException>()));
      await expectLater(store.tags.create('  '), throwsA(isA<TagNameException>()));
      final music = await store.tags.create('Music');
      await expectLater(store.tags.rename(music.id, 'GAMES'), throwsA(isA<TagNameException>()));
      await store.tags.rename(games.id, 'GAMES');
      expect((await store.tags.all()).map((tag) => tag.name), ['GAMES', 'Music']);
    });

    test('membership, reorder and delete', () async {
      final a = await store.tags.create('A');
      final b = await store.tags.create('B');
      final ref = RoomRef('douyu', '1');
      await store.tags.setTagsOf(ref, {a.id, b.id, 'missing'});
      expect(await store.tags.tagsOf(ref), {a.id, b.id});
      await store.tags.addRooms(a.id, [RoomRef('douyu', '2')]);
      await store.tags.removeRooms(b.id, [ref]);
      expect(await store.tags.tagsOf(ref), {a.id});
      await store.tags.reorder([b.id]);
      expect((await store.tags.all()).map((tag) => tag.name), ['B', 'A']);
      await store.tags.delete(a.id);
      expect(await store.tags.tagsOf(ref), isEmpty);
      expect(await store.tags.tagsOf(RoomRef('douyu', '2')), isEmpty);
    });
  });

  group('BlockRuleStore', () {
    test('rules are unique per kind after folding', () async {
      expect(await store.blockRules.add(BlockKind.keyword, ' Spam '), isTrue);
      expect(await store.blockRules.add(BlockKind.keyword, 'spam'), isFalse);
      expect(await store.blockRules.add(BlockKind.user, 'spam'), isTrue);
      expect(await store.blockRules.add(BlockKind.user, '  '), isFalse);
      final keywords = await store.blockRules.all(BlockKind.keyword);
      expect(keywords.single.value, 'Spam');
      expect(keywords.single.folded, 'spam');
      expect(await store.blockRules.remove(BlockKind.keyword, 'SPAM'), isTrue);
      expect(await store.blockRules.all(), hasLength(1));
    });
  });

  group('FollowAreaStore and RoomPrefStore', () {
    test('areas use the store.md §2 identity', () async {
      await store.followAreas.follow(FollowedArea(platform: 'Douyu', areaId: ' 1 ', namespace: 'ignored'));
      await store.followAreas.follow(FollowedArea(platform: 'missevan', areaId: '7', namespace: 'Tag'));
      await store.followAreas.follow(FollowedArea(platform: 'missevan', areaId: '7', namespace: 'catalog'));
      await store.followAreas.follow(FollowedArea(platform: 'douyu', areaId: '1', areaName: 'LOL'));
      final areas = await store.followAreas.all();
      expect(areas.map((area) => area.key), ['douyu||1', 'missevan|tag|7', 'missevan|catalog|7']);
      expect(areas.first.areaName, 'LOL');
      expect(await store.followAreas.unfollow(areas.first), isTrue);
    });

    test('GEO-7: a room orientation override is stored and automatic removes it', () async {
      final ref = RoomRef('douyu', '1');
      expect(await store.roomPrefs.portraitOverrideOf(ref), PortraitOverride.automatic);
      await store.roomPrefs.setPortraitOverride(ref, PortraitOverride.portrait);
      expect(await store.roomPrefs.portraitOverrideOf(ref), PortraitOverride.portrait);
      expect(await store.roomPrefs.get(ref, RoomPrefStore.portraitLayout), 'portrait', reason: '3.x names');
      await store.roomPrefs.setPortraitOverride(ref, PortraitOverride.automatic);
      expect(await store.roomPrefs.get(ref, RoomPrefStore.portraitLayout), isNull);
    });

    test('room volume is clamped and removable', () async {
      final ref = RoomRef('douyu', '1');
      expect(await store.roomPrefs.volumeOf(ref), isNull);
      await store.roomPrefs.setVolume(ref, 1.5);
      expect(await store.roomPrefs.volumeOf(ref), 1);
      await store.roomPrefs.setVolume(ref, null);
      expect(await store.roomPrefs.volumeOf(ref), isNull);
    });

    test('live alert opt-outs are stored per room and only as false (F-NEW-01)', () async {
      final muted = RoomRef('douyu', 'AbC');
      final other = RoomRef('douyu', 'abc');
      await store.follows.follow(snapshot('douyu', 'AbC'));
      await store.follows.follow(snapshot('douyu', 'abc'));
      final changes = store.roomPrefs.watchLiveAlertsOff();
      final seen = <Set<RoomRef>>[];
      final subscription = changes.listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await store.roomPrefs.setLiveAlert(muted, enabled: false);
      expect(await store.roomPrefs.liveAlertsOff(), {muted}, reason: 'room ids keep their case');
      expect(await store.roomPrefs.get(muted, RoomPrefStore.liveAlert), isFalse);
      await store.roomPrefs.setLiveAlert(muted, enabled: true);
      expect(await store.roomPrefs.liveAlertsOff(), isEmpty);
      expect(await store.roomPrefs.get(muted, RoomPrefStore.liveAlert), isNull, reason: 'on means "follow the global"');
      await store.roomPrefs.setLiveAlert(other, enabled: true);
      expect(await store.roomPrefs.get(other, RoomPrefStore.liveAlert), isNull);

      await pumpEventQueue();
      expect(seen.first, isEmpty);
      expect(seen, contains(equals({muted})));
      expect(seen.last, isEmpty);
    });
  });

  test('prune removes only unreferenced rooms', () async {
    await store.follows.follow(snapshot('douyu', '1'));
    await store.history.record(snapshot('douyu', '2'));
    await store.follows.follow(snapshot('douyu', '3'));
    await store.follows.unfollow(RoomRef('douyu', '3'));
    expect(await store.rooms.prune(), 1);
    expect(await store.rooms.get(RoomRef('douyu', '1')), isNotNull);
    expect(await store.rooms.get(RoomRef('douyu', '3')), isNull);
  });
}
