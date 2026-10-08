import 'dart:async';
import 'dart:math' as math;

import 'package:live_core/live_core.dart';

/// Loads the current detail of a history room.
typedef HistoryRoomLoader = Future<LiveRoom> Function(LiveRoom room);

/// The detail loader over [sites]: the platform's cheap card refresh where
/// it has one (`LiveSiteRoomRefresher`), else the full detail (3.x always
/// asked for the full detail). A platform without an adapter (retired, or
/// left out of this build) is skipped: [HistoryRoomSkipped], the room stays
/// as stored (I03.2 c7, as the follows do).
HistoryRoomLoader siteHistoryLoader(SiteRegistry sites) => (room) async {
  final site = sites.maybeOf(room.platform);
  if (site == null) throw const HistoryRoomSkipped();
  if (site case final LiveSiteRoomRefresher refresher) {
    return await refresher.getRoomDetailForRefresh(roomId: room.roomId);
  }
  return await site.getRoomDetail(roomId: room.roomId);
};

/// Thrown by a [HistoryRoomLoader] for a room it does not ask about (no
/// adapter): the room is kept as stored and not counted as failed.
final class HistoryRoomSkipped implements Exception {
  /// Creates the signal.
  const new();
}

/// The outcome of [refreshHistoryRooms].
final class HistoryRefreshResult {
  /// Creates the outcome.
  const new({required this.rooms, required this.failed, required this.cancelled, this.skipped = 0});

  /// One room per room asked for that was reached: the fresh detail, or
  /// for a failed one the stored room with its state set to pending
  /// ([LiveRoom.pendingAfterError]), so a stale "live" is not shown.
  final List<LiveRoom> rooms;

  /// Rooms whose detail could not be loaded.
  final int failed;

  /// Whether the refresh stopped before every room was asked.
  final bool cancelled;

  /// Rooms not asked about ([HistoryRoomSkipped]), kept as stored.
  final int skipped;

  /// Rooms refreshed successfully.
  int get succeeded => rooms.length - failed - skipped;
}

/// Refreshes [rooms] with [load], at most [maxConcurrent] at a time and
/// [timeout] per room (3.x `HistoryPage._refreshHistory`: the refresh
/// concurrency setting, 12 s). A room without platform or id fails without
/// a request. [onProgress] gets the number of finished rooms; once
/// [isCancelled] says so no further room is started.
Future<HistoryRefreshResult> refreshHistoryRooms(
  List<LiveRoom> rooms, {
  required HistoryRoomLoader load,
  required int maxConcurrent,
  Duration timeout = const Duration(seconds: 12),
  void Function(int done)? onProgress,
  bool Function()? isCancelled,
}) async {
  final results = List<LiveRoom?>.filled(rooms.length, null);
  var failed = 0;
  var skipped = 0;
  var done = 0;
  var next = 0;
  var cancelled = false;

  Future<void> worker() async {
    while (next < rooms.length) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        return;
      }
      final index = next++;
      final room = rooms[index];
      try {
        if (room.platform.trim().isEmpty || room.roomId.trim().isEmpty) throw StateError('No room identity');
        final fresh = await load(room).timeout(timeout);
        // An answer for another room (a renamed id) is not this entry's.
        results[index] = fresh.hasSameIdentity(room) ? fresh : room.pendingAfterError();
        if (!fresh.hasSameIdentity(room)) failed++;
      } on HistoryRoomSkipped {
        results[index] = room;
        skipped++;
      } on Object {
        results[index] = room.pendingAfterError();
        failed++;
      }
      onProgress?.call(++done);
    }
  }

  final workers = math.max(1, math.min(maxConcurrent, rooms.length));
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return HistoryRefreshResult(rooms: results.nonNulls.toList(), failed: failed, cancelled: cancelled, skipped: skipped);
}
