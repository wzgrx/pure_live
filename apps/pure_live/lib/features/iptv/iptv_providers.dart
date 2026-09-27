import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_repository.dart';
import 'package:pure_live_app/features/iptv/iptv_sync.dart';
import 'package:pure_live_app/features/iptv/xtream.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';

/// The "网络电视" source over the app database (spec/modules/iptv.md §5).
final iptvSiteProvider = Provider<IptvSite>((ref) {
  final store = ref.watch(storeProvider);
  return IptvSite(
    StoreIptvRepository(store.iptv),
    userAgent: () {
      final agent = store.settings.get(Settings.iptvUserAgent).trim();
      return agent.isEmpty ? null : agent;
    },
  );
});

/// `<data root>/IPTV`, where imported playlist and guide files are kept.
final iptvDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}IPTV'),
);

/// Imports and syncs; after every change the IPTV discover lists reload.
final iptvSyncProvider = Provider<IptvSync>((ref) {
  final store = ref.watch(storeProvider);
  return IptvSync(
    store: store.iptv,
    fetcher: IptvFetcher(ref.watch(liveHttpProvider)),
    settings: store.settings,
    directory: ref.watch(iptvDirectoryProvider),
    xtream: XtreamVault(ref.watch(secretStoreProvider)),
    onChanged: () {
      ref
        ..invalidate(categoriesProvider(IptvSite.platformId))
        ..invalidate(roomListProvider(const RecommendedQuery(IptvSite.platformId)));
    },
  );
});

/// Playlists with their counts, live.
final iptvPlaylistsProvider = StreamProvider<List<IptvPlaylistRecord>>(
  (ref) => ref.watch(storeProvider).iptv.watchPlaylists(),
);

/// Guide sources, live.
final iptvGuideSourcesProvider = StreamProvider<List<IptvGuideSourceRecord>>(
  (ref) => ref.watch(storeProvider).iptv.watchGuideSources(),
);

/// Automatic sync (F-IPTV-03): when the setting is on, due URL sources sync
/// 3 s after start and then every hour; turning it on runs a check at once.
final iptvAutoSyncProvider = Provider<void>((ref) {
  final settings = ref.watch(storeProvider).settings;
  Timer? start;
  Timer? hourly;
  var running = false;

  Future<void> run() async {
    if (running || !settings.get(Settings.iptvAutoSync)) return;
    running = true;
    try {
      await ref.read(iptvSyncProvider).syncDue();
    } on Object {
      // Failures are recorded per source and shown on the IPTV page.
    } finally {
      running = false;
    }
  }

  void schedule({Duration delay = const Duration(seconds: 3)}) {
    start?.cancel();
    hourly?.cancel();
    if (!settings.get(Settings.iptvAutoSync)) return;
    start = Timer(delay, () => unawaited(run()));
    hourly = Timer.periodic(const Duration(hours: 1), (_) => unawaited(run()));
  }

  schedule();
  final changes = settings.changes
      .where((id) => id == Settings.iptvAutoSync.id || id == Settings.iptvAutoSyncHours.id)
      .listen((_) => schedule(delay: Duration.zero));
  ref.onDispose(() {
    start?.cancel();
    hourly?.cancel();
    unawaited(changes.cancel());
  });
});
