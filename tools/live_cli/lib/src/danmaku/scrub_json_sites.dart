import 'dart:convert';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// Replaces every remaining occurrence of a replaced original in [text]:
/// names of two or more characters anywhere, numbers of five or more digits
/// between non-digits (as `scrub_sites.dart` does for the first batch).
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

/// Frame scrubbing for chat protocols whose messages are JSON: keys are
/// matched at any depth; string fields named in [nested] that hold JSON are
/// decoded, scrubbed and encoded again.
abstract class JsonFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  /// Keys whose values are secrets (tokens, session ids, images).
  Set<String> get secrets;

  /// Keys whose values identify a viewer (ids, hashes).
  Set<String> get ids;

  /// Keys whose values are viewers' display names.
  Set<String> get people;

  /// Keys whose string values are JSON documents.
  Set<String> get nested => const {};

  /// Keys left untouched whatever the other sets say (public streamer data).
  Set<String> get kept => const {};

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(frame.bytes));
    } on FormatException {
      return frame.bytes;
    }
    return utf8.encode(_elsewhere(names, jsonEncode(walk(value, r'$'))));
  }

  /// Scrubs [node] in place; [path] names it in the records.
  Object? walk(Object? node, String path) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        final where = '$path.$key';
        if (kept.contains(key)) continue;
        if (value is String && value.isNotEmpty && secrets.contains(key)) {
          node[key] = names.secret(value);
          record(where, 'secret');
        } else if ((value is String || value is int) && '$value'.isNotEmpty && ids.contains(key)) {
          final replaced = value is int ? names.digits('$value') : names.secret(value as String);
          node[key] = value is int ? int.parse(replaced) : replaced;
          record(where, 'person');
        } else if (value is String && people.contains(key)) {
          node[key] = names.person(value);
          record(where, 'person');
        } else if (value is String && nested.contains(key) && value.trimLeft().startsWith('{')) {
          try {
            node[key] = jsonEncode(walk(jsonDecode(value), where));
          } on FormatException {
            // Not JSON after all; left as is.
          }
        } else {
          node[key] = walk(value, where);
        }
      }
      return node;
    }
    if (node is List) {
      for (var index = 0; index < node.length; index++) {
        node[index] = walk(node[index], '$path[*]');
      }
    }
    return node;
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    // Nested JSON strings hold their values escaped once.
    return utf8.encode('$text\n${text.replaceAll(r'\"', '"').replaceAll(r'\/', '/')}');
  }
}

/// A Brotli stream holding [data] in uncompressed meta-blocks (RFC 7932
/// §9.2): the scrubbed frames stay decodable by the real decoder without a
/// Brotli compressor.
List<int> brotliStored(List<int> data) {
  final out = <int>[];
  var bits = 0;
  var count = 0;
  void write(int value, int width) {
    for (var bit = 0; bit < width; bit++) {
      bits |= ((value >> bit) & 1) << count;
      count++;
      if (count == 8) {
        out.add(bits);
        bits = 0;
        count = 0;
      }
    }
  }

  void flush() {
    if (count > 0) {
      out.add(bits);
      bits = 0;
      count = 0;
    }
  }

  write(0, 1); // WBITS = 16
  for (var offset = 0; offset < data.length; offset += 65536) {
    final length = data.length - offset < 65536 ? data.length - offset : 65536;
    write(0, 1); // ISLAST
    write(0, 2); // MNIBBLES = 4
    write(length - 1, 16); // MLEN - 1
    write(1, 1); // ISUNCOMPRESSED
    flush();
    out.addAll(data.sublist(offset, offset + length));
  }
  write(1, 1); // ISLAST
  write(1, 1); // ISLASTEMPTY
  flush();
  return out;
}

/// Missevan (spec/sites/missevan.md §11): frames are Brotli JSON behind a
/// four-byte header; they are decoded, scrubbed (viewers' ids, names and
/// images, the join uuid) and stored again as uncompressed Brotli with the
/// new length.
class MissevanFrameScrubber extends JsonFrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Set<String> get secrets => const {'uuid', 'iconurl'};

  @override
  Set<String> get ids => const {'user_id'};

  @override
  Set<String> get people => const {'username'};

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final json = MissevanProtocol.text(frame.bytes);
    if (frame.text || frame.bytes.isEmpty || frame.bytes[0] != 1 || json == null) return super.scrubFrame(frame);
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      return frame.bytes;
    }
    final plain = utf8.encode(_elsewhere(names, jsonEncode(walk(value, r'$'))));
    return [1, plain.length & 0xff, (plain.length >> 8) & 0xff, (plain.length >> 16) & 0xff, ...brotliStored(plain)];
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final json = frame.text ? null : MissevanProtocol.text(frame.bytes);
    return json == null ? super.plain(frame) : utf8.encode(json);
  }
}

