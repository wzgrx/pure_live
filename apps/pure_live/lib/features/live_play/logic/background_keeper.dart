import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

// What a room playing away from the app holds on to (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强,
// record R1–R6): the media notification's foreground service and the
// wake and Wi-Fi locks stay while the room plays, reconnects, waits for
// the broadcast or a call; a stream that failed is tried again; a pause
// of the user's lets everything go.

/// Why the room keeps its foreground service and locks while it is away.
enum BackgroundHold {
  /// Nothing to keep: in front, paused by the user, given up, or never
  /// played since the app left.
  none,

  /// Opening, buffering or playing.
  playing,

  /// The stream failed and is being brought back (by the session, which
  /// looks for a network that is gone, or by the keeper's tries).
  recovering,

  /// The broadcast stopped (offline, ended, refused for now): the room's
  /// periodic refresh may start it again.
  waiting,

  /// A call or another app has the sound and will give it back.
  interrupted,
}

/// What the keeper reads about the room ([BackgroundKeeper.update]).
@immutable
final class KeeperInput {
  /// Creates the snapshot.
  const new({
    required this.away,
    required this.status,
    this.failure,
    this.networkLost = false,
    this.roomStopped = false,
    this.roomFailed = false,
    this.interrupted = false,
  });

  /// The app is out of sight (not picture-in-picture) and the room may
  /// play there (background play, a sleep session).
  final bool away;

  /// The session's status.
  final PlaybackStatus status;

  /// The failure behind [PlaybackStatus.error].
  final SourceFailureKind? failure;

  /// The session found the network gone and keeps looking by itself
  /// (`networkLostCode`).
  final bool networkLost;

  /// The room is not broadcasting or could not be resolved (offline,
  /// unplayable): only the periodic refresh brings it back.
  final bool roomStopped;

  /// The room's detail could not be fetched (often the network).
  final bool roomFailed;

  /// The audio focus paused the room and resumes it when the interruption
  /// ends (G05.1).
  final bool interrupted;

  /// Whether the session plays or is about to.
  bool get active => switch (status) {
    PlaybackStatus.opening || PlaybackStatus.buffering || PlaybackStatus.playing => true,
    _ => false,
  };
}

/// Schedules [callback] after [delay] (tests give a fake clock).
typedef KeeperTimer = Timer Function(Duration delay, void Function() callback);

