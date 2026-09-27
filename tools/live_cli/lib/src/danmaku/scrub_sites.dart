import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// Replaces every remaining occurrence of a replaced original in [text]:
/// names of two or more characters anywhere, numbers of five or more digits
/// between non-digits.
String _elsewhere(Pseudonyms names, String text) {
  var out = text;
  for (final MapEntry(key: original, value: replacement) in names.pairs) {
    if (RegExp(r'^\d+$').hasMatch(original)) {
      if (original.length < 5) continue;
      out = out.replaceAll(RegExp('(?<![0-9])$original(?![0-9])'), replacement);
    } else if (original.runes.length >= 2) {
      out = out.replaceAll(original, replacement);
    }
  }
  return out;
}

// ---------------------------------------------------------------- Douyu

/// Douyu: STT fields of viewers (`nn`, `uid`, `ic`, …) and the client IP of
/// `loginres`.
class DouyuFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _people = {'nn', 'un', 'dnn', 'sn', 'uname', 'nickname', 'username', 'unk'};
  static const _ids = {'uid', 'userid', 'suid', 'duid'};
  static const _secrets = {'ic', 'uat', 'ip', 'hc', 'avatar', 'sessionid', 'uic'};

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final bytes = Uint8List.fromList(frame.bytes);
    final view = ByteData.sublistView(bytes);
    final out = BytesBuilder();
    var offset = 0;
    while (offset + 12 <= bytes.length) {
      final length = view.getUint32(offset, Endian.little);
      if (length < 9 || offset + 4 + length > bytes.length) break;
      final type = view.getUint16(offset + 8, Endian.little);
      var end = offset + 4 + length;
      if (bytes[end - 1] == 0) end--;
      final body = utf8.decode(bytes.sublist(offset + 12, end), allowMalformed: true);
      out.add(DouyuProtocol.packet(_elsewhere(names, _stt(body, '')), type: type));
      offset += 4 + length;
    }
    if (offset < bytes.length) record('frame.trailing', 'dropped');
    return out.takeBytes();
  }

  /// Scrubs one STT map (escaped once per nesting level already removed).
  String _stt(String text, String path) {
    final parts = text.split('/');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final separator = part.indexOf('@=');
      if (separator <= 0) continue;
      final key = Stt.unescape(part.substring(0, separator));
      final value = Stt.unescape(part.substring(separator + 2));
      final where = path.isEmpty ? key : '$path.$key';
      String next;
      if (_people.contains(key)) {
        next = names.person(value);
        record(where, 'person');
      } else if (_ids.contains(key)) {
        next = names.digits(value);
        record(where, 'person');
      } else if (_secrets.contains(key)) {
        next = key == 'uat'
            ? Stt.list(value).map(names.secret).map((item) => '${Stt.escape(item)}/').join()
            : names.secret(value);
        record(where, 'secret');
      } else if (value.contains('@=')) {
        next = _stt(value, where);
      } else if (value.contains('@A=')) {
        next = value
            .split('/')
            .map((item) => item.isEmpty ? item : Stt.escape(_stt(Stt.unescape(item), '$where[]')))
            .join('/');
      } else {
        continue;
      }
      parts[i] = '${part.substring(0, separator)}@=${Stt.escape(next)}';
    }
    return parts.join('/');
  }

  @override
  List<int> plain(CapturedFrame frame) => utf8.encode(
    DouyuProtocol.bodies(frame.bytes)
        .map((body) => '$body\n${Stt.unescape(body)}\n${Stt.unescape(Stt.unescape(body))}')
        .join('\n'),
  );
}

// ----------------------------------------------------------------- Huya

