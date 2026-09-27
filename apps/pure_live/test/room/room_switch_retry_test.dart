import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart' show TransportFailure, TransportReason;
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/retry.dart';
import 'package:pure_live_app/features/room/room_switch.dart';

FollowedRoom _follow(String id, LiveState state) => FollowedRoom(
  room: StoredRoom(
    ref: RoomRef('douyu', id),
    anchorName: '主播$id',
    title: '',
    updatedAt: DateTime(2026),
    lastState: state,
  ),
  order: 0,
  followedAt: DateTime(2026),
);

void main() {
  test('room details retry only network failures, twice', () {
    expect(networkRetry(0, const NetworkFailure('x')), const Duration(seconds: 1));
    expect(networkRetry(1, const NetworkFailure('x')), const Duration(seconds: 2));
    expect(networkRetry(2, const NetworkFailure('x')), isNull);
    expect(networkRetry(0, const NotFound('x')), isNull);
    expect(networkRetry(0, StateError('x')), isNull);
    expect(networkRetry(0, const TransportFailure('douyu', TransportReason.timeout)), isNotNull);
  });

  test('F-FAV-03: the switch list follows what this run checked', () {
    final follows = [_follow('1', LiveState.live), _follow('2', LiveState.offline)];
    expect(liveFollowEntries(follows).map((entry) => entry.ref.roomId), ['1']);
    expect(liveFollowEntries(follows, isLive: (_) => false), isEmpty);
  });
}
