import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/showroom/showroom_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'showroom';
const _host = 'www.showroom-live.com';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The SHOWROOM adapter (spec/sites/showroom.md).
final class ShowroomSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  /// §6.3 API headers.
  static const Map<String, String> headers = {
    'user-agent': _userAgent,
    'accept': 'application/json, text/plain, */*',
    'referer': 'https://www.showroom-live.com/',
  };

  /// §6.3 media headers.
  static const Map<String, String> mediaHeaders = {
    'user-agent': _userAgent,
    'referer': 'https://www.showroom-live.com/',
  };

  @override
  String get id => _site;

  @override
  String get name => 'SHOWROOM';

  Future<LiveResponse> _get(String path, [Map<String, String>? query]) async {
    try {
      return await http.send(LiveRequest(site: _site, url: Uri.https(_host, path, query), headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _onlives() => _get('/api/live/onlives');

  @override
  Future<List<Category>> categories() async {
    final response = await _onlives();
    return ShowroomParse.categories(response.text, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final response = await _onlives();
    return ShowroomParse.genrePage(response.text, genreId: area.id, status: response.status);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final response = await _onlives();
    return ShowroomParse.genrePage(response.text, genreId: '0', status: response.status);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    if (cursor != null || keyword.trim().isEmpty) return const Page.empty();
    // §3 a room link finds that room, live or not.
    if (RegExp('^https?://').hasMatch(keyword.trim())) {
      final ref = await resolve(keyword);
      if (ref == null) return const Page.empty();
      try {
        return Page([(await detail(ref)).card]);
      } on NotFound {
        return const Page.empty();
      }
    }
    final response = await _onlives();
    return ShowroomParse.searchPage(response.text, keyword: keyword, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    if (!ShowroomParse.roomIdPattern.hasMatch(ref.roomId)) throw NotFound(_site, 'not a room id: ${ref.roomId}');
    final profile = await _get('/api/room/profile', {'room_id': ref.roomId});
    final info = await _get('/api/live/live_info', {'room_id': ref.roomId});
    return ShowroomParse.detail(profile.text, info.text, profileStatus: profile.status, infoStatus: info.status);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    if (!ShowroomParse.roomIdPattern.hasMatch(room.ref.roomId)) throw NotFound(_site, room.ref.roomId);
    final response = await _get('/api/live/streaming_url', {'room_id': room.ref.roomId, 'abr_available': '1'});
    return ShowroomParse.streams(response.text, headers: mediaHeaders, wanted: quality?.id, status: response.status);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final reference = ShowroomParse.referenceOf(input);
    if (reference == null) return null;
    if (reference.roomId != null) return RoomRef(_site, reference.roomId!);
    final response = await _get('/api/room/status', {'room_url_key': reference.urlKey!});
    return RoomRef(_site, ShowroomParse.roomIdOfStatus(response.text, status: response.status));
  }
}