/// Huya: senders of uri 1400 rebuilt from uid and nick only; bodies of
/// other uris except 8006 emptied (their layouts are not decoded and hold
/// viewer names).
class HuyaFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const Set<int> _keep = {HuyaProtocol.popularityUri};

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    if (frame.direction == 'out') return frame.bytes;
    if (frame.url != null) return _board(frame.bytes);
    final outer = TarsStruct.decode(frame.bytes);
    final payload = outer.bytes(1);
    if (payload == null) return frame.bytes;
    final command = outer.integer(0);
    Uint8List? scrubbed;
    if (command == 7) {
      final push = TarsStruct.decode(payload);
      scrubbed = TarsStruct({...push.fields, 2: _body(push.integer(1), push.bytes(2))}).encode();
    } else if (command == 22) {
      final push = TarsStruct.decode(payload);
      scrubbed = TarsStruct({
        ...push.fields,
        1: [
          for (final item in push.list(1).whereType<TarsStruct>())
            TarsStruct({...item.fields, 1: _body(item.integer(0), item.bytes(1))}),
        ],
      }).encode();
    }
    if (scrubbed == null) return frame.bytes;
    return TarsStruct({...outer.fields, 1: scrubbed}).encode();
  }

  /// A `getHeadLineMessageBoard` WUP response: each item's user (tag 0:
  /// nick 1, avatar 2) rebuilt.
  Uint8List _board(List<int> bytes) {
    final packet = TarsStruct.decode(bytes.sublist(4));
    final buffer = TarsStruct.decode(packet.bytes(7)!);
    final params = Map<Object?, Object?>.of(buffer.fields[0]! as Map<Object?, Object?>);
    final response = TarsStruct.decode(params['tRsp']! as Uint8List);
    final rsp = response.struct(0)!;
    final panel = rsp.struct(1);
    if (panel != null) {
      final items = [
        for (final item in panel.list(1).whereType<TarsStruct>())
          TarsStruct({
            ...item.fields,
            0: TarsStruct({
              1: names.person(item.struct(0)?.string(1) ?? ''),
              2: names.secret(item.struct(0)?.string(2) ?? ''),
            }),
          }),
      ];
      if (items.isNotEmpty) record('headline.user', 'person');
      params['tRsp'] = TarsStruct({
        ...response.fields,
        0: TarsStruct({
          ...rsp.fields,
          1: TarsStruct({...panel.fields, 1: items}),
        }),
      }).encode();
    }
    final body = TarsStruct({
      ...packet.fields,
      7: TarsStruct({...buffer.fields, 0: params}).encode(),
    }).encode();
    return (BytesBuilder()
          ..add((ByteData(4)..setInt32(0, body.length + 4)).buffer.asUint8List())
          ..add(body))
        .takeBytes();
  }

  Uint8List _body(int? uri, Uint8List? body) {
    if (body == null) return Uint8List(0);
    if (uri == HuyaProtocol.chatUri) return _chat(body);
    if (_keep.contains(uri)) return body;
    record('uri $uri body', 'dropped');
    return Uint8List(0);
  }

  Uint8List _chat(Uint8List body) {
    final message = TarsStruct.decode(body);
    final sender = message.struct(0);
    final uid = sender?.integer(0) ?? 0;
    record('1400.sender', 'person');
    return TarsStruct({
      ...message.fields,
      0: TarsStruct({
        0: uid > 0 ? int.parse(names.digits('$uid')) : uid,
        1: 0,
        2: names.person(sender?.string(2) ?? ''),
        3: sender?.integer(3) ?? 0,
      }),
      // Decorations and badges carry viewer ids and assets.
      for (final tag in const [8, 9, 10, 12, 15, 16])
        if (message.fields.containsKey(tag)) tag: const <Object?>[],
    }).encode();
  }
}

// ------------------------------------------------------------- Bilibili

