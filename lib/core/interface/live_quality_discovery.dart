import 'package:dio/dio.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'live_site.dart';

/// Optional discovery ownership. Implementations forward cancellation to their
/// transport and settle only after temporary sessions/credentials are released.
/// Cancelling a caller must never close a shared client or another discovery.
abstract interface class LiveQualityDiscovery {
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel});
}

extension LiveSiteQualityDiscovery on LiveSite {
  Future<List<LivePlayQuality>> discoverPlayQualities({required LiveRoom detail, CancelToken? cancel}) async {
    if (cancel?.isCancelled == true) throw cancel!.cancelError!;
    final site = this;
    final result = site is LiveQualityDiscovery
        ? await (site as LiveQualityDiscovery).discoverPlayQualitiesRaw(detail: detail, cancel: cancel)
        : await getPlayQualites(detail: detail);
    // A legacy adapter still has its own transport lifetime, but its cancelled
    // result must not become the next stage of a new playback operation.
    if (cancel?.isCancelled == true) throw cancel!.cancelError!;
    return result;
  }
}
