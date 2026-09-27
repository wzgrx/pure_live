import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/crypto/aes.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'bigo';

/// A studio answer reduced to what the adapter needs (spec/sites/bigo.md §4).
typedef BigoStudio = ({RoomDetail detail, Uri? hls});

/// Pure parsing of Bigo Live responses and the web token request (spec/sites/bigo.md).
abstract final class BigoParse {
  /// §1 a Bigo id (numeric or chosen by the streamer).
  static final RegExp siteId = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$');

  /// §1 path segments on bigo.tv that are pages, not rooms.
  static const reserved = {'about', 'download', 'index', 'live', 'login', 'search', 'signup', 'show', 'user'};

  /// §5 the only quality.
  static const auto = Quality(id: 'hls', label: '自动', rank: 1);

  static const _passphrase = 'undefinedval0x01';

  /// The room page.
  static Uri link(String id) => Uri.parse('https://www.bigo.tv/$id');

  /// §6.1 the `data` parameter of the token request: OpenSSL-style
  /// `Salted__` + salt + AES-256-CBC of the JSON, key and IV from
  /// EVP_BytesToKey(md5) over the web passphrase.
  static String tokenData(String timestamp, {Random? random, List<int>? salt, String? nonce}) {
    final rnd = random ?? Random.secure();
    final actualSalt = salt ?? List<int>.generate(8, (_) => rnd.nextInt(256));
    final dr = nonce ?? List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final payload = utf8.encode(
      jsonEncode({'dr': dr, 'business': 'bigolive-video', 'scene': '', 'at_time': timestamp, 'ver': '2.0'}),
    );
    final derived = BytesBuilder(copy: false);
    var previous = <int>[];
    while (derived.length < 48) {
      previous = md5.convert([...previous, ...utf8.encode(_passphrase), ...actualSalt]).bytes;
      derived.add(previous);
    }
    final bytes = derived.takeBytes();
    final encrypted = AesCbc.encrypt(payload, key: bytes.sublist(0, 32), iv: bytes.sublist(32, 48));
    return base64Encode([...ascii.encode('Salted__'), ...actualSalt, ...encrypted]);
  }

  /// A JSONP body `callback({...});` → its object.
  static Map<String, dynamic> jsonp(String body, String what) {
    final text = body.trim();
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open <= 0 || close <= open) throw ApiChanged(_site, '$what: not JSONP');
    try {
      final decoded = jsonDecode(text.substring(open + 1, close));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw ApiChanged(_site, '$what: not a JSON object');
  }

  /// §6.1 `webjs/t` → the server time for the token request.
  static String serverTime(String body) {
    final time = jsonString(jsonp(body, 'webjs/t')['time']);
    if (time == null || !RegExp(r'^\d{1,20}$').hasMatch(time)) throw const ApiChanged(_site, 'webjs/t: no time');
    return time;
  }

  /// §6.1 `webjs/status` → the web token.
  static String token(String body) {
    final token = jsonString(jsonp(body, 'webjs/status')['token']);
    if (token == null) throw const ApiChanged(_site, 'webjs/status: no token');
    return token;
  }

  static Map<String, dynamic> _data(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final code = jsonInt(decoded['code']);
    if (code != 0) throw ApiChanged(_site, '$what: code $code ${jsonString(decoded['msg']) ?? ''}');
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw ApiChanged(_site, '$what: no data');
    return data;
  }

