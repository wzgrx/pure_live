// O01.1 (V01.1 L3–L6): which follows began a broadcast, once per broadcast.
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/favorite/live_alerts.dart';

import '../../support.dart';

LiveRoom _room(String id, LiveStatus? status, {DateTime? startedAt, String nick = ''}) =>
    LiveRoom(platform: 'douyu', roomId: id, nick: nick, liveStatus: status, startedAt: startedAt);

List<String> _ids(List<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

void main() {
  group('tracker', () {
    late DateTime now;
    late LiveAlertTracker tracker;
    setUp(() {
      now = DateTime.utc(2026, 10, 8, 20);
      tracker = LiveAlertTracker(now: () => now);
    });

    List<String> see(List<LiveRoom> rooms, {bool quiet = false}) => _ids(tracker.observe(rooms, quiet: quiet));

    test('the first state seen is only remembered; off air then live is new, once', () {
      expect(see([_room('1', LiveStatus.offline), _room('2', LiveStatus.live)]), isEmpty);
      expect(see([_room('1', LiveStatus.live), _room('2', LiveStatus.live)]), ['1']);
      expect(see([_room('1', LiveStatus.live), _room('2', LiveStatus.live)]), isEmpty);
    });

    test('a failed request (unknown) is no evidence either way', () {
      see([_room('1', LiveStatus.unknown)]);
      expect(see([_room('1', LiveStatus.live)]), isEmpty, reason: 'unknown first: live is the first state seen');
      expect(see([_room('1', null)]), isEmpty);
      expect(see([_room('1', LiveStatus.live)]), isEmpty, reason: 'live, failed, live: the same broadcast');
      see([_room('2', LiveStatus.offline)]);
      see([_room('2', LiveStatus.unknown)]);
      expect(see([_room('2', LiveStatus.live)]), ['2'], reason: 'offline, failed, live');
    });

    test('replay, carousel and banned are off air; restricted live is live', () {
      for (final (id, off) in [('r', LiveStatus.replay), ('c', LiveStatus.carousel), ('b', LiveStatus.banned)]) {
        see([_room(id, off)]);
        expect(see([_room(id, off)]), isEmpty);
        expect(see([_room(id, LiveStatus.live)]), [id]);
      }
      see([_room('p', LiveStatus.offline)]);
      final paid = LiveRoom(
        platform: 'douyu',
        roomId: 'p',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.paid,
      );
      expect(_ids(tracker.observe([paid])), ['p']);
    });

    test('back within 15 minutes is the same broadcast reconnecting; later it is a new one', () {
      see([_room('1', LiveStatus.offline)]);
      expect(see([_room('1', LiveStatus.live)]), ['1']);
      now = now.add(const Duration(hours: 1));
      see([_room('1', LiveStatus.offline)]);
      now = now.add(const Duration(minutes: 14));
      expect(see([_room('1', LiveStatus.live)]), isEmpty);
      now = now.add(const Duration(hours: 2));
      see([_room('1', LiveStatus.offline)]);
      now = now.add(const Duration(minutes: 16));
      expect(see([_room('1', LiveStatus.live)]), ['1']);
    });

    test('the same start time is the same broadcast, however long it looked off air', () {
      final start = DateTime.utc(2026, 10, 8, 19, 30);
      see([_room('1', LiveStatus.offline)]);
      expect(see([_room('1', LiveStatus.live, startedAt: start)]), ['1']);
      see([_room('1', LiveStatus.offline)]);
      now = now.add(const Duration(hours: 1));
      expect(see([_room('1', LiveStatus.live, startedAt: start.add(const Duration(minutes: 1)))]), isEmpty);
    });

    test('live both times but the start moved on by more than 15 minutes: it began again between checks', () {
      final start = DateTime.utc(2026, 10, 8, 19);
      see([_room('1', LiveStatus.live, startedAt: start)]);
      expect(see([_room('1', LiveStatus.live, startedAt: start.add(const Duration(minutes: 3)))]), isEmpty);
      expect(see([_room('1', LiveStatus.live)]), isEmpty, reason: 'no start time: nothing to compare');
      expect(see([_room('1', LiveStatus.live, startedAt: start.add(const Duration(hours: 3)))]), ['1']);
      expect(see([_room('1', LiveStatus.live, startedAt: start.add(const Duration(hours: 3)))]), isEmpty);
    });

    test('a quiet pass records the broadcast without reporting it, and later passes do not either', () {
      see([_room('1', LiveStatus.offline)]);
      expect(see([_room('1', LiveStatus.live)], quiet: true), isEmpty);
      expect(see([_room('1', LiveStatus.live)]), isEmpty);
    });

    test('forget starts over: the next state is only remembered', () {
      see([_room('1', LiveStatus.offline)]);
      tracker.forget();
      expect(see([_room('1', LiveStatus.live)]), isEmpty);
    });
  });

  group('covered follows', () {
    final follows = [_room('1', null), _room('2', null), _room('3', null)];
    const tags = [StoreTag(id: 'a', name: 'A'), StoreTag(id: 'b', name: 'B')];
    final assignments = {
      'douyu:1': ['a'],
      'douyu:2': ['b'],
    };

    test('no tag chosen: every follow; chosen tags: their follows; deleted tags do not count', () {
      List<String> covered(List<String> chosen) =>
          _ids(liveAlertRooms(follows, chosen: chosen, tags: tags, assignments: assignments));
      expect(covered([]), ['1', '2', '3']);
      expect(covered(['a']), ['1']);
      expect(covered(['a', 'b']), ['1', '2']);
      expect(covered(['gone', 'b']), ['2']);
      expect(covered(['gone']), ['1', '2', '3'], reason: 'nothing chosen is left: as if none were chosen');
    });
  });

  group('alerts', () {
    late LiveStore store;
    late List<String> posted;
    late LiveAlerts alerts;
    setUp(() async {
      store = await LiveStore.memory(cipher: FakeCipher());
      posted = [];
      alerts = LiveAlerts(settings: store.settings, post: (room) async => posted.add(room.roomId));
    });
    tearDown(() => store.close());

    test('off: nothing is posted or remembered', () async {
      alerts
        ..observe([_room('1', LiveStatus.offline)], covered: {'douyu:1'})
        ..observe([_room('1', LiveStatus.live)], covered: {'douyu:1'});
      await pumpEventQueue();
      expect(posted, isEmpty);
      await store.settings.set(Settings.liveAlertEnabled, true);
      alerts.observe([_room('1', LiveStatus.live)], covered: {'douyu:1'});
      await pumpEventQueue();
      expect(posted, isEmpty, reason: 'turned on while live: the first state seen');
    });

    test('on: only covered follows are posted; a failing post is only logged', () async {
      await store.settings.set(Settings.liveAlertEnabled, true);
      alerts
        ..observe([_room('1', LiveStatus.offline), _room('2', LiveStatus.offline)], covered: {'douyu:1'})
        ..observe([_room('1', LiveStatus.live), _room('2', LiveStatus.live)], covered: {'douyu:1'});
      await pumpEventQueue();
      expect(posted, ['1']);

      LiveAlerts(settings: store.settings, post: (_) async => throw StateError('no channel'))
        ..observe([_room('1', LiveStatus.offline)], covered: {'douyu:1'})
        ..observe([_room('1', LiveStatus.live)], covered: {'douyu:1'});
      await pumpEventQueue();
    });

    test("the recorder's checks: a check that moved on and did not fail is a room in the state found", () {
      final at = DateTime.utc(2026, 10, 8, 20);
      final task = RecordTask.fromRoom(_room('9', LiveStatus.offline, nick: 'N'), now: at)..title = 'T';
      expect(alerts.recorderChecks([task]), isEmpty, reason: 'first sight only sets the mark');
      expect(alerts.recorderChecks([task]), isEmpty, reason: 'no check yet');
      task
        ..lastLiveCheckAt = at
        ..liveStatus = LiveStatus.live;
      final rooms = alerts.recorderChecks([task]);
      expect(
        [for (final room in rooms) (room.identityKey, room.nick, room.title, room.liveStatus)],
        [('douyu:9', 'N', 'T', LiveStatus.live)],
      );
      expect(alerts.recorderChecks([task]), isEmpty, reason: 'the same check again');
      final later = at.add(const Duration(minutes: 1));
      task
        ..lastLiveCheckAt = later
        ..markFailure(stage: 'status', error: 'timeout', now: later);
      expect(alerts.recorderChecks([task]), isEmpty, reason: 'the check failed');
      task.lastLiveCheckAt = later.add(const Duration(minutes: 1));
      expect(alerts.recorderChecks([task]), hasLength(1), reason: 'an earlier failure does not count');
    });
  });
}