/// Bilibili: the auth token, buvid and uid of the client's auth packet;
/// viewer names, ids, faces and hashes in every notice (by key, and by
/// position in `DANMU_MSG`); protobuf blobs (`dm_v2`, `pb`) emptied.
/// Compressed packets are inflated, scrubbed and deflated again.
class BilibiliFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _people = {'uname', 'username', 'user_name', 'reply_uname', 'nickname', 'nick_name'};
  static const _ids = {'uid', 'mid', 'reply_mid', 'user_id'};
  static const _secrets = {'face', 'user_hash', 'avatar', 'buvid', 'key', 'token', 'uface'};
  static const _blobs = {'dm_v2', 'pb'};

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    if (frame.text) return utf8.encode(_json(utf8.decode(frame.bytes)));
    return _packets(Uint8List.fromList(frame.bytes));
  }

  Uint8List _packets(Uint8List data) {
    final view = ByteData.sublistView(data);
    final out = BytesBuilder();
    var offset = 0;
    while (offset + 16 <= data.length) {
      final length = view.getUint32(offset);
      final header = view.getUint16(offset + 4);
      final version = view.getUint16(offset + 6);
      final op = view.getUint32(offset + 8);
      final seq = view.getUint32(offset + 12);
      if (header < 16 || length < header || offset + length > data.length) break;
      final body = data.sublist(offset + header, offset + length);
      List<int> next = body;
      if (op == BilibiliProtocol.opNotice && version == 2) {
        next = zlib.encode(_packets(BilibiliProtocol.inflate(body)));
      } else if ((op == BilibiliProtocol.opNotice && version == 0) || op == BilibiliProtocol.opAuth) {
        final text = utf8.decode(body, allowMalformed: true);
        if (text.trim().isNotEmpty) next = utf8.encode(_json(text));
      }
      final packet = Uint8List(16 + next.length);
      ByteData.sublistView(packet)
        ..setUint32(0, packet.length)
        ..setUint16(4, 16)
        ..setUint16(6, version)
        ..setUint32(8, op)
        ..setUint32(12, seq);
      packet.setRange(16, packet.length, next);
      out.add(packet);
      offset += length;
    }
    if (offset < data.length) record('frame.trailing', 'dropped');
    return out.takeBytes();
  }

  String _json(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return text;
    }
    if (value is Map<String, dynamic> && '${value['cmd']}'.contains('DANMU_MSG')) _danmu(value);
    return _elsewhere(names, jsonEncode(_walk(value, r'$')));
  }

  /// `DANMU_MSG` positions: `info[2]` is [uid, name, …], `info[0][7]` the
  /// sender hash.
  void _danmu(Map<String, dynamic> notice) {
    final info = notice['info'];
    if (info is! List || info.length < 3) return;
    if (info[2] case final List<dynamic> user when user.length > 1) {
      user[0] = user[0] is int ? int.parse(names.digits('${user[0]}')) : names.digits('${user[0]}');
      user[1] = names.person('${user[1]}');
      record(r'$.info[2][0,1]', 'person');
    }
    if (info[0] case final List<dynamic> meta when meta.length > 7 && meta[7] is String) {
      meta[7] = names.secret(meta[7] as String);
      record(r'$.info[0][7]', 'secret');
    }
  }

  Object? _walk(Object? node, String path, [String? key, String? parent]) {
    switch (node) {
      case final Map<String, dynamic> map:
        return {
          for (final MapEntry(:key, :value) in map.entries) key: _walk(value, '$path.$key', key, path.split('.').last),
        };
      case final List<dynamic> list:
        return [for (final item in list) _walk(item, '$path[*]', null, parent)];
      case final String text when key != null:
        if (_blobs.contains(key)) {
          record(path, 'dropped');
          return '';
        }
        if (_people.contains(key) || (key == 'name' && (parent == 'base' || parent == 'origin_info'))) {
          record(path, 'person');
          return names.person(text);
        }
        if (_ids.contains(key)) {
          record(path, 'person');
          return names.digits(text);
        }
        if (_secrets.contains(key)) {
          record(path, 'secret');
          return names.secret(text);
        }
        final trimmed = text.trimLeft();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            return jsonEncode(_walk(jsonDecode(text), '$path(json)'));
          } on FormatException {
            return text;
          }
        }
        return text;
      case final int number when key != null && _ids.contains(key) && number > 0:
        record(path, 'person');
        return int.parse(names.digits('$number'));
      default:
        return node;
    }
  }

  @override
  List<int> plain(CapturedFrame frame) {
    if (frame.text) return frame.bytes;
    final out = BytesBuilder();
    void collect(Uint8List data, int depth) {
      final view = ByteData.sublistView(data);
      var offset = 0;
      while (offset + 16 <= data.length) {
        final length = view.getUint32(offset);
        final header = view.getUint16(offset + 4);
        if (header < 16 || length < header || offset + length > data.length) return;
        final body = data.sublist(offset + header, offset + length);
        if (view.getUint16(offset + 6) == 2 && depth < 3) {
          collect(BilibiliProtocol.inflate(body), depth + 1);
        } else {
          out.add(body);
        }
        offset += length;
      }
    }

    collect(Uint8List.fromList(frame.bytes), 0);
    return out.takeBytes();
  }
}