/// KilaKila (spec/sites/kilakila.md §11): Socket.IO text frames whose
/// `text_message` payload nests the message as a JSON string. Chat (200)
/// and gift (220) messages keep their text and gift, with the sender's uid,
/// name and avatar replaced and the viewer decorations (`ui`, `uc`)
/// dropped; other message types keep only their type (their fields are
/// not decoded and name viewers).
class KilakilaFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _prefix = '42${KilakilaProtocol.namespace},';

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    if (!text.startsWith(_prefix)) return frame.bytes;
    final Object? packet;
    try {
      packet = jsonDecode(text.substring(_prefix.length));
    } on FormatException {
      return frame.bytes;
    }
    if (packet is! List || packet.length < 2 || packet[0] != 'text_message' || packet[1] is! String) {
      return frame.bytes;
    }
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(packet[1] as String) as Map<String, dynamic>;
    } on Object {
      return frame.bytes;
    }
    final response = (message['body'] as Map<String, dynamic>?)?['response'];
    if (response is Map<String, dynamic>) {
      final sender = response['sender_info'];
      if (sender is Map<String, dynamic>) {
        if (sender['uid'] != null) sender['uid'] = int.tryParse(names.digits('${sender['uid']}')) ?? 0;
        for (final key in const ['nickname', 'avatar']) {
          if (sender[key] is String) sender[key] = names.secret(sender[key] as String);
        }
        record(r'$.body.response.sender_info', 'person');
      }
      final content = response['content'] is String ? jsonDecode(response['content'] as String) : null;
      if (content is Map<String, dynamic>) {
        final type = content['t'];
        if (type == 200 || type == 220) {
          if (content['u'] != null) {
            final id = names.digits('${content['u']}');
            content['u'] = content['u'] is int ? int.parse(id) : id;
          }
          if (content['n'] is String) content['n'] = names.person(content['n'] as String);
          if (content['a'] is String) content['a'] = names.secret(content['a'] as String);
          content
            ..remove('ui')
            ..remove('uc');
          record(r'$.content[t=200,220]', 'person');
          response['content'] = jsonEncode(content);
        } else {
          response['content'] = jsonEncode({'t': type});
          record(r'$.content[other t]', 'dropped');
        }
      }
      response.remove('user_group_ratio');
    }
    final out = '$_prefix${jsonEncode([packet[0], jsonEncode(message)])}';
    return utf8.encode(_elsewhere(names, out));
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    return utf8.encode('$text\n${text.replaceAll(r'\\\"', '"').replaceAll(r'\"', '"')}');
  }
}

/// Picarto (spec/sites/picarto.md §11): the anonymous chat JWT (token
/// response and handshake path); viewers' ids, names and avatar paths in
/// chat (`c`) and join (`un`) messages. Stream updates name public
/// channels under other keys and stay.
class PicartoFrameScrubber extends JsonFrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Set<String> get secrets => const {'key', 'i'};

  @override
  Set<String> get ids => const {'u'};

  @override
  Set<String> get people => const {'n'};

  @override
  Uri scrubUrl(Uri url) {
    final match = RegExp('token=([A-Za-z0-9_.-]+)').firstMatch(url.path);
    if (match == null) return url;
    record('handshake.token', 'secret');
    return url.replace(path: url.path.replaceFirst(match.group(1)!, names.secret(match.group(1)!)));
  }
}

/// CHZZK (spec/sites/chzzk.md §11): the access token and session ids in
/// the join, the recent-chat request and the token response; viewers' ids,
/// hashes, nicknames, images and per-message tokens in chat items, whose
/// `profile` and `extras` are JSON strings. `streamingChannelId` is the
/// streamer's public channel id.
class ChzzkFrameScrubber extends JsonFrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Set<String> get secrets => const {'accTkn', 'accessToken', 'extraToken', 'sid', 'uuid', 'profileImageUrl'};

  @override
  Set<String> get ids => const {'uid', 'userId', 'userIdHash', 'cuid'};

  @override
  Set<String> get people => const {'nickname'};

  @override
  Set<String> get nested => const {'profile', 'extras'};

  @override
  Set<String> get kept => const {'streamingChannelId', 'channelId', 'cid'};
}
