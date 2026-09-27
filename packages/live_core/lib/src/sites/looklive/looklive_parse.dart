import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/crypto/aes.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'looklive';

/// A room reduced to what the adapter needs (spec/sites/looklive.md §4).
typedef LookLiveRoom = ({RoomDetail detail, bool audio, int? streamType, Map<String, dynamic>? urls});

/// Pure parsing of LOOK Live responses and the `weapi` request envelope
/// (spec/sites/looklive.md).
abstract final class LookLiveParse {
  /// §1 room number.
  static final RegExp roomNo = RegExp(r'^[1-9]\d{1,17}$');

  /// §2.1 the one top-level category.
  static const categoryId = 'look';

  /// §2.1 the two lists.
  static const areas = [
    Area(id: 'video', name: '视频直播', categoryId: categoryId),
    Area(id: 'audio', name: '声音直播', categoryId: categoryId),
  ];

  /// §2.2 rows per request.
  static const pageSize = 20;

  /// §5 the only quality.
  static const source = Quality(id: 'source', label: '原画', rank: 1);

  static const _nonce = '0CoJUm6Qyw8W8jud';
  static const _secretKey = '0123456789abcdef';
  static const _iv = '0102030405060708';
  static final BigInt _modulus = BigInt.parse(
    '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec'
    '4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813'
    'cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
    radix: 16,
  );

  /// The room page.
  static Uri link(String no) => Uri.parse('https://look.163.com/live?id=$no');

  static String _aes(String text, String key) =>
      base64Encode(AesCbc.encrypt(utf8.encode(text), key: utf8.encode(key), iv: utf8.encode(_iv)));

  /// §6.1 the `weapi` form: AES-CBC twice (web nonce, then the secret key)
  /// and the RSA-encrypted reversed secret key. With the fixed secret key
  /// the web client uses, `encSecKey` is a constant.
  static Map<String, String> envelope(Map<String, Object?> payload) {
    final params = _aes(_aes(jsonEncode(payload), _nonce), _secretKey);
    final reversed = utf8.encode(_secretKey).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final encSecKey = BigInt.parse(reversed, radix: 16).modPow(BigInt.from(0x10001), _modulus).toRadixString(16);
    return {'params': params, 'encSecKey': encSecKey.padLeft(256, '0')};
  }

  static Map<String, dynamic>? _data(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final code = jsonInt(decoded['code']);
    final message = jsonString(decoded['message']) ?? jsonString(decoded['msg']) ?? '';
    return switch (code) {
      200 => decoded['data'] is Map<String, dynamic> ? decoded['data'] as Map<String, dynamic> : null,
      404 => throw NotFound(_site, '$what: $message'),
      424 || 520 || 522 || 555 => throw RiskControl(_site, detail: '$what: $code $message'),
      _ => throw ApiChanged(_site, '$what: code $code $message'),
    };
  }

  static Uri? _picture(Object? value) {
    final url = jsonUrl(value);
    // NetEase serves the same images over https.
    return url != null && url.scheme == 'http' ? url.replace(scheme: 'https') : url;
  }

  /// §2.2 a recommendation page; only cards of [area]'s kind are kept (the
  /// voice list sometimes injects a video card).
  static Page<RoomCard> list(String body, {required String area, required int page}) {
    final data = _data(body, 'recommend');
    final rows = data?['itemList'];
    if (rows is! List) throw const ApiChanged(_site, 'recommend: itemList is not a list');
    final kind = area == 'audio' ? 2 : 1;
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map || '${row['type']}' != '1') continue;
      final live = row['liveData'];
      if (live is! Map || jsonInt(live['liveType']) != kind) continue;
      final user = live['userInfo'] is Map ? live['userInfo'] as Map : const <Object?, Object?>{};
      final id = jsonString(user['liveRoomNo']);
      if (id == null || !roomNo.hasMatch(id) || !seen.add(id)) continue;
      final name = decodeHtmlEntities(jsonString(user['nickname']) ?? '');
      final online = jsonInt(live['onlineNumber']);
      final heat = jsonInt(live['popularity']);
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(live['liveTitle']) ?? name),
          anchorName: name,
          state: LiveState.live,
          cover: _picture(live['liveCoverUrl']),
          area: areas.firstWhere((a) => a.id == area).name,
          audience: Audience(
            online: online != null && online >= 0 ? online : null,
            popularity: heat != null && heat >= 0 ? heat : null,
          ),
          avatar: _picture(user['avatarUrl']),
        ),
      );
    }
    final more = data?['hasMore'] == true && rows.isNotEmpty;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 `room/get/v3`.
  static LookLiveRoom room(String body, {required String expectedNo}) {
    final data = _data(body, 'room/get/v3');
    if (data == null) throw NotFound(_site, 'room $expectedNo');
    final anchor = data['anchor'] is Map ? data['anchor'] as Map : const <Object?, Object?>{};
    final id = jsonString(anchor['liveRoomNo']);
    if (id != expectedNo) throw ApiChanged(_site, 'room/get/v3: asked $expectedNo, got $id');
    final info = data['roomInfo'] is Map<String, dynamic> ? data['roomInfo'] as Map<String, dynamic> : null;
    final status = jsonInt(data['liveStatus']);
    final state = switch (status) {
      1 => LiveState.live,
      0 || -1 || -10 => LiveState.offline,
      _ => throw ApiChanged(_site, 'room/get/v3: liveStatus $status'),
    };
    final name = decodeHtmlEntities(jsonString(anchor['nickName']) ?? '');
    final liveType = jsonInt(info?['liveType']);
    final urls = info?['liveUrl'];
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, expectedNo),
          title: decodeHtmlEntities(jsonString(info?['title']) ?? name),
          anchorName: name,
          state: state,
          cover: _picture(info?['liveCoverUrl']),
          area: liveType == 2 ? '声音直播' : '视频直播',
          liveSince: switch (jsonInt(info?['startTime'])) {
            final int ms when ms > 0 && state == LiveState.live => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
            _ => null,
          },
        ),
        link: link(expectedNo),
        avatar: _picture(anchor['avatarUrl']),
      ),
      audio: liveType == 2,
      streamType: jsonInt(info?['liveStreamType']),
      urls: urls is Map<String, dynamic> ? urls : null,
    );
  }

  /// §5/§6 FLV then HLS from `liveUrl`.
  static List<StreamLine> lines(LookLiveRoom room, {required Map<String, String> headers}) {
    if (room.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    final urls = room.urls;
    final lines = <StreamLine>[
      for (final (key, format) in const [('httpPullUrl', StreamFormat.flv), ('hlsPullUrl', StreamFormat.hls)])
        if (jsonUrl(urls?[key]) case final url?)
          StreamLine(
            url: url,
            format: format,
            lineId: format.name,
            requested: source,
            headers: headers,
            codec: room.audio ? null : 'avc',
          ),
    ];
    if (lines.isEmpty) {
      // §4 stream type 50 is watchable in the app only.
      throw StreamUnavailable(_site, 'no liveUrl (liveStreamType ${room.streamType})');
    }
    return lines;
  }
}