// --------------------------------------------------------------- Douyin

/// Douyin: the visitor id (`user_unique_id`, `wss_push_did`) everywhere;
/// chat senders rebuilt from id and nickname only; ranked viewer lists of
/// `RoomUserSeqMessage` and the payloads of every other method emptied.
class DouyinFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed}) {
    final visitor = detail.danmakuKeys['userUniqueId'];
    if (visitor != null) names.digits(visitor);
  }

  static const _keep = {'WebcastRoomUserSeqMessage', 'WebcastChatMessage'};

  @override
  Map<String, String> scrubKeys(Map<String, String> keys) => {
    for (final MapEntry(:key, :value) in keys.entries) key: key == 'userUniqueId' ? names.digits(value) : value,
  };

  @override
  Uri scrubUrl(Uri url) {
    if (!url.queryParameters.containsKey('signature')) return url;
    record('handshake.signature', 'secret');
    record('handshake.user_unique_id', 'person');
    return url.replace(
      queryParameters: {
        ...url.queryParameters,
        'signature': names.secret(url.queryParameters['signature']!),
        'user_unique_id': names.digits(url.queryParameters['user_unique_id'] ?? ''),
      },
    );
  }

  String _text(String value) => _elsewhere(names, value);

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final push = ProtoMessage.decode(frame.bytes);
    final writer = ProtoWriter();
    for (final field in push.fields) {
      if (field.number == 5 && field.value is Uint8List) {
        // HeadersList{key 1, value 2}
        final header = ProtoMessage.decode(field.value as Uint8List);
        writer.bytes(
          5,
          (ProtoWriter()
                ..string(1, header.string(1) ?? '')
                ..string(2, _text(header.string(2) ?? '')))
              .toBytes(),
        );
      } else if (field.number == 8 && field.value is Uint8List) {
        final payload = field.value as Uint8List;
        final type = push.string(7);
        if (type == 'ack') {
          writer.bytes(8, utf8.encode(_text(utf8.decode(payload, allowMalformed: true))));
        } else if (type == 'msg') {
          final gzipped = payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b;
          final response = _response(ProtoMessage.decode(gzipped ? gzip.decode(payload) : payload));
          writer.bytes(8, gzipped ? gzip.encode(response) : response);
        } else {
          writer.field(field);
        }
      } else {
        writer.field(field);
      }
    }
    return writer.toBytes();
  }

  Uint8List _response(ProtoMessage response) {
    final writer = ProtoWriter();
    for (final field in response.fields) {
      switch (field.number) {
        case 1:
          writer.bytes(1, _message(ProtoMessage.decode(field.value as Uint8List)));
        case 5 || 2 || 10 || 11:
          writer.string(field.number, _text(utf8.decode(field.value as Uint8List, allowMalformed: true)));
        case 7:
          // routeParams map entries {key 1, value 2}
          final entry = ProtoMessage.decode(field.value as Uint8List);
          writer.bytes(
            7,
            (ProtoWriter()
                  ..string(1, entry.string(1) ?? '')
                  ..string(2, _text(entry.string(2) ?? '')))
                .toBytes(),
          );
        default:
          writer.field(field);
      }
    }
    return writer.toBytes();
  }

  Uint8List _message(ProtoMessage message) {
    final method = message.string(1) ?? '';
    final writer = ProtoWriter();
    for (final field in message.fields) {
      if (field.number != 2) {
        writer.field(field);
        continue;
      }
      final payload = field.value as Uint8List;
      if (!_keep.contains(method)) {
        record('$method.payload', 'dropped');
        writer.bytes(2, const []);
      } else if (method == 'WebcastChatMessage') {
        writer.bytes(2, _chat(ProtoMessage.decode(payload)));
      } else {
        // RoomUserSeqMessage: ranksList 2 and seatsList 5 hold viewers.
        final seq = ProtoMessage.decode(payload);
        final out = ProtoWriter();
        for (final item in seq.fields) {
          if (item.number == 2 || item.number == 5) continue;
          if (item.number == 1) {
            out.bytes(1, _common(ProtoMessage.decode(item.value as Uint8List)));
          } else {
            out.field(item);
          }
        }
        record('$method.ranks', 'dropped');
        writer.bytes(2, out.toBytes());
      }
    }
    return writer.toBytes();
  }

  /// `ChatMessage`: common (without its user), sender {id, nickName},
  /// content and eventTime; the rest (badges, rich text, labels) dropped.
  Uint8List _chat(ProtoMessage chat) {
    final writer = ProtoWriter();
    for (final field in chat.fields) {
      switch (field.number) {
        case 1:
          writer.bytes(1, _common(ProtoMessage.decode(field.value as Uint8List)));
        case 2:
          final user = ProtoMessage.decode(field.value as Uint8List);
          final id = user.integer(1) ?? 0;
          final replacement = id > 0 ? int.parse(names.digits('$id')) : id;
          writer.bytes(
            2,
            (ProtoWriter()
                  ..integer(1, replacement)
                  ..string(3, names.person(user.string(3) ?? '')))
                .toBytes(),
          );
          record('ChatMessage.user', 'person');
        case 3 || 4 || 15:
          writer.field(field);
        default:
          record('ChatMessage.${field.number}', 'dropped');
      }
    }
    return writer.toBytes();
  }

  /// `Common` without its user (15) and display text (8).
  Uint8List _common(ProtoMessage common) {
    final writer = ProtoWriter();
    for (final field in common.fields) {
      if (field.number == 15 || field.number == 8) continue;
      writer.field(field);
    }
    return writer.toBytes();
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final push = ProtoMessage.decode(frame.bytes);
    final payload = push.bytes(8) ?? Uint8List(0);
    final gzipped = payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b;
    return [...frame.bytes, ...(gzipped ? gzip.decode(payload) : payload)];
  }
}

