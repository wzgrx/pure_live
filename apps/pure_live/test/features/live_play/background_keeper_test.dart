// O01.3 (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): what a room away from
// the app keeps and when it tries a failed stream again, on a fake clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/background_keeper.dart';

import 'fake_clock.dart';

const _play = KeeperInput(away: true, status: PlaybackStatus.playing);

KeeperInput _error({
  SourceFailureKind failure = SourceFailureKind.transient,
  bool networkLost = false,
  bool roomStopped = false,
}) => KeeperInput(
  away: true,
  status: PlaybackStatus.error,
  failure: failure,
  networkLost: networkLost,
  roomStopped: roomStopped,
);

void main() {
  late FakeClock clock;
  late int tries;
  late int changes;
  late BackgroundKeeper keeper;
  late List<KeeperInput> afterTry;

  setUp(() {
    clock = FakeClock();
    tries = 0;
    changes = 0;
    afterTry = [];
    keeper = BackgroundKeeper(
      retry: () async {
        tries++;
        // What the room goes through on a try that fails again.
        afterTry.forEach(keeper.update);
      },
      onChanged: () => changes++,
      now: () => clock.now,
      timer: clock.timer,
    );
  });

  tearDown(() => keeper.dispose());

  test('in front nothing is kept, whatever plays', () {
    expect(keeper.update(const KeeperInput(away: false, status: PlaybackStatus.playing)), BackgroundHold.none);
    expect(keeper.update(const KeeperInput(away: false, status: PlaybackStatus.error)), BackgroundHold.none);
    expect(clock.pending, isEmpty);
  });

  test('away and playing: kept; the user pausing lets go and nothing is tried', () {
    expect(keeper.update(_play), BackgroundHold.playing);
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.paused)), BackgroundHold.none);
    expect(clock.pending, isEmpty);
    // Played again from the notification: kept again.
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.buffering)), BackgroundHold.playing);
  });

  test('R1: an open or a reconnect away from the app is still "playing" (the service stays)', () {
    keeper.update(_play);
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.opening)), BackgroundHold.playing);
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.buffering)), BackgroundHold.playing);
  });

  test('C01.5: a room that was not playing when the app left is not kept or tried', () {
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.error)), BackgroundHold.none);
    expect(clock.pending, isEmpty);
    expect(
      keeper.update(const KeeperInput(away: true, status: PlaybackStatus.idle, roomStopped: true)),
      BackgroundHold.none,
    );
  });

  test('R5: a failed stream is tried after 5, 10, 20, 30, 60, 60 s; kept meanwhile', () async {
    keeper.update(_play);
    afterTry = [const KeeperInput(away: true, status: PlaybackStatus.opening), _error()];
    expect(keeper.update(_error()), BackgroundHold.recovering);
    final waits = <int>[];
    for (var i = 0; i < 6; i++) {
      final before = tries;
      final next = clock.pending.reduce((a, b) => a < b ? a : b);
      waits.add(next.inSeconds);
      await clock.advance(next);
      expect(tries, before + 1);
      expect(keeper.hold, BackgroundHold.recovering);
    }
    expect(waits, [5, 10, 20, 30, 60, 60]);
  });

  test('a try that plays resets the pauses; the next failure waits 5 s again', () async {
    keeper
      ..update(_play)
      ..update(_error());
    await clock.advance(const Duration(seconds: 5));
    await clock.advance(const Duration(seconds: 10));
    expect(tries, 2);
    expect(keeper.update(_play), BackgroundHold.playing);
    expect(keeper.tries, 0);
    keeper.update(_error());
    expect(clock.pending, contains(const Duration(seconds: 5)));
  });

  test('R5: after 30 minutes of failing it gives up: nothing kept, no more tries', () async {
    keeper
      ..update(_play)
      ..update(_error());
    afterTry = [_error()];
    await clock.advance(const Duration(minutes: 30));
    expect(keeper.hold, BackgroundHold.none);
    expect(changes, greaterThan(0));
    final made = tries;
    await clock.advance(const Duration(minutes: 5));
    expect(tries, made);
    // It plays again (the user, the refresh): kept again.
    expect(keeper.update(_play), BackgroundHold.playing);
  });

  test('the network gone: kept, no tries of its own (the session looks)', () async {
    keeper.update(_play);
    expect(keeper.update(_error(networkLost: true)), BackgroundHold.recovering);
    await clock.advance(const Duration(minutes: 2));
    expect(tries, 0);
    expect(keeper.hold, BackgroundHold.recovering);
  });

  test('R6: the network back tries a failed stream at once', () async {
    keeper
      ..update(_play)
      ..update(_error())
      ..networkChanged(online: false);
    await clock.advance(Duration.zero);
    expect(tries, 0);
    keeper.networkChanged(online: true);
    await clock.advance(Duration.zero);
    expect(tries, 1);
  });

  test('offline or refused: waits 10 minutes for the broadcast, then lets go', () async {
    keeper.update(_play);
    expect(
      keeper.update(const KeeperInput(away: true, status: PlaybackStatus.idle, roomStopped: true)),
      BackgroundHold.waiting,
    );
    expect(keeper.update(_error(failure: SourceFailureKind.terminal)), BackgroundHold.waiting);
    await clock.advance(const Duration(minutes: 9));
    expect(keeper.hold, BackgroundHold.waiting);
    expect(tries, 0, reason: 'the room refresh starts a broadcast that comes back');
    await clock.advance(const Duration(minutes: 1));
    expect(keeper.hold, BackgroundHold.none);
    expect(changes, 1);
  });

  test('the detail failing (often the network) is tried like a failed stream', () async {
    keeper.update(_play);
    expect(
      keeper.update(const KeeperInput(away: true, status: PlaybackStatus.idle, roomFailed: true)),
      BackgroundHold.recovering,
    );
    await clock.advance(const Duration(seconds: 5));
    expect(tries, 1);
  });

  test('a call (G05.1) keeps things until it ends; then the room plays on', () {
    keeper.update(_play);
    expect(
      keeper.update(const KeeperInput(away: true, status: PlaybackStatus.paused, interrupted: true)),
      BackgroundHold.interrupted,
    );
    expect(keeper.update(const KeeperInput(away: true, status: PlaybackStatus.buffering)), BackgroundHold.playing);
  });

  test('a pause from the notification during a failure stops the tries', () async {
    keeper
      ..update(_play)
      ..update(_error())
      ..markUserPause();
    expect(keeper.hold, BackgroundHold.none);
    // The session stays "error" after a pause.
    expect(keeper.update(_error()), BackgroundHold.none);
    await clock.advance(const Duration(minutes: 5));
    expect(tries, 0);
  });

  test('coming back cancels everything; leaving again starts afresh', () async {
    keeper
      ..update(_play)
      ..update(_error());
    expect(keeper.update(const KeeperInput(away: false, status: PlaybackStatus.error)), BackgroundHold.none);
    expect(clock.pending, isEmpty);
    await clock.advance(const Duration(minutes: 1));
    expect(tries, 0, reason: 'in front the user has the retry button');
    // Left while it showed the error: not tried (C01.5).
    expect(keeper.update(_error()), BackgroundHold.none);
  });
}
