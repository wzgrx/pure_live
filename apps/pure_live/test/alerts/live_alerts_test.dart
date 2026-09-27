import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';

import '../fakes.dart';
import 'fake_notifier.dart';

final _now = DateTime.utc(2026, 9, 28, 20);

FollowedRoom _follow(String roomId, LiveState? state, {String platform = 'douyu', String? name}) => FollowedRoom(
  room: StoredRoom(
    ref: RoomRef(platform, roomId),
    anchorName: name ?? '主播$roomId',
    title: '',
    updatedAt: _now,
    lastState: state,
  ),
  followedAt: _now,
  order: 0,
);

LiveObservation _seen(String roomId, {LiveState state = LiveState.live, DateTime? since, String platform = 'douyu'}) =>
    LiveObservation(
      ref: RoomRef(platform, roomId),
      state: state,
      anchorName: '主播$roomId',
      title: '标题$roomId',
      liveSince: since,
    );

LiveAlertPlan _plan(
  List<FollowedRoom> before,
  List<LiveObservation> observed, {
  Set<RoomRef> optedOut = const {},
  Map<String, LiveAlertRecord> records = const {},
  DateTime? now,
}) => planLiveAlerts(before: before, observed: observed, optedOut: optedOut, records: records, now: now ?? _now);

List<String> _ids(LiveAlertPlan plan) => [for (final alert in plan.alerts) alert.ref.roomId];

