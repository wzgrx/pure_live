import 'dart:async';
import 'dart:developer';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';

// "开播提醒" (docs/O-Android系统集成/O01-通知和前台服务/O01.1-开播提醒, design
// in docs/V-需求和反馈/V01-新功能提议/V01.1-开播提醒 L1–L16): while the app
// runs, a followed room that begins a broadcast gets one system
// notification. No check of its own: it reads the follows' refresh passes
// and the recorder's waiting-for-live checks.

/// Posts the go-live notification of one room (Android's
/// `pure_live/live_alerts`).
typedef LiveAlertPoster = Future<void> Function(LiveRoom room);

/// Tells which rooms began a broadcast, once per broadcast (V01.1 L4, L5).
///
/// Every room is remembered by identity with its last known state: a
/// failed request (`unknown`) is no evidence and changes nothing. The first
/// state seen of a room is only remembered (the app's start, a new follow,
/// the switch just turned on: what is live then is not news). A room is new
/// on air when it is live now and
///
/// * was last seen off air (offline, replay, banned, carousel), unless it
///   is the same broadcast: the same start time give or take
///   [sameStartTolerance], or back within [reconnectWindow] of going off
///   air (a stream that dropped and reconnected);
/// * or was last seen live, but its start time moved on by more than
///   [reconnectWindow] (it ended and began again between two checks).
///
/// A quiet observation (a pass the user started and is watching) records
/// the broadcast as known without reporting it.
final class LiveAlertTracker {
  /// Creates the tracker; [now] is the clock (tests).
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A room back on air this soon after going off is the same broadcast
  /// reconnecting; a start time that moved on by more is a new one.
  static const Duration reconnectWindow = Duration(minutes: 15);

  /// Start times this close are the same broadcast (platforms round them,
  /// some compute them from the duration).
  static const Duration sameStartTolerance = Duration(minutes: 2);

  final DateTime Function() _now;
  final Map<String, _Seen> _seen = {};

  /// Takes the states of [rooms]; returns those that began a broadcast
  /// (none when [quiet]).
  List<LiveRoom> observe(Iterable<LiveRoom> rooms, {bool quiet = false}) {
    final now = _now();
    final started = <LiveRoom>[];
    for (final room in rooms) {
      final status = room.effectiveLiveStatus;
      if (status == LiveStatus.unknown) continue;
      final live = status == LiveStatus.live;
      final seen = _seen[room.identityKey];
      if (seen == null) {
        _seen[room.identityKey] = _Seen(live: live, startedAt: live ? room.startedAt : null);
        continue;
      }
      if (!live) {
        if (seen.live) {
          seen
            ..live = false
            ..endedAt = now;
        }
        continue;
      }
      final isNew = seen.live ? _restarted(seen.startedAt, room.startedAt) : !_sameBroadcast(seen, room, now);
      seen.live = true;
      if (isNew) {
        seen
          ..startedAt = room.startedAt
          ..endedAt = null;
        if (!quiet) started.add(room);
      } else {
        seen.startedAt ??= room.startedAt;
      }
    }
    return started;
  }

  /// Forgets every room (the switch turned off: turning it on starts over).
  void forget() => _seen.clear();

  bool _sameBroadcast(_Seen seen, LiveRoom room, DateTime now) {
    final before = seen.startedAt;
    final start = room.startedAt;
    if (before != null && start != null && start.difference(before).abs() <= sameStartTolerance) return true;
    final ended = seen.endedAt;
    return ended != null && now.difference(ended) < reconnectWindow;
  }

  static bool _restarted(DateTime? before, DateTime? now) =>
      before != null && now != null && now.difference(before) > reconnectWindow;
}

final class _Seen {
  new({required this.live, this.startedAt});

  bool live;
  DateTime? startedAt;
  DateTime? endedAt;
}

/// The follows "开播提醒" covers (V01.1 L3): every follow, or with tags
/// chosen ([chosen], `liveAlertTagIds`) those with one of them. A chosen
/// tag that no longer exists does not count; with none left it is every
/// follow again, which is also what the settings show (no tag ticked).
List<LiveRoom> liveAlertRooms(
  List<LiveRoom> follows, {
  required List<String> chosen,
  required List<StoreTag> tags,
  required Map<String, List<String>> assignments,
}) {
  final existing = {for (final tag in tags) tag.id};
  final wanted = {
    for (final id in chosen)
      if (existing.contains(id)) id,
  };
  if (wanted.isEmpty) return follows;
  return [
    for (final room in follows)
      if (assignments[room.identityKey]?.any(wanted.contains) ?? false) room,
  ];
}

/// "开播提醒" over the follows: [observe] takes a refresh pass's rooms,
/// [recorderChecks] turns the recorder's checks into rooms to observe, and
/// the rooms of the covered follows that began a broadcast are [post]ed.
/// Does nothing while the switch is off (and forgets what it saw).
final class LiveAlerts {
  /// Creates the alerts over [settings]; [now] is the clock (tests).
  new({required this.settings, required this.post, DateTime Function()? now}) : tracker = LiveAlertTracker(now: now);

  /// How often the covered follows are checked when "关注自动刷新" is off
  /// (V01.1 L2): Android's shortest periodic background work, low on
  /// battery and traffic.
  static const Duration checkInterval = Duration(minutes: 15);

  /// The settings (`liveAlertEnabled`, `liveAlertTagIds`).
  final SettingsStore settings;

  /// Posts a notification.
  final LiveAlertPoster post;

  /// What was seen.
  final LiveAlertTracker tracker;

  final Map<String, DateTime?> _checks = {};

  /// Whether the switch is on.
  bool get enabled => settings.get(Settings.liveAlertEnabled);

  /// Takes [rooms] (fresh states); posts the ones in [covered] (identity
  /// keys) that began a broadcast. [quiet]: the user started this pass and
  /// sees its result, so nothing is posted.
  void observe(Iterable<LiveRoom> rooms, {required Set<String> covered, bool quiet = false}) {
    if (!enabled) {
      tracker.forget();
      return;
    }
    for (final room in tracker.observe(rooms, quiet: quiet)) {
      if (!covered.contains(room.identityKey)) continue;
      unawaited(
        post(room).catchError((Object error, StackTrace stack) {
          log('Live alert failed: ${room.identityKey}', name: 'LiveAlerts', error: error, stackTrace: stack);
        }),
      );
    }
  }

  /// The rooms the recorder just checked (V01.1 L2, L6): a task whose
  /// `lastLiveCheckAt` moved on and whose check did not fail (a failure
  /// sets `lastFailTime` at the same moment or later), as a room with the
  /// state found. A task seen for the first time only sets the mark.
  List<LiveRoom> recorderChecks(Iterable<RecordTask> tasks) {
    final rooms = <LiveRoom>[];
    for (final task in tasks) {
      final checked = task.lastLiveCheckAt;
      final known = _checks.containsKey(task.taskId);
      final before = _checks[task.taskId];
      _checks[task.taskId] = checked;
      if (!known || checked == null || checked == before) continue;
      final failed = task.lastFailTime;
      if (failed != null && !failed.isBefore(checked)) continue;
      rooms.add(
        LiveRoom(
          platform: task.platform,
          roomId: task.roomId,
          nick: task.nick,
          title: task.title,
          liveStatus: task.liveStatus,
        ),
      );
    }
    return rooms;
  }
}
