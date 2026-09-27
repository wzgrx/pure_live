import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/chzzk/chzzk_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'chzzk';
const _api = 'api.chzzk.naver.com';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The CHZZK adapter (spec/sites/chzzk.md).
final class ChzzkSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  /// §2.1 at most this many `categories/live` pages.
  static const categoryPages = 4;

  /// §6.3 API request headers.
  static const Map<String, String> apiHeaders = {
    'user-agent': _userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://chzzk.naver.com',
    'referer': 'https://chzzk.naver.com/',
  };

  /// §6.3 media request headers.
  static const Map<String, String> mediaHeaders = {'user-agent': _userAgent, 'referer': 'https://chzzk.naver.com/'};

  @override
  String get id => _site;

  @override
  String get name => 'CHZZK';

  Future<LiveResponse> _send(Uri url, {Map<String, String> headers = apiHeaders}) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(String path, [Map<String, String>? query]) =>
      _send(Uri.https(_api, path, query == null || query.isEmpty ? null : query));

  @override
  Future<List<Category>> categories() async {
    final pages = <ChzzkCategoryPage>[];
    Map<String, String>? next = const {};
    for (var index = 0; index < categoryPages && next != null; index++) {
      final response = await _get('/service/v1/categories/live', {'size': '50', ...next});
      final page = ChzzkParse.categoryPage(response.text, status: response.status);
      pages.add(page);
      next = page.next;
    }
    return ChzzkParse.categories(pages);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final query = cursor == null ? const <String, String>{} : ChzzkParse.cursorQuery(cursor);
    final path = '/service/v2/categories/${Uri.encodeComponent(area.categoryId)}/${Uri.encodeComponent(area.id)}/lives';
    final response = await _get(path, {'size': '30', ...query});
    return ChzzkParse.livesPage(response.text, status: response.status, cursor: query);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final query = cursor == null ? const <String, String>{} : ChzzkParse.cursorQuery(cursor);
    final response = await _get('/service/v1/lives', {'size': '30', ...query});
    return ChzzkParse.livesPage(response.text, status: response.status, cursor: query);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final offset = int.tryParse(cursor?.value ?? '') ?? 0;
    final response = await _get('/service/v1/search/channels', {
      'keyword': text.length > 100 ? text.substring(0, 100) : text,
      'offset': '$offset',
      'size': '20',
    });
    return ChzzkParse.searchPage(response.text, offset: offset, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final id = _checkedId(ref);
    final channel = await _get('/service/v1/channels/$id');
    // The channel answers 200 for an unknown id; check before the second call.
    ChzzkParse.channel(channel.text, status: channel.status);
    final live = await _get('/service/v3.1/channels/$id/live-detail');
    return ChzzkParse.detail(channel.text, live.text, channelStatus: channel.status, liveStatus: live.status);
  }

  String _checkedId(RoomRef ref) {
    final id = ref.roomId.toLowerCase();
    if (!ChzzkParse.channelIdPattern.hasMatch(id)) throw NotFound(_site, 'not a channel id: ${ref.roomId}');
    return id;
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final id = _checkedId(room.ref);
    // §6.1 always a fresh live-detail: the master URLs carry the tokens.
    final live = await _get('/service/v3.1/channels/$id/live-detail');
    final playback = ChzzkParse.playback(live.text, status: live.status);
    if (playback.media.isEmpty) throw ChzzkParse.noPlayback(playback);
    final issuedAt = _now();
    final masters = <({String id, Uri url, String? body})>[];
    SiteError? failure;
    for (final media in playback.media) {
      final response = await _send(media.url, headers: mediaHeaders);
      if (response.isSuccess) {
        masters.add((id: media.id, url: media.url, body: response.text));
      } else {
        masters.add((id: media.id, url: media.url, body: null));
        failure = response.status == 403 || response.status == 401
            ? RiskControl(_site, detail: '${media.id} master HTTP ${response.status}')
            : StreamUnavailable(_site, '${media.id} master HTTP ${response.status}');
      }
    }
    if (masters.every((master) => master.body == null)) throw failure!;
    return ChzzkParse.streams(masters, issuedAt: issuedAt, headers: mediaHeaders, wanted: quality?.id);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (ChzzkParse.channelIdPattern.hasMatch(text.toLowerCase())) return RoomRef(_site, text.toLowerCase());
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || url.host.toLowerCase() != 'chzzk.naver.com') return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final candidate = switch (segments) {
      ['live', final id] => id,
      [final id] => id,
      _ => null,
    };
    final id = candidate?.toLowerCase();
    return id != null && ChzzkParse.channelIdPattern.hasMatch(id) ? RoomRef(_site, id) : null;
  }
}
