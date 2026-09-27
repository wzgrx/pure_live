import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follow_status.dart';

final _t0 = DateTime.utc(2026, 9, 28, 12);

FollowedRoom follow(
  String id, {
  String platform = 'douyu',
  LiveState? state = LiveState.live,
  int? online,
  int order = 0,
  DateTime? lastLiveAt,
  DateTime? updatedAt,
}) => FollowedRoom(
  room: StoredRoom(
    ref: RoomRef(platform, id),
    anchorName: '主播$id',
    title: '标题$id',
    updatedAt: updatedAt ?? _t0,
    audience: Audience(online: online),
    lastState: state,
    lastLiveAt: lastLiveAt,
  ),
  followedAt: _t0,
  order: order,
);

FollowEntry entry(FollowedRoom follow, [FollowStatus status = FollowStatus.live]) => (follow: follow, status: status);

List<String> ids(List<FollowEntry> entries) => [for (final entry in entries) entry.follow.ref.roomId];

void main() {
  group('F-FAV-03 session', () {
    test('while the first refresh runs every supported follow is checking, whatever was stored', () {
      final session = FollowSession.of(const AsyncLoading<FollowRefreshResult?>());
      expect(session.checking, isTrue);
      expect(session.statusOf(follow('1'), supported: true), FollowStatus.checking);
      expect(session.statusOf(follow('2', platform: 'huajiao'), supported: false), FollowStatus.unsupported);
    });

    test('after it publishes, failures are unknown and missing rooms say so; later data wins', () {
      final at = _t0.add(const Duration(minutes: 1));
      final session = FollowSession.of(
        AsyncData(
          FollowRefreshResult(
            checked: 1,
            failedPlatforms: const {'huya'},
            failed: {'huya:2'},
            missing: {'douyu:3'},
            at: at,
          ),
        ),
      );
      expect(session.checking, isFalse);
      expect(session.statusOf(follow('1'), supported: true), FollowStatus.live);
      expect(session.statusOf(follow('1', state: LiveState.offline), supported: true), FollowStatus.offline);
      expect(session.statusOf(follow('1', state: LiveState.replay), supported: true), FollowStatus.replay);
      expect(session.statusOf(follow('1', state: null), supported: true), FollowStatus.unknown);
      expect(
        session.statusOf(follow('2', platform: 'huya'), supported: true),
        FollowStatus.unknown,
        reason: 'never the state of an earlier run',
      );
      expect(session.statusOf(follow('3'), supported: true), FollowStatus.missing);
      expect(
        session.statusOf(follow('2', platform: 'huya', updatedAt: at.add(const Duration(seconds: 5))), supported: true),
        FollowStatus.live,
        reason: 'the room was opened after the refresh: its data is fresh',
      );
    });

    test('a first refresh that failed as a whole leaves every state unknown', () {
      final session = FollowSession.of(AsyncError<FollowRefreshResult?>(StateError('db'), StackTrace.empty));
      expect(session.statusOf(follow('1'), supported: true), FollowStatus.unknown);
    });

    test('no refresh at all (tests, overrides) takes the stored states as they are', () {
      const session = FollowSession();
      expect(session.statusOf(follow('1'), supported: true), FollowStatus.live);
    });
  });

  group('F-FAV-01 order', () {
    const platforms = ['bilibili', 'douyu', 'huya'];
    final a = entry(follow('a', online: 10, order: 2));
    final b = entry(follow('b', platform: 'huya', online: 30));
    final c = entry(follow('c', platform: 'bilibili', online: 20, order: 1));
    final d = entry(follow('d', platform: 'huajiao', online: 99, order: 3));

    test('audience, platform and custom', () {
      expect(ids(sortLive([a, b, c, d], FollowSort.audience, platforms: platforms)), ['d', 'b', 'c', 'a']);
      expect(ids(sortLive([a, b, c, d], FollowSort.platform, platforms: platforms)), [
        'c',
        'a',
        'b',
        'd',
      ], reason: 'platforms outside the order go last');
      expect(ids(sortLive([a, b, c, d], FollowSort.custom, platforms: platforms)), ['b', 'c', 'a', 'd']);
    });

    test('start time: latest first, unknown times after by audience', () {
      final since = {'douyu:a': _t0, 'huya:b': _t0.subtract(const Duration(hours: 1))};
      final sorted = sortLive(
        [a, b, c, d],
        FollowSort.liveTime,
        platforms: platforms,
        liveSince: (follow) => since[follow.ref.key],
      );
      expect(ids(sorted), ['a', 'b', 'd', 'c']);
    });

    test('rows go by last live time except for the platform and custom orders', () {
      final old = entry(follow('old', state: LiveState.offline, lastLiveAt: _t0.subtract(const Duration(days: 2))));
      final recent = entry(follow('recent', platform: 'bilibili', state: LiveState.offline, order: 1, lastLiveAt: _t0));
      final never = entry(follow('never', platform: 'huya', state: LiveState.offline, order: 2));
      final rows = [old, never, recent];
      expect(ids(sortRows(rows, FollowSort.audience, platforms: platforms)), ['recent', 'old', 'never']);
      expect(ids(sortRows(rows, FollowSort.liveTime, platforms: platforms)), ['recent', 'old', 'never']);
      expect(ids(sortRows(rows, FollowSort.platform, platforms: platforms)), ['recent', 'old', 'never']);
      expect(ids(sortRows(rows, FollowSort.custom, platforms: platforms)), ['old', 'recent', 'never']);
    });
  });
}
