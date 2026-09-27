import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/twitcasting/twitcasting_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'twitcasting';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The TwitCasting adapter (spec/sites/twitcasting.md).
final class TwitcastingSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  /// §6.3 request headers (English pages, so labels are readable).
  static const Map<String, String> headers = {
    'user-agent': _userAgent,
    'referer': 'https://twitcasting.tv/',
    'accept-language': 'en',
  };

  @override
  String get id => _site;

  @override
  String get name => 'TwitCasting';

  Future<LiveResponse> _get(Uri url, {bool follow = true}) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: headers, followRedirects: follow));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  @override
  Future<List<Category>> categories() async {
    final response = await _get(Uri.https('twitcasting.tv', '/'));
    return TwitcastingParse.categories(response.text, status: response.status);
  }

  Future<Page<RoomCard>> _top(String genre, PageCursor? cursor) async {
    if (cursor != null) return const Page.empty();
    final response = await _get(Uri.https('frontendapi.twitcasting.tv', '/top/category', {'id': genre, 'count': '60'}));
    return TwitcastingParse.topPage(response.text, now: _now(), status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    if (!RegExp(r'^[A-Za-z0-9_]{1,80}$').hasMatch(area.id)) throw ArgumentError.value(area.id, 'area', 'not a genre');
    return _top(area.id, cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _top('', cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty || cursor != null) return const Page.empty();
    // §3 a channel link finds that channel, live or not.
    if (RegExp('^https?://').hasMatch(text)) {
      final id = TwitcastingParse.channelOf(text);
      if (id == null) return const Page.empty();
      try {
        return Page([(await detail(RoomRef(_site, id))).card]);
      } on NotFound {
        return const Page.empty();
      }
    }
    final response = await _get(
      Uri(
        scheme: 'https',
        host: 'search.twitcasting.tv',
        pathSegments: ['search', 'text', if (text.length > 100) text.substring(0, 100) else text],
        queryParameters: {'hl': 'en'},
      ),
    );
    return TwitcastingParse.searchPage(response.text, status: response.status);
  }

  Future<LiveResponse> _stream(String id) =>
      _get(Uri.https('twitcasting.tv', '/streamserver.php', {'target': id, 'mode': 'client', 'player': 'pc_web'}));

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final id = TwitcastingParse.channel(ref.roomId);
    if (id == null) throw NotFound(_site, 'not a channel: ${ref.roomId}');
    final page = await _get(Uri.https('twitcasting.tv', '/$id'), follow: false);
    if (page.status >= 300 && page.status < 400) throw NotFound(_site, 'channel $id redirects');
    final stream = await _stream(id);
    return TwitcastingParse.detail(page.text, stream.text, id: id, pageStatus: page.status);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final id = TwitcastingParse.channel(room.ref.roomId);
    if (id == null) throw NotFound(_site, 'not a channel: ${room.ref.roomId}');
    final response = await _stream(id);
    return TwitcastingParse.streams(response.text, headers: headers, wanted: quality?.id, status: response.status);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final id = TwitcastingParse.channelOf(input);
    return id == null ? null : RoomRef(_site, id);
  }
}