// ------------------------------------------------------------- Kuaishou

/// Kuaishou (spec §11): authors (`userName`, `userId`, `headurl`) and the
/// comment text replaced; the liveStreamId in URLs and keys replaced.
class KuaishouFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Map<String, String> scrubKeys(Map<String, String> keys) => {
    for (final MapEntry(:key, :value) in keys.entries) key: key == 'liveStreamId' ? names.secret(value) : value,
  };

  @override
  Uri scrubUrl(Uri url) {
    final stream = url.queryParameters['liveStreamId'];
    if (stream == null) return url;
    record('url.liveStreamId', 'secret');
    return url.replace(queryParameters: {...url.queryParameters, 'liveStreamId': names.secret(stream)});
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    var layers = 0;
    Object? value = utf8.decode(frame.bytes);
    try {
      while (value is String && layers < 3) {
        value = jsonDecode(value);
        layers++;
      }
    } on FormatException {
      return frame.bytes;
    }
    final root = value is Map<String, dynamic> && value['data'] is Map<String, dynamic>
        ? value['data'] as Map<String, dynamic>
        : value;
    if (root is Map<String, dynamic>) {
      for (final feed in (root['liveStreamFeeds'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()) {
        final author = feed['author'];
        if (author is Map<String, dynamic>) {
          if (author['userName'] is String) author['userName'] = names.person(author['userName'] as String);
          if (author['userId'] != null) {
            final id = names.digits('${author['userId']}');
            author['userId'] = author['userId'] is int ? int.parse(id) : id;
          }
          for (final key in const ['headurl', 'userText', 'avatar']) {
            if (author[key] is String) author[key] = names.secret(author[key] as String);
          }
          record(r'$.liveStreamFeeds[*].author', 'person');
        }
        if (feed['content'] is String) {
          feed['content'] = names.text(feed['content'] as String);
          record(r'$.liveStreamFeeds[*].content', 'person');
        }
      }
    }
    var text = jsonEncode(value);
    for (var i = 1; i < layers; i++) {
      text = jsonEncode(text);
    }
    return utf8.encode(_elsewhere(names, text));
  }
}