void main() {
  group('state changes', () {
    test('only rooms stored as not live and now seen live are announced', () {
      final plan = _plan(
        [
          _follow('offline', LiveState.offline),
          _follow('replay', LiveState.replay),
          _follow('live', LiveState.live),
          _follow('unknown', null),
          _follow('stays', LiveState.offline),
          _follow('missing', LiveState.offline),
        ],
        [_seen('offline'), _seen('replay'), _seen('live'), _seen('unknown'), _seen('stays', state: LiveState.offline)],
      );
      expect(_ids(plan), ['offline', 'replay'], reason: 'follow order; unknown and still-live rooms are not news');
      expect(plan.records.keys, {'douyu:offline', 'douyu:replay'});
      expect(plan.records['douyu:offline']!.notifiedAt, _now);
    });

    test('a room that opted out is never announced; the others still are', () {
      final plan = _plan(
        [_follow('a', LiveState.offline), _follow('b', LiveState.offline)],
        [_seen('a'), _seen('b')],
        optedOut: {RoomRef('douyu', 'b')},
      );
      expect(_ids(plan), ['a']);
      expect(plan.records.keys, {'douyu:a'}, reason: 'no record, so turning it back on works for the next broadcast');
    });

    test('IPTV channels are never announced', () {
      final channel = IptvSite.refOf('CCTV-1');
      final plan = _plan(
        [_follow(channel.roomId, LiveState.offline, platform: IptvSite.platformId)],
        [_seen(channel.roomId, platform: IptvSite.platformId)],
      );
      expect(plan.alerts, isEmpty);
    });

    test('the stored name stands in when the page has none', () {
      final plan = _plan(
        [_follow('a', LiveState.offline, name: '存储的名字')],
        [LiveObservation(ref: RoomRef('douyu', 'a'), state: LiveState.live)],
      );
      expect(plan.alerts.single.anchorName, '存储的名字');
    });
  });

  group('one alert per broadcast', () {
    final since = _now.subtract(const Duration(minutes: 5));

    test('the same start time is the same broadcast, even after a restart', () {
      final records = {
        'douyu:a': LiveAlertRecord(notifiedAt: _now.subtract(const Duration(hours: 3)), liveSince: since),
      };
      // The stored state flipped to offline in between (a failed check), the
      // start time did not change.
      final again = _plan(
        [_follow('a', LiveState.offline)],
        [_seen('a', since: since.add(const Duration(seconds: 50)))],
        records: records,
      );
      expect(again.alerts, isEmpty);
      expect(again.records, records, reason: 'the record is kept as it was');

      final restarted = _plan(
        [_follow('a', LiveState.offline)],
        [_seen('a', since: since.add(const Duration(hours: 2)))],
        records: records,
      );
      expect(_ids(restarted), ['a'], reason: 'a new start time is a new broadcast');
      expect(restarted.records['douyu:a']!.liveSince, since.add(const Duration(hours: 2)));
    });

    test('without start times a quiet period applies', () {
      final records = {'douyu:a': LiveAlertRecord(notifiedAt: _now.subtract(const Duration(minutes: 20)))};
      expect(_plan([_follow('a', LiveState.offline)], [_seen('a')], records: records).alerts, isEmpty);
      final later = _plan(
        [_follow('a', LiveState.offline)],
        [_seen('a')],
        records: records,
        now: _now.add(const Duration(minutes: 11)),
      );
      expect(_ids(later), ['a']);
    });

    test('records of unfollowed rooms and old records are dropped', () {
      final plan = _plan(
        [_follow('a', LiveState.live), _follow('b', LiveState.live)],
        const [],
        records: {
          'douyu:a': LiveAlertRecord(notifiedAt: _now.subtract(const Duration(days: 1))),
          'douyu:b': LiveAlertRecord(notifiedAt: _now.subtract(const Duration(days: 8))),
          'douyu:gone': LiveAlertRecord(notifiedAt: _now),
        },
      );
      expect(plan.records.keys, {'douyu:a'});
    });

    test('records survive JSON', () {
      final record = LiveAlertRecord(notifiedAt: _now, liveSince: since);
      expect(LiveAlertRecord.fromJson(record.toJson()), record);
      expect(LiveAlertRecord.fromJson(LiveAlertRecord(notifiedAt: _now).toJson())!.liveSince, isNull);
      expect(LiveAlertRecord.fromJson({'since': 1}), isNull);
      expect(LiveAlertRecord.fromJson('x'), isNull);
    });
  });

  group('notices', () {
    test('up to three rooms get one notice each that opens the room', () {
      final notices = liveAlertNotices([
        _seen('1'),
        _seen('2'),
        LiveObservation(ref: RoomRef('huya', '3'), state: LiveState.live),
      ]);
      expect(notices, hasLength(3));
      expect(notices.first.title, '主播1 开播了');
      expect(notices.first.body, '斗鱼 · 标题1');
      expect(notices.first.payload, roomLocation(RoomRef('douyu', '1')));
      expect(notices.first.channel, AlertChannel.live);
      expect(notices.last.title, '3 开播了', reason: 'the room id stands in for a missing name');
      expect(notices.last.body, '虎牙');
      expect(notices.map((notice) => notice.id).toSet(), hasLength(3));
      expect(liveAlertNotices([_seen('1')]).single.id, notices.first.id, reason: 'a room replaces its own notice');
    });

    test('more than three are combined into one notice that opens the live tab', () {
      final notices = liveAlertNotices([for (var i = 1; i <= 4; i++) _seen('$i')]);
      expect(notices, hasLength(1));
      expect(notices.single.title, '主播1等 4 位主播开播了');
      expect(notices.single.body, '主播1、主播2、主播3、主播4');
      expect(notices.single.payload, followsLiveLocation);
      final many = liveAlertNotices([for (var i = 1; i <= 8; i++) _seen('$i')]).single;
      expect(many.title, '主播1等 8 位主播开播了');
      expect(many.body, '主播1、主播2、主播3、主播4、主播5、主播6 等');
      expect(liveAlertNotices(const []), isEmpty);
    });
  });

  group('service', () {
    late LiveStore store;
    late FakeAlertNotifier notifier;
    late AppLog log;

    setUp(() async {
      store = await LiveStore.inMemory();
      notifier = FakeAlertNotifier();
      log = AppLog.memory();
      for (final id in ['a', 'b']) {
        await store.follows.follow(
          RoomSnapshot(ref: RoomRef('douyu', id), anchorName: '主播$id', state: LiveState.offline),
        );
      }
    });
    tearDown(() => store.close());

    LiveAlertService service({DateTime? now}) =>
        LiveAlertService(store: store, notifier: notifier, log: log, now: () => now ?? _now);

    test('nothing while the global switch is off (the default)', () async {
      final shown = await service().afterRefresh(await store.follows.all(), [_seen('a')]);
      expect(shown, isEmpty);
      expect(notifier.shown, isEmpty);
      expect(await store.meta.get(LiveAlertRules.recordsKey), isNull);
    });

    test('announces, stores the record first, and a cold start does not repeat it', () async {
      await store.settings.set(Settings.liveAlerts, true);
      final since = _now.subtract(const Duration(minutes: 3));
      final before = await store.follows.all();
      await service().afterRefresh(before, [_seen('a', since: since), _seen('b', state: LiveState.offline)]);
      expect(notifier.shown.map((notice) => notice.title), ['主播a 开播了']);
      expect(await store.meta.get(LiveAlertRules.recordsKey), isNotNull);

      // A new process: a new service reads the stored record. The stored
      // state still says offline, as if the first run died before saving it.
      final restarted = service(now: _now.add(const Duration(hours: 1)));
      final again = await restarted.afterRefresh(before, [_seen('a', since: since)]);
      expect(again, isEmpty);
      expect(notifier.shown, hasLength(1));
    });

    test('rooms that opted out stay quiet', () async {
      await store.settings.set(Settings.liveAlerts, true);
      await store.roomPrefs.setLiveAlert(RoomRef('douyu', 'b'), enabled: false);
      await service().afterRefresh(await store.follows.all(), [_seen('a'), _seen('b')]);
      expect(notifier.shown.map((notice) => notice.title), ['主播a 开播了']);
    });

    test('a failing notification is logged, not thrown', () async {
      await store.settings.set(Settings.liveAlerts, true);
      notifier.failShow = true;
      final shown = await service().afterRefresh(await store.follows.all(), [_seen('a')]);
      expect(shown, hasLength(1));
      expect(log.recent.any((line) => line.contains('notification failed')), isTrue);
    });

    test('platforms without notifications skip silently', () async {
      await store.settings.set(Settings.liveAlerts, true);
      final quiet = LiveAlertService(store: store, notifier: const NoAlertNotifier(), log: log, now: () => _now);
      expect(await quiet.afterRefresh(await store.follows.all(), [_seen('a')]), isEmpty);
      expect(await store.meta.get(LiveAlertRules.recordsKey), isNull);
    });
  });

  group('follow refresh', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('a refresh that sees rooms go live announces them once', () async {
      final store = await LiveStore.inMemory();
      addTearDown(store.close);
      await store.settings.set(Settings.liveAlerts, true);
      for (final id in ['a', 'b', 'c']) {
        await store.follows.follow(
          RoomSnapshot(ref: RoomRef('douyu', id), anchorName: '主播$id', state: LiveState.offline),
        );
      }
      await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', 'new'), anchorName: '新关注'));
      await store.roomPrefs.setLiveAlert(RoomRef('douyu', 'c'), enabled: false);
      final site = FakeSite('douyu', offline: {'b'});
      final notifier = FakeAlertNotifier();
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
          alertNotifierProvider.overrideWithValue(notifier),
        ],
      );
      addTearDown(container.dispose);

      // The first refresh runs when the provider starts, as on a cold start.
      await container.read(followRefreshProvider.future);
      await pumpEventQueue();
      expect(notifier.shown.map((notice) => notice.title), ['主播a 开播了'], reason: 'b offline, c opted out, new unknown');
      expect((await store.rooms.get(RoomRef('douyu', 'a')))!.lastState, LiveState.live);

      site.offline.clear();
      await container.read(followRefreshProvider.notifier).refresh();
      expect(notifier.shown.map((notice) => notice.title), ['主播a 开播了', '主播b 开播了']);

      await container.read(followRefreshProvider.notifier).refresh();
      expect(notifier.shown, hasLength(2), reason: 'still live is not news');
    });
  });
}
