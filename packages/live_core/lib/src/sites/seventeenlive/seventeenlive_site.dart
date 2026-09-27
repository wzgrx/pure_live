import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/seventeenlive/seventeenlive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = '17live';
const _api = 'api-dsa.17app.co';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The 17LIVE adapter (spec/sites/17live.md).
final class SeventeenliveSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  /// §6.3 API headers.
  static const Map<String, String> headers = {
    'user-agent': _userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://17.live',
    'referer': 'https://17.live/',
  };

  /// §6.3 media headers: the pull hosts refuse requests without a Referer.
  static const Map<String, String> mediaHeaders = {'user-agent': _userAgent, 'referer': 'https://17.live/'};

  @override
  String get id => _site;

  @override
  String get name => '17LIVE';

  Future<LiveResponse> _get(String path, Map<String, String>? query) async {
    try {
      return await http.send(LiveRequest(site: _site, url: Uri.https(_api, path, query), headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<Page<RoomCard>> _sections(String region, PageCursor? cursor) async {
    final response = await _get('/api/v1/sections', {
      'count': '20',
      'typeTab': '2',
      'region': region,
      'cursor': cursor?.value ?? '',
    });
    return SeventeenliveParse.sectionsPage(response.text, cursor: cursor?.value, status: response.status);
  }

  @override
  Future<List<Category>> categories() async => const [SeventeenliveParse.category];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    if (!SeventeenliveParse.areas.any((a) => a.id == area.id)) throw NotFound(_site, 'area ${area.id}');
    return _sections(area.id, cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _sections('JP', cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    var text = keyword.trim();
    if (text.isEmpty || cursor != null) return const Page.empty();
    // §3 a room link or number finds that room, live or not.
    final roomId = SeventeenliveParse.roomIdPattern.hasMatch(text) ? text : SeventeenliveParse.roomIdOf(text);
    if (roomId != null) {
      try {
        return Page([(await detail(RoomRef(_site, roomId))).card]);
      } on NotFound {
        if (RegExp('^https?://').hasMatch(text)) return const Page.empty();
      }
    }
    if (RegExp('^https?://').hasMatch(text)) return const Page.empty();
    if (text.length > 100) text = text.substring(0, 100);
    final response = await _get('/api/v1/liveStreams/search', {'query': text});
    return SeventeenliveParse.searchPage(response.text, status: response.status);
  }

  String _checkedId(RoomRef ref) {
    final id = ref.roomId;
    if (!SeventeenliveParse.roomIdPattern.hasMatch(id)) throw NotFound(_site, 'not a room id: $id');
    return id;
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final id = _checkedId(ref);
    final response = await _get('/api/v1/lives/$id', null);
    return SeventeenliveParse.detail(response.text, roomId: id, status: response.status);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final id = _checkedId(room.ref);
    // §6.1 fresh: the answer names the provider that serves right now.
    final response = await _get('/api/v1/lives/$id', null);
    return SeventeenliveParse.streams(
      response.text,
      roomId: id,
      headers: mediaHeaders,
      wanted: quality?.id,
      status: response.status,
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final id = SeventeenliveParse.roomIdOf(input);
    return id == null ? null : RoomRef(_site, id);
  }
}
