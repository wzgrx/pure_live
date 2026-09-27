import 'dart:async';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/tiktok/tiktok_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'tiktok';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The TikTok LIVE adapter (spec/sites/tiktok.md): link-only. A room is a
/// username; its current broadcast and streams come from the anonymous
/// `api-live/user/room` answer. TikTok has no anonymous directory or
/// search (§2), so there is no catalog.
final class TikTokSite implements LiveSite, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'TikTok';

  Future<LiveResponse> _send(Uri url, {required String referer, bool followRedirects = true}) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: {
            'accept': 'application/json, text/plain, */*',
            'accept-language': 'en-US,en;q=0.9',
            'origin': 'https://www.tiktok.com',
            'referer': referer,
            'user-agent': _userAgent,
          },
          followRedirects: followRedirects,
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
    if (followRedirects && status != 200) throw ApiChanged(_site, 'HTTP $status ${url.path}');
    return response;
  }

  Future<TikTokRoom> _room(String user) async {
    if (!TikTokParse.username.hasMatch(user)) throw NotFound(_site, 'not a TikTok username: $user');
    final response = await _send(
      Uri.https('www.tiktok.com', '/api-live/user/room/', {
        'aid': '1988',
        'sourceType': '54',
        'staleTime': '600000',
        'uniqueId': user,
      }),
      referer: TikTokParse.link(user).toString(),
    );
    return TikTokParse.userRoom(response.text, roomId: user);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final user = room.ref.roomId;
    final current = await _room(user);
    if (current.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (current.restricted) throw const NeedsLogin(_site, 'subscriber-only or paid LIVE');
    final qualities = TikTokParse.qualities(current.pull, options: current.options);
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no stream_data');
    final selected = qualities.firstWhere((q) => q.id == quality?.id, orElse: () => qualities.first);
    final lines = TikTokParse.lines(
      current.pull,
      selected,
      headers: {'referer': TikTokParse.link(user).toString(), 'user-agent': _userAgent},
    );
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'no FLV or HLS URL');
    return StreamSet(qualities: qualities, selected: selected, lines: lines);
  }

  static const _hosts = {'tiktok.com', 'www.tiktok.com', 'm.tiktok.com'};
  static const _shortHosts = {'vm.tiktok.com', 'vt.tiktok.com'};

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (text.startsWith('@')) {
      final user = text.substring(1).toLowerCase();
      return TikTokParse.username.hasMatch(user) ? RoomRef(_site, user) : null;
    }
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    var url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    // §1 a short share link: one redirect, which must stay on TikTok.
    if (_shortHosts.contains(url.host.toLowerCase()) || (_isTikTok(url) && url.pathSegments.firstOrNull == 't')) {
      final response = await _send(url, referer: 'https://www.tiktok.com/', followRedirects: false);
      final location = response.header('location');
      if (response.status < 300 || response.status >= 400 || location == null) return null;
      url = url.resolve(location.trim());
    }
    if (!_isTikTok(url)) return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments case [final at] || [final at, 'live'] when at.startsWith('@')) {
      final user = at.substring(1).toLowerCase();
      return TikTokParse.username.hasMatch(user) ? RoomRef(_site, user) : null;
    }
    // §1 `share/live/<room id>`: the room's owner is the room.
    if (segments case ['share', 'live', final room] when TikTokParse.liveRoomId.hasMatch(room)) {
      final response = await _send(
        Uri.https('webcast.tiktok.com', '/webcast/room/info/', {'aid': '1988', 'room_id': room}),
        referer: 'https://www.tiktok.com/',
      );
      return RoomRef(_site, TikTokParse.roomOwner(response.text));
    }
    return null;
  }

  static bool _isTikTok(Uri url) => _hosts.contains(url.host.toLowerCase());
}