  /// §2 `vedioList/72`: the public recommendation (one page); locked rooms
  /// are skipped.
  static Page<RoomCard> list(String body) {
    final data = _data(body, 'vedioList');
    if (jsonString(data['resCode']) != '0') throw ApiChanged(_site, 'vedioList: resCode ${data['resCode']}');
    final rows = data['data'];
    if (rows is! List) throw const ApiChanged(_site, 'vedioList: data is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = jsonString(row['bigo_id']);
      if (id == null || !siteId.hasMatch(id) || jsonInt(row['is_locked']) == 1 || !seen.add(id)) continue;
      final viewers = jsonInt(row['user_count']);
      final name = decodeHtmlEntities(jsonString(row['nick_name']) ?? '');
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(row['room_topic']) ?? name),
          anchorName: name,
          state: LiveState.live,
          cover: jsonUrl(row['cover_m']) ?? jsonUrl(row['cover_l']),
          area: jsonString(row['country_name']) ?? jsonString(row['country']),
          audience: Audience(online: viewers != null && viewers >= 0 ? viewers : null),
        ),
      );
    }
    return Page(cards);
  }

  /// §4 `studio/getInternalStudioInfo` with a web token.
  static BigoStudio studio(String body, {required String roomId}) {
    final data = _data(body, 'getInternalStudioInfo');
    if (data['needLogin'] == true) throw const NeedsLogin(_site, 'needLogin (no or stale web token, or region)');
    final name = decodeHtmlEntities(jsonString(data['nick_name']) ?? '');
    final alive = jsonInt(data['alive']);
    final state = switch (alive) {
      1 => LiveState.live,
      0 => LiveState.offline,
      _ => throw ApiChanged(_site, 'getInternalStudioInfo: alive $alive'),
    };
    final locked = data['passRoom'] == true || jsonString(data['isPaidShow']) == '1';
    final hls = jsonUrl(data['hls_src']);
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, roomId),
          title: decodeHtmlEntities(jsonString(data['roomTopic']) ?? name),
          anchorName: name,
          state: state,
          cover: jsonUrl(data['snapshot']),
          area: jsonString(data['gameTitle']),
        ),
        link: link(roomId),
        avatar: jsonUrl(data['avatar']),
        danmakuKeys: {'uid': ?jsonString(data['uid']), 'roomId': ?jsonString(data['roomId'])},
      ),
      hls: state == LiveState.live && !locked && hls != null && hls.path.endsWith('.m3u8') ? hls : null,
    );
  }

  /// §5 the one HLS line (segments need the §6.3 transform).
  static StreamLine line(Uri hls, {required Map<String, String> headers}) =>
      StreamLine(url: hls, format: StreamFormat.hls, lineId: hls.host, requested: auto, headers: headers, codec: 'avc');
}

/// §6.3 Bigo's web HLS protection: a playlist tag carries a seed; the first
/// two 188-byte TS packets of every segment are XOR-scrambled with a
/// xorshift stream from it. Applying [transform] twice restores the input.
abstract final class BigoProtection {
  static final RegExp _tag = RegExp(r'^#EXT-X-BIGO-WEB-PROTECTION:(.*)$', multiLine: true, caseSensitive: false);

  /// The seed of a media playlist, or null when it is not protected.
  static int? seed(String playlist) {
    final attributes = _tag.firstMatch(playlist)?.group(1);
    if (attributes == null) return null;
    final value = RegExp(r'(?:^|,)\s*SEED=(\d+)', caseSensitive: false).firstMatch(attributes)?.group(1);
    final seed = value == null ? null : int.tryParse(value);
    if (seed == null || seed > 0xffffffff) throw const ApiChanged(_site, 'bad HLS protection seed');
    return seed;
  }

  /// Unscrambles (or scrambles) a segment.
  static Uint8List transform(List<int> segment, int seed) {
    final packets = Uint8List.fromList(segment);
    for (var packet = 0; packet < 2 && (packet + 1) * 188 <= packets.length; packet++) {
      var state = (seed ^ ((packet + 1) * 2654435769)) & 0xffffffff;
      if (state == 0) state = 1831565813;
      for (var offset = 0; offset < 16; offset++) {
        state = (state ^ ((state << 13) & 0xffffffff)) & 0xffffffff;
        state = (state ^ (state >> 17)) & 0xffffffff;
        state = (state ^ ((state << 5) & 0xffffffff)) & 0xffffffff;
        var mask = state & 0xff;
        if (mask == 0) mask = 165;
        packets[packet * 188 + offset] ^= mask;
      }
    }
    return packets;
  }
}
