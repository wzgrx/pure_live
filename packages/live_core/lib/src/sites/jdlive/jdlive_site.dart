import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/jdlive/jdlive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'jdlive';
const _userAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';

/// The JD Live adapter (spec/sites/jdlive.md): the featured shopping lives
/// and the play endpoint, which gives state, cover and addresses but no
/// title or streamer name.
final class JdLiveSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '京东直播';

  static const Map<String, String> _headers = {
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://lives.jd.com',
    'referer': 'https://lives.jd.com/',
    'user-agent': _userAgent,
  };

  Future<String> _api(String function, Map<String, Object?> body, {String time = 't'}) async {
    final url = Uri.https('api.m.jd.com', '/api', {
      'appid': 'h5-live',
      'functionId': function,
      time: '${_now().millisecondsSinceEpoch}',
      'body': jsonEncode(body),
    });
    final LiveResponse response;
    try {
      response = await http.send(LiveRequest(site: _site, url: url, headers: _headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status $function');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 $function');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status $function');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status $function');
    return response.text;
  }

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async =>
      throw NotFound(_site, 'no area ${area.id}: JD Live has one featured list');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final after = JdLiveParse.cursor(cursor);
    final page = after?.page ?? 1;
    final timestamp = after?.timestamp ?? _now().millisecondsSinceEpoch;
    final body = await _api('liveListWithTabToM', {
      'tabId': 1,
      'currentCount': '${after?.count ?? 0}',
      'page': page,
      'timestamp': timestamp,
    }, time: 'v');
    return JdLiveParse.list(body, page: page, timestamp: timestamp);
  }

  Future<JdLivePlay> _play(String liveId) async {
    if (!JdLiveParse.liveId.hasMatch(liveId)) throw NotFound(_site, 'not a live id: $liveId');
    return JdLiveParse.play(await _api('getImmediatePlayToM', {'liveId': liveId}), expectedId: liveId);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _play(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final lines = JdLiveParse.lines(
      await _play(room.ref.roomId),
      headers: const {'origin': 'https://lives.jd.com', 'referer': 'https://lives.jd.com/', 'user-agent': _userAgent},
    );
    return StreamSet(qualities: const [JdLiveParse.fhd], selected: JdLiveParse.fhd, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (JdLiveParse.liveId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null || url.host.toLowerCase() != 'lives.jd.com') return null;
    // The page routes by fragment: `#/<id>`, `#/<id>/live`, `#/<id>?origin=0`.
    final route = RegExp(r'^/?([1-9]\d{4,17})(?:/(?:live|notice|closed|replay))?(?:\?.*)?$').firstMatch(url.fragment);
    return route == null ? null : RoomRef(_site, route.group(1)!);
  }
}
