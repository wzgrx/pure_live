import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/missevan/missevan_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'missevan';
const _origin = 'https://fm.missevan.com';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Missevan (猫耳 FM) adapter (spec/sites/missevan.md).
final class MissevanSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  /// §6.3 API and media request headers.
  static const Map<String, String> headers = {'user-agent': _userAgent, 'referer': '$_origin/', 'origin': _origin};

  @override
  String get id => _site;

  @override
  String get name => '猫耳 FM';

  Future<LiveResponse> _get(String path, [Map<String, String>? query]) async {
    try {
      return await http.send(
        LiveRequest(
          site: _site,
          url: Uri.https('fm.missevan.com', '/api/v2/$path', query == null || query.isEmpty ? null : query),
          headers: const {...headers, 'accept': 'application/json, text/plain, */*'},
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  @override
  Future<List<Category>> categories() async {
    final response = await _get('meta/data');
    return MissevanParse.categories(response.text, status: response.status);
  }

  Future<Page<RoomCard>> _list(Map<String, String> filter, PageCursor? cursor) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get('chatroom/open/list', {'p': '$page', ...filter});
    return MissevanParse.listPage(response.text, page: page, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    final parameter = MissevanParse.namespaceQuery[area.categoryId];
    if (parameter == null || !MissevanParse.roomIdPattern.hasMatch(area.id)) {
      throw ArgumentError.value(area.id, 'area', 'not a Missevan ${area.categoryId} area');
    }
    return _list({parameter: area.id}, cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _list(const {}, cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) return const Page.empty();
    // §3 a room id or link finds exactly that room, live or not.
    final id = MissevanParse.roomIdOf(text);
    if (id != null) {
      if (cursor != null) return const Page.empty();
      try {
        return Page([(await detail(RoomRef(_site, id))).card]);
      } on NotFound {
        return const Page.empty();
      }
    }
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get('chatroom/search', {
      's': text.length > 100 ? text.substring(0, 100) : text,
      'p': '$page',
      'page_size': '20',
    });
    return MissevanParse.searchPage(response.text, page: page, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    if (!MissevanParse.roomIdPattern.hasMatch(ref.roomId)) throw NotFound(_site, 'not a room id: ${ref.roomId}');
    final response = await _get('live/${ref.roomId}');
    final detail = MissevanParse.detail(response.text, status: response.status);
    if (detail.ref != ref) throw ApiChanged(_site, 'live/${ref.roomId} answered ${detail.ref.roomId}');
    return detail;
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    if (!MissevanParse.roomIdPattern.hasMatch(room.ref.roomId)) throw NotFound(_site, room.ref.roomId);
    // §6.1 always fresh: the pull URLs are signed and expire.
    final response = await _get('live/${room.ref.roomId}');
    return MissevanParse.streams(response.text, issuedAt: _now(), headers: headers, status: response.status);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final id = MissevanParse.roomIdOf(input);
    return id == null ? null : RoomRef(_site, id);
  }
}
