import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/inke/inke_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'inke';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Inke (映客) adapter (spec/sites/inke.md): the website's showcases
/// and room API, and the app's public live API for the current stream.
final class InkeSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  /// §6.3 API and media request headers.
  static const Map<String, String> headers = {
    'user-agent': _userAgent,
    'referer': 'https://www.inke.cn/',
    'origin': 'https://www.inke.cn',
  };

  @override
  String get id => _site;

  @override
  String get name => '映客';

  Future<LiveResponse> _get(Uri url) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _web(String path, [Map<String, String>? query]) =>
      _get(Uri.https('webapi.busi.inke.cn', '/web/$path', query));

  Future<LiveResponse> _service(String path, [Map<String, String>? query]) =>
      _get(Uri.https('service.inke.cn', '/api/live/$path', query));

  @override
  Future<List<Category>> categories() async {
    final response = await _web('Live_channel_pc');
    return InkeParse.categories(response.text, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final response = await _web('Live_channel_pc');
    return InkeParse.channelPage(response.text, tabKey: area.id, status: response.status);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final response = await _service('simpleall');
    return InkeParse.simpleallPage(response.text, status: response.status);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty || cursor != null) return const Page.empty();
    // §3 a uid or a room link finds that anchor exactly.
    final uid = InkeParse.uidOf(text);
    if (uid != null) return Page([(await detail(RoomRef(_site, uid))).card]);
    if (RegExp('^https?://').hasMatch(text)) return const Page.empty();
    // §3 no server search: the nicknames of every public showcase.
    final query = text.toLowerCase();
    final top = await _web('Live_top_pc');
    final channels = await _web('Live_channel_pc');
    final hot = await _service('simpleall');
    final cards = [
      ...InkeParse.topPage(top.text, status: top.status).items,
      for (final area in InkeParse.categories(channels.text, status: channels.status).single.areas)
        ...InkeParse.channelPage(channels.text, tabKey: area.id).items,
      ...InkeParse.simpleallPage(hot.text, status: hot.status).items,
    ];
    final seen = <String>{};
    return Page([
      for (final card in cards)
        if (card.anchorName.toLowerCase().contains(query) && seen.add(card.ref.roomId)) card,
    ]);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    if (!InkeParse.uidPattern.hasMatch(ref.roomId)) throw NotFound(_site, 'not a uid: ${ref.roomId}');
    final share = await _web('live_share_pc', {'uid': ref.roomId});
    final publish = await _service('now_publish', {'id': ref.roomId});
    return InkeParse.detail(
      uid: ref.roomId,
      shareBody: share.text,
      publishBody: publish.text,
      shareStatus: share.status,
      publishStatus: publish.status,
    );
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    // §6.1 fresh: the signed URL expires.
    final publish = await _service('now_publish', {'id': room.ref.roomId});
    return InkeParse.streams(
      publish.text,
      uid: room.ref.roomId,
      issuedAt: _now(),
      headers: headers,
      status: publish.status,
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final uid = InkeParse.uidOf(input);
    return uid == null ? null : RoomRef(_site, uid);
  }
}
