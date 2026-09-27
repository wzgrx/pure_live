import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/steambroadcast/steambroadcast_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'steambroadcast';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Steam broadcast adapter (spec/sites/steambroadcast.md): the trending
/// broadcasts page, details from the broadcast info and the mini profile,
/// and the HLS master playlist.
final class SteamBroadcastSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'Steam 直播';

  static Map<String, String> _headers({String? steamId, bool json = true}) => {
    'accept': json ? 'application/json, text/javascript, */*; q=0.8' : 'text/html, */*; q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'referer': steamId == null
        ? 'https://steamcommunity.com/?subsection=broadcasts'
        : SteamBroadcastParse.link(steamId).toString(),
    'user-agent': _userAgent,
    'x-requested-with': 'XMLHttpRequest',
  };

  Future<String> _get(Uri url, {String? steamId, bool json = true}) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: _headers(steamId: steamId, json: json),
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status ${url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${url.path}');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status ${url.path}');
    return response.text;
  }

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async =>
      throw NotFound(_site, 'no area ${area.id}: Steam broadcasts have no categories');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('steamcommunity.com', '/apps/allcontenthome', {
      'l': 'english',
      'browsefilter': 'trend',
      'appHubSubSection': '13',
      'forceanon': '1',
      'p': '$page',
      'broadcastsoffset': '${(page - 1) * 10}',
      'numperpage': '10',
    });
    return SteamBroadcastParse.directory(await _get(url, json: false), page: page);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final steamId = ref.roomId;
    if (!SteamBroadcastParse.steamId.hasMatch(steamId)) throw NotFound(_site, 'not a Steam id: $steamId');
    final info = await _get(
      Uri.https('steamcommunity.com', '/broadcast/getbroadcastinfo/', {
        'steamid': steamId,
        'broadcastid': '0',
        'location': '5',
      }),
      steamId: steamId,
    );
    final profile = SteamBroadcastParse.profile(
      await _get(
        Uri.parse('https://steamcommunity.com/miniprofile/${SteamBroadcastParse.accountId(steamId)}/json'),
        steamId: steamId,
      ),
    );
    return SteamBroadcastParse.detail(info, steamId: steamId, name: profile.name, avatar: profile.avatar);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final steamId = room.ref.roomId;
    final body = await _get(
      Uri.https('steamcommunity.com', '/broadcast/getbroadcastmpd/', {
        'broadcastid': '0',
        'steamid': steamId,
        'viewertoken': '0',
        'sessionid': '',
      }),
      steamId: steamId,
    );
    final line = SteamBroadcastParse.line(
      SteamBroadcastParse.master(body),
      headers: {
        'origin': 'https://steamcommunity.com',
        'referer': SteamBroadcastParse.link(steamId).toString(),
        'user-agent': _userAgent,
      },
    );
    return StreamSet(qualities: const [SteamBroadcastParse.auto], selected: SteamBroadcastParse.auto, lines: [line]);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (SteamBroadcastParse.steamId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null || url.host.toLowerCase() != 'steamcommunity.com') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    return switch (segments) {
      ['broadcast', 'watch', final id] ||
      ['profiles', final id] when SteamBroadcastParse.steamId.hasMatch(id) => RoomRef(_site, id),
      _ => null,
    };
  }
}
