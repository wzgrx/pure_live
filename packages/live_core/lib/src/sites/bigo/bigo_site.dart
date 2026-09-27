import 'dart:async';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/bigo/bigo_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'bigo';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Bigo Live adapter (spec/sites/bigo.md): the public recommendation,
/// details and HLS through the anonymous web token. Needs the platform's
/// proxy route from mainland China (the studio answer asks for a login
/// there, §9).
final class BigoSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [random] seeds the token request (tests).
  new(this.http, {Random? random}) : _random = random ?? Random.secure();

  /// Transport.
  final LiveHttp http;
  final Random _random;

  @override
  String get id => _site;

  @override
  String get name => 'Bigo Live';

  static const Map<String, String> _headers = {
    'origin': 'https://www.bigo.tv',
    'referer': 'https://www.bigo.tv/',
    'accept': 'application/json, text/plain, */*',
    'user-agent': _userAgent,
  };

  Future<String> _send(Uri url, {String method = 'GET', Map<String, String> extra = const {}}) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          method: method,
          url: url,
          headers: {..._headers, ...extra},
          body: method == 'POST' ? const <int>[] : null,
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
      throw NotFound(_site, 'no area ${area.id}: Bigo has one public list');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    return BigoParse.list(
      await _send(
        Uri.https('ta.bigo.tv', '/official_website/OInterfaceWeb/vedioList/72', {
          'tabType': '00',
          'fetchNum': '10',
          'lang': 'en',
          'countryCode': 'US',
        }),
      ),
    );
  }

  /// §6.1 the anonymous web token: server time → encrypted request → token.
  Future<String> _token() async {
    final time = BigoParse.serverTime(
      await _send(Uri.https('sec.bigo.sg', '/v1/webjs/t', {'callback': 'jsonp_purelive_t'})),
    );
    return BigoParse.token(
      await _send(
        Uri.https('sec.bigo.sg', '/v1/webjs/status', {
          'callback': 'jsonp_purelive_s',
          'data': BigoParse.tokenData(time, random: _random),
        }),
      ),
    );
  }

  Future<BigoStudio> _studio(String roomId) async {
    if (!BigoParse.siteId.hasMatch(roomId)) throw NotFound(_site, 'not a Bigo id: $roomId');
    final token = await _token();
    return BigoParse.studio(
      await _send(
        Uri.https('ta.bigo.tv', '/official_website/studio/getInternalStudioInfo', {
          'siteId': roomId,
          'verify': '',
          'token': token,
        }),
        method: 'POST',
        extra: const {'content-type': 'application/x-www-form-urlencoded'},
      ),
      roomId: roomId,
    );
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _studio(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final studio = await _studio(room.ref.roomId);
    final hls = studio.hls;
    if (hls == null) throw const StreamUnavailable(_site, 'not live, locked, or no hls_src');
    final line = BigoParse.line(
      hls,
      headers: const {'origin': 'https://www.bigo.tv', 'referer': 'https://www.bigo.tv/', 'user-agent': _userAgent},
    );
    return StreamSet(qualities: const [BigoParse.auto], selected: BigoParse.auto, lines: [line]);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (RegExp(r'^\d{1,20}$').hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'bigo.tv' && !host.endsWith('.bigo.tv')) return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    // `/<id>`, `/<lang>/<id>` (two-letter language prefix).
    final id = switch (segments) {
      [final id] => id,
      [final lang, final id] when RegExp(r'^[a-z]{2}(?:-[A-Za-z]{2})?$').hasMatch(lang) => id,
      _ => null,
    };
    if (id == null || BigoParse.reserved.contains(id.toLowerCase()) || !BigoParse.siteId.hasMatch(id)) return null;
    return RoomRef(_site, id);
  }
}
