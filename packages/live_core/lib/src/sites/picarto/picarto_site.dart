import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/picarto/picarto_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'picarto';
const _api = 'ptvintern.picarto.tv';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Picarto adapter (spec/sites/picarto.md).
final class PicartoSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  /// §6.3 API and media request headers.
  static const Map<String, String> headers = {
    'user-agent': _userAgent,
    'referer': 'https://picarto.tv/',
    'origin': 'https://picarto.tv',
  };

  /// §2.2 explore page size.
  static const pageSize = 30;

  /// §3 search page size.
  static const searchSize = 20;

  @override
  String get id => _site;

  @override
  String get name => 'Picarto';

  Future<LiveResponse> _get(Uri url) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  @override
  Future<List<Category>> categories() async {
    final response = await _get(Uri.https(_api, '/api/languages-categories'));
    return PicartoParse.categories(response.text, status: response.status);
  }

  Future<Page<RoomCard>> _explore({String? category, PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get(
      Uri.https(_api, '/api/explore', {
        'first': '$pageSize',
        'page': '$page',
        'filter_params[adult]': 'false',
        'order_by[field]': 'viewers',
        'order_by[order]': 'DESC',
        'type': 'stream',
        if (category != null) 'filter_params[languages]': '',
        if (category != null) 'filter_params[categories]': '$category: true',
      }),
    );
    return PicartoParse.explorePage(response.text, page: page, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(area.id)) throw ArgumentError.value(area.id, 'area', 'not a category id');
    return _explore(category: area.id, cursor: cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _explore(cursor: cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get(
      Uri.https(_api, '/api/search', {
        'first': '$searchSize',
        'page': '$page',
        'q': text.length > 100 ? text.substring(0, 100) : text,
        'type': 'searchProfiles',
        'tag_search': 'false',
      }),
    );
    return PicartoParse.searchPage(response.text, page: page, size: searchSize, status: response.status);
  }

  Future<({RoomDetail detail, Uri? master})> _detail(RoomRef ref) async {
    if (!PicartoParse.namePattern.hasMatch(ref.roomId)) throw NotFound(_site, 'not a channel: ${ref.roomId}');
    final response = await _get(Uri.https(_api, '/api/channel/detail/${ref.roomId}'));
    return PicartoParse.detail(response.text, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _detail(ref)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    // §6.1 fresh: the load balancer picks the edge per request.
    final fresh = await _detail(room.ref);
    final master = fresh.master;
    if (master == null) throw const StreamUnavailable(_site, 'channel is offline');
    final response = await _get(master);
    if (response.status == 404) throw const StreamUnavailable(_site, 'master 404');
    if (!response.isSuccess) throw NetworkFailure(_site, 'master HTTP ${response.status}');
    return PicartoParse.streams(response.text, master: master, headers: headers, wanted: quality?.id);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final name = PicartoParse.channelOf(input);
    return name == null ? null : RoomRef(_site, name);
  }
}
