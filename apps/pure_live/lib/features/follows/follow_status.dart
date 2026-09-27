import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';

/// The remembered order of the follows page (F-FAV-01).
final followSortSetting = NotifierProvider<SettingNotifier<FollowSort>, FollowSort>(
  () => SettingNotifier(Settings.followSort),
);

/// What the follows page says about one follow (spec/product.md F-FAV-03,
/// F-FAV-08).
enum FollowStatus {
  /// The first refresh after launch is running: no state is shown yet.
  checking,

  /// Broadcasting.
  live,

  /// Not broadcasting.
  offline,

  /// Playing a loop or a recording.
  replay,

  /// The state could not be fetched; the stored one is not shown.
  unknown,

  /// The platform says the room does not exist.
  missing,

  /// This build has no adapter for the platform.
  unsupported,
}

/// What this run knows about the follows' states (F-FAV-03): the stored
/// state is a cache from an earlier run until the first refresh publishes,
/// and a room whose refresh failed shows as unknown until its data is newer
/// than that refresh.
final class FollowSession {
  const new({this.checking = false, this.result, this.failed = false});

  /// The session of a refresh state: checking while the first pass has no
  /// result; a pass that failed as a whole leaves every state unknown.
  factory of(AsyncValue<FollowRefreshResult?> refresh) => FollowSession(
    checking: refresh.isLoading && !refresh.hasValue,
    result: refresh.value,
    failed: refresh.hasError && !refresh.hasValue,
  );

  /// The first refresh is running.
  final bool checking;

  /// The latest published refresh; null when none ran (the stored states
  /// are taken as they are).
  final FollowRefreshResult? result;

  /// The first refresh failed as a whole.
  final bool failed;

  /// The status of [follow]; [supported] is whether this build has the
  /// platform's adapter.
  FollowStatus statusOf(FollowedRoom follow, {required bool supported}) {
    if (!supported) return FollowStatus.unsupported;
    if (checking) return FollowStatus.checking;
    final key = follow.ref.key;
    final result = this.result;
    final at = result?.at;
    // Data written after the refresh (the room was opened or followed again)
    // is this run's own observation.
    final newer = at != null && follow.room.updatedAt.isAfter(at);
    if (!newer) {
      if (failed) return FollowStatus.unknown;
      if (result != null && result.missing.contains(key)) return FollowStatus.missing;
      if (result != null && result.failed.contains(key)) return FollowStatus.unknown;
    }
    return switch (follow.room.lastState) {
      LiveState.live => FollowStatus.live,
      LiveState.offline => FollowStatus.offline,
      LiveState.replay => FollowStatus.replay,
      null => FollowStatus.unknown,
    };
  }

  /// When the broadcast of live [follow] started, if the refresh learned it.
  DateTime? liveSince(FollowedRoom follow) => result?.liveSince[follow.ref.key];
}

/// A follow with its status.
typedef FollowEntry = ({FollowedRoom follow, FollowStatus status});

/// Audience used for ordering: the first figure the platform reports.
int _audience(FollowedRoom follow) {
  final audience = follow.room.audience;
  return audience.online ?? audience.popularity ?? audience.cumulative ?? 0;
}

int _custom(FollowEntry a, FollowEntry b) {
  final order = a.follow.order.compareTo(b.follow.order);
  return order != 0 ? order : a.follow.followedAt.compareTo(b.follow.followedAt);
}

/// Later first, missing times last.
int _later(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
  return b.compareTo(a);
}

/// Orders the live cards (spec/product.md F-FAV-01, principles §4.1):
/// audience; start time (latest first, unknown times after, by audience);
/// platform order then audience; or the custom order. Ties keep the custom
/// order, so the list never shuffles between refreshes.
List<FollowEntry> sortLive(
  Iterable<FollowEntry> live,
  FollowSort sort, {
  required List<String> platforms,
  DateTime? Function(FollowedRoom follow)? liveSince,
}) {
  int rank(FollowEntry entry) {
    final index = platforms.indexOf(entry.follow.ref.platform);
    return index < 0 ? platforms.length : index;
  }

  int byAudience(FollowEntry a, FollowEntry b) => _audience(b.follow).compareTo(_audience(a.follow));
  return [...live]..sort((a, b) {
    final first = switch (sort) {
      FollowSort.audience => byAudience(a, b),
      FollowSort.liveTime => _later(liveSince?.call(a.follow), liveSince?.call(b.follow)),
      FollowSort.platform => rank(a).compareTo(rank(b)),
      FollowSort.custom => 0,
    };
    if (first != 0) return first;
    final second = switch (sort) {
      FollowSort.liveTime || FollowSort.platform => byAudience(a, b),
      _ => 0,
    };
    return second != 0 ? second : _custom(a, b);
  });
}

/// Orders the compact rows: by when they were last live (latest first),
/// except the platform and custom orders (F-FAV-01).
List<FollowEntry> sortRows(Iterable<FollowEntry> rows, FollowSort sort, {required List<String> platforms}) {
  int rank(FollowEntry entry) {
    final index = platforms.indexOf(entry.follow.ref.platform);
    return index < 0 ? platforms.length : index;
  }

  return [...rows]..sort((a, b) {
    final first = switch (sort) {
      FollowSort.platform => rank(a).compareTo(rank(b)),
      FollowSort.custom => 0,
      FollowSort.audience || FollowSort.liveTime => 0,
    };
    if (first != 0) return first;
    final second = sort == FollowSort.custom ? 0 : _later(a.follow.room.lastLiveAt, b.follow.room.lastLiveAt);
    return second != 0 ? second : _custom(a, b);
  });
}
