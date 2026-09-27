import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// Downloads playlists and programme guides (spec/modules/iptv.md §6).
///
/// Requests go out as platform `iptv` (proxy route and throttle key) with the
/// user's custom User-Agent when one is set. A 404 or 410 is [NotFound];
/// other failures are [NetworkFailure]; cancellation stays a
/// [TransportFailure].
final class IptvFetcher {
  /// Creates a fetcher on [_http].
  const new(this._http, {this.timeout = const Duration(minutes: 2)});

  final LiveHttp _http;

  /// Limit for one download, body included (guides reach tens of megabytes).
  final Duration timeout;

  /// The bytes at [url].
  Future<List<int>> download(Uri url, {String? userAgent, CancelToken? cancel}) async {
    final agent = userAgent?.trim();
    final LiveResponse response;
    try {
      response = await _http.send(
        LiveRequest(
          site: 'iptv',
          url: url,
          headers: {if (agent != null && agent.isNotEmpty) 'user-agent': agent, 'accept': '*/*'},
          timeout: timeout,
          cancel: cancel,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure('iptv', failure.toString());
    }
    if (response.status == 404 || response.status == 410) throw NotFound('iptv', 'HTTP ${response.status}');
    if (!response.isSuccess) throw NetworkFailure('iptv', 'HTTP ${response.status}');
    return response.bytes;
  }
}
