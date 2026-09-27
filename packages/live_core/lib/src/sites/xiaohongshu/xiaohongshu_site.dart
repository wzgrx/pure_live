import 'dart:async';

import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/xiaohongshu/xiaohongshu_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'xiaohongshu';
const _userAgent = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/87.0.4280.141 Mobile Safari/537.36';

/// The Xiaohongshu adapter, link-only (spec/sites/xiaohongshu.md): share
/// links, short links and app deep links resolve to a room; the public share
/// page gives details and the pull addresses. No catalog, search or chat.
final class XiaohongshuSite implements LiveSite, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => '小红书';

  static const Map<String, String> _headers = {
    'accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
    'referer': 'https://www.xiaohongshu.com/',
    'user-agent': _userAgent,
  };

  Future<LiveResponse> _get(Uri url, {bool followRedirects = true}) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(site: _site, url: url, headers: _headers, followRedirects: followRedirects),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status ${url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${url.path}');
    return response;
  }

  Future<XiaohongshuRoom> _room(String roomId) async {
    if (!XiaohongshuParse.roomId.hasMatch(roomId)) throw NotFound(_site, 'not a room id: $roomId');
    // The share page must be the page asked for: a redirect could land on
    // another room or a landing page.
    final response = await _get(XiaohongshuParse.link(roomId), followRedirects: false);
    if (response.status != 200) throw ApiChanged(_site, 'share page HTTP ${response.status}');
    return XiaohongshuParse.room(response.text, expectedId: roomId);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final fresh = await _room(room.ref.roomId);
    final config = fresh.pullConfig;
    final qualities = config == null ? const <Quality>[] : XiaohongshuParse.qualities(config);
    if (qualities.isEmpty) {
      // Offline or limited rooms report why first.
      XiaohongshuParse.lines(
        fresh,
        const Quality(id: '', label: '', rank: 0),
        headers: const {},
      );
      throw const StreamUnavailable(_site, 'no quality');
    }
    final requested = qualities.where((q) => q.id == quality?.id).firstOrNull ?? qualities.first;
    final lines = XiaohongshuParse.lines(
      fresh,
      requested,
      headers: const {'referer': 'https://www.xiaohongshu.com/', 'user-agent': _userAgent},
    );
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (XiaohongshuParse.roomId.hasMatch(text)) return RoomRef(_site, text);
    // Share text may hold several links; the first one that names a room wins.
    final candidates = RegExp(
      r'(?:https?|xhsdiscover)://[^\s，。！？、“”"<>]+',
      caseSensitive: false,
    ).allMatches(text).map((match) => Uri.tryParse(match.group(0)!)).nonNulls.toList();
    Uri? short;
    for (final url in candidates) {
      final room = XiaohongshuParse.roomFromUrl(url);
      if (room != null) return RoomRef(_site, room);
      if (short == null && XiaohongshuParse.isShortLink(url)) short = url;
    }
    if (short == null) return null;
    // §1 follow the short link one hop at a time, only across xhslink.com.
    var current = short;
    for (var hop = 0; hop < 5; hop++) {
      final response = await _get(current, followRedirects: false);
      final location = response.header('location');
      if (response.status < 300 || response.status >= 400 || location == null) break;
      final target = current.resolve(location.trim());
      final room = XiaohongshuParse.roomFromUrl(target);
      if (room != null) return RoomRef(_site, room);
      if (!XiaohongshuParse.isShortLink(target)) {
        throw UnsupportedLink(_site, 'short link leads to ${target.host}${target.path}, not a live room');
      }
      current = target;
    }
    throw UnsupportedLink(_site, 'short link ${short.path} did not lead to a live room');
  }
}
