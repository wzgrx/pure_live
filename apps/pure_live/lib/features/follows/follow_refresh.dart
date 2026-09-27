import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';

/// Followed rooms as stored, newest state first; the page never waits for the
/// network to show them.
final followsProvider = StreamProvider<List<FollowedRoom>>((ref) => ref.watch(storeProvider).follows.watchAll());

/// Result of one refresh of the follows' live states.
final class FollowRefreshResult {
  const new({required this.checked, required this.failedPlatforms});

  /// Rooms whose state was fetched.
  final int checked;

  /// Platforms that failed, for the banner (principles §4.1: 平台异常时顶部显示横幅).
  final Set<String> failedPlatforms;
}

/// Refreshes the live state of every followed room and writes the results to
/// the store; the list updates through [followsProvider].
class FollowRefreshNotifier extends AsyncNotifier<FollowRefreshResult?> {
  Timer? _timer;

  @override
  Future<FollowRefreshResult?> build() {
    final settings = ref.read(storeProvider).settings;
    // Refresh when the app comes back (default on) and on a timer (default
    // off), as the 3.x settings did; the interval is in minutes.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (settings.get(Settings.refreshFollowsOnResume)) unawaited(refresh());
      },
    );
    void schedule() {
      _timer?.cancel();
      _timer = settings.get(Settings.autoRefreshFollows)
          ? Timer.periodic(Duration(minutes: settings.get(Settings.autoRefreshInterval)), (_) => unawaited(refresh()))
          : null;
    }

    schedule();
    final changes = settings.changes
        .where((id) => id == Settings.autoRefreshFollows.id || id == Settings.autoRefreshInterval.id)
        .listen((_) => schedule());
    ref.onDispose(() {
      lifecycle.dispose();
      _timer?.cancel();
      unawaited(changes.cancel());
    });
    return refresh();
  }

  /// Fetches every followed room's detail.
  Future<FollowRefreshResult> refresh() async {
    final store = ref.read(storeProvider);
    final sites = ref.read(sitesProvider);
    final follows = await store.follows.all();
    final queue = [...follows.map((follow) => follow.ref).where((room) => sites.containsKey(room.platform))];
    final snapshots = <RoomSnapshot>[];
    final failed = <String>{};

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final room = queue.removeLast();
        try {
          final detail = await sites[room.platform]!.rooms.detail(room);
          snapshots.add(RoomSnapshot.fromDetail(detail));
        } on NotFound {
          // A removed room keeps its last known card; the row says so later.
        } on Object {
          failed.add(room.platform);
        }
      }
    }

    // Requests in flight at once, so a long follow list does not trip rate limits.
    final concurrency = store.settings.get(Settings.maxConcurrentRefresh);
    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    if (snapshots.isNotEmpty) await store.rooms.update(snapshots);
    final result = FollowRefreshResult(checked: snapshots.length, failedPlatforms: failed);
    if (ref.mounted) state = AsyncData(result);
    return result;
  }
}

/// The follows' refresh state.
final followRefreshProvider = AsyncNotifierProvider<FollowRefreshNotifier, FollowRefreshResult?>(
  FollowRefreshNotifier.new,
);