/// Decides what a room away from the app keeps ([hold]) and tries a failed
/// stream again (O01.3 R1, R5, R6):
///
/// - playing: kept;
/// - failed on its own (not the platform's refusal): [retry] after
///   [retryDelays] (the last one repeats), at once when the network comes
///   back ([networkChanged]); kept meanwhile, for at most [recoverBudget];
/// - the session looks for a network that is gone: kept, no tries of its
///   own, for at most [recoverBudget];
/// - offline, ended or refused: kept for [waitBudget] (the refresh starts
///   a broadcast that comes back);
/// - paused by a call (G05.1): kept for [recoverBudget];
/// - paused by the user ([markUserPause], or a pause that is not a call's):
///   nothing kept, nothing tried until it plays again.
///
/// Only a room that played since the app left is kept or tried (C01.5: a
/// room that was not playing does not start by itself). [onChanged] runs
/// when a timer changed [hold] without an [update].
final class BackgroundKeeper {
  /// Creates the keeper; [retry] reopens the room (the retry button's
  /// command).
  new({
    required this.retry,
    this.onChanged,
    DateTime Function()? now,
    KeeperTimer? timer,
    this.retryDelays = defaultRetryDelays,
    this.recoverBudget = const Duration(minutes: 30),
    this.waitBudget = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new,
       assert(retryDelays.isNotEmpty, 'at least one delay');

  /// The pauses before the keeper's tries.
  static const List<Duration> defaultRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Opens the room again.
  final Future<void> Function() retry;

  /// [hold] changed by a timer.
  final void Function()? onChanged;

  /// The pauses before each try; the last repeats.
  final List<Duration> retryDelays;

  /// How long a failed stream, a missing network or a call keeps things.
  final Duration recoverBudget;

  /// How long a stopped broadcast keeps things.
  final Duration waitBudget;

  final DateTime Function() _now;
  final KeeperTimer _timer;

  KeeperInput? _input;
  BackgroundHold _hold = BackgroundHold.none;
  bool _played = false;
  bool _userPaused = false;
  bool _gaveUp = false;
  DateTime? _troubleSince;
  Timer? _retryTimer;
  Timer? _budgetTimer;
  bool _retrying = false;
  int _tries = 0;
  bool _disposed = false;

  /// What is kept now.
  BackgroundHold get hold => _hold;

  /// The keeper's tries since the stream last played.
  int get tries => _tries;

  /// Whether a try is scheduled.
  @visibleForTesting
  bool get retryPending => _retryTimer != null;

  /// Takes the room's state; returns [hold].
  BackgroundHold update(KeeperInput input) {
    if (_disposed) return _hold = BackgroundHold.none;
    final previous = _input;
    _input = input;
    if (!input.away) {
      _reset();
      return _hold = BackgroundHold.none;
    }
    if (previous == null || !previous.away) {
      // The app just left: only what was playing then may be kept.
      _played = input.active;
      _userPaused = false;
      _gaveUp = false;
    }
    return _hold = _decide(input);
  }

  BackgroundHold _decide(KeeperInput input) {
    if (input.active) {
      _played = true;
      _userPaused = false;
      _gaveUp = false;
      _cancelTimers();
      // Opening or buffering may still fail: the budget and the pauses
      // between tries start again only once it plays.
      if (input.status == PlaybackStatus.playing) {
        _troubleSince = null;
        _tries = 0;
      }
      return BackgroundHold.playing;
    }
    if (!_played || _userPaused || _gaveUp) {
      _cancelTimers();
      return BackgroundHold.none;
    }
    final BackgroundHold trouble;
    final Duration budget;
    var tryAgain = false;
    switch (input.status) {
      case PlaybackStatus.paused:
        if (!input.interrupted) {
          // A pause that is not a call's is the user's (notification,
          // lock screen, headphones, the sleep timer).
          _userPaused = true;
          _cancelTimers();
          return BackgroundHold.none;
        }
        trouble = BackgroundHold.interrupted;
        budget = recoverBudget;
      case PlaybackStatus.error when input.failure == SourceFailureKind.terminal || input.roomStopped:
        trouble = BackgroundHold.waiting;
        budget = waitBudget;
      case PlaybackStatus.error:
        trouble = BackgroundHold.recovering;
        budget = recoverBudget;
        tryAgain = !input.networkLost;
      case _ when input.roomFailed:
        trouble = BackgroundHold.recovering;
        budget = recoverBudget;
        tryAgain = true;
      case _:
        // Idle, stopped or completed: a reload between two opens, or a
        // broadcast that ended.
        trouble = BackgroundHold.waiting;
        budget = waitBudget;
    }
    final since = _troubleSince ??= _now();
    final left = budget - _now().difference(since);
    if (left <= Duration.zero) {
      _giveUp();
      return BackgroundHold.none;
    }
    _budgetTimer?.cancel();
    _budgetTimer = _timer(left, _onBudget);
    if (tryAgain) {
      _scheduleTry();
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    return trouble;
  }

  void _scheduleTry({Duration? delay}) {
    if (_retryTimer != null || _retrying) return;
    final wait = delay ?? retryDelays[_tries.clamp(0, retryDelays.length - 1)];
    _retryTimer = _timer(wait, () {
      _retryTimer = null;
      unawaited(_try());
    });
  }

  Future<void> _try() async {
    final input = _input;
    if (_disposed || input == null || !input.away || _userPaused || _gaveUp || input.active) return;
    _tries++;
    _retrying = true;
    try {
      await retry();
    } on Object catch (error) {
      developer.log('Background retry failed', name: 'LivePlay', error: error);
    } finally {
      _retrying = false;
    }
    // Still failed and nothing new arrived: the next try.
    final now = _input;
    if (!_disposed && now != null && now.away && _hold == BackgroundHold.recovering && !now.active) {
      _hold = _decide(now);
      onChanged?.call();
    }
  }

  void _onBudget() {
    _budgetTimer = null;
    final input = _input;
    if (_disposed || input == null || !input.away || input.active) return;
    final since = _troubleSince;
    if (since == null) return;
    _hold = _decide(input);
    onChanged?.call();
  }

  void _giveUp() {
    _gaveUp = true;
    _cancelTimers();
  }

  /// The user paused or stopped from the notification or the lock screen:
  /// nothing is kept or tried until the room plays again.
  void markUserPause() {
    _userPaused = true;
    _cancelTimers();
    if (_hold != BackgroundHold.none && !(_input?.active ?? false)) {
      _hold = BackgroundHold.none;
    }
  }

  /// The network changed: a failed stream away from the app is tried at
  /// once when there is a network ([online]).
  void networkChanged({required bool online}) {
    final input = _input;
    if (_disposed || !online || input == null || !input.away) return;
    if (_hold != BackgroundHold.recovering || input.networkLost || input.active) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _scheduleTry(delay: Duration.zero);
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _budgetTimer?.cancel();
    _budgetTimer = null;
  }

  void _reset() {
    _cancelTimers();
    _played = false;
    _userPaused = false;
    _gaveUp = false;
    _troubleSince = null;
    _tries = 0;
  }

  /// Stops every timer.
  void dispose() {
    _disposed = true;
    _reset();
    _hold = BackgroundHold.none;
  }
}
