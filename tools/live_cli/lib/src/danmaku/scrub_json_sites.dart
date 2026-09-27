import 'dart:convert';
import 'dart:io';

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

/// TwitCasting (spec/sites/twitcasting.md §11): the signed socket URL
/// (`token`, `n`) in the pubsub answer and the handshake; comment authors'
/// ids, names, screen names and images.
class TwitcastingFrameScrubber extends JsonFrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Set<String> get secrets => const {'profileImage', 'screenName'};

  @override
  Set<String> get ids => const {'id'};

  @override
  Set<String> get people => const {'name'};

  @override
  Uri scrubUrl(Uri url) {
    if (!url.queryParameters.containsKey('token')) return url;
    record('url.token', 'secret');
    return url.replace(
      queryParameters: {
        for (final entry in url.queryParameters.entries)
          entry.key: entry.key == 'token' || entry.key == 'n' ? names.secret(entry.value) : entry.value,
      },
    );
  }

  @override
  Object? walk(Object? node, String path) {
    if (node is Map && node['url'] is String && (node['url'] as String).contains('token=')) {
      node['url'] = scrubUrl(Uri.parse(node['url'] as String)).toString();
      return node;
    }
    return super.walk(node, path);
  }
}

/// SHOWROOM (spec/sites/showroom.md §11): `MSG\t<key>\t<json>` frames.
/// Comments (t 1) and gifts (t 2) keep their text and gift with the
/// viewer's id, name and avatar replaced; other types (visits, telops,
/// notices naming viewers) keep only their type.
class ShowroomFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    if (!text.startsWith('MSG\t')) return frame.bytes;
    final parts = text.split('\t');
    if (parts.length < 3) return frame.bytes;
    final Object? message;
    try {
      message = jsonDecode(parts.sublist(2).join('\t'));
    } on FormatException {
      return frame.bytes;
    }
    if (message is! Map<String, dynamic>) return frame.bytes;
    final type = '${message['t']}';
    Map<String, dynamic> kept;
    if (type == '1' || type == '2') {
      kept = {
        for (final key in const ['t', 'cm', 'g', 'n', 'created_at'])
          if (message.containsKey(key)) key: message[key],
        if (message['u'] != null) 'u': int.tryParse(names.digits('${message['u']}')) ?? 0,
        if (message['ac'] is String) 'ac': names.person(message['ac'] as String),
      };
      record(r'$[t=1,2].u/ac', 'person');
    } else {
      kept = {'t': message['t']};
      record(r'$[other t]', 'dropped');
    }
    return utf8.encode(_elsewhere(names, 'MSG\t${parts[1]}\t${jsonEncode(kept)}'));
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

/// PandaTV (spec/sites/pandalive.md §11). The `live/play` answer keeps only
/// what the connector reads (result, channel, the broadcaster's `media`
/// identity) with the chat token replaced; its fan list, viewer network,
/// session key and playback tokens are dropped. Centrifugo frames: the
/// token in the connect command, the client id and the viewer's personal
/// channel in its reply; chat keeps type, text, emoticon and time with the
/// sender's login id, index and nickname replaced and the rest (the
/// viewer's address hash, device, level, languages) dropped; heart gifts
/// keep their count; other pushes keep only their type (their messages
/// name viewers).
class PandaliveFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    if (frame.url != null) return utf8.encode(_play(text));
    final lines = [for (final line in const LineSplitter().convert(text)) _line(line)];
    return utf8.encode(_elsewhere(names, lines.join('\n')));
  }

  String _play(String text) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return text;
    }
    if (root is! Map<String, dynamic>) return text;
    final media = root['media'];
    record(r'$ (live/play)', 'reduced');
    return jsonEncode({
      'result': root['result'],
      'message': root['message'],
      if (root['errorData'] != null) 'errorData': root['errorData'],
      if (root['channel'] != null) 'channel': root['channel'],
      if (root['token'] is String) 'token': names.secret(root['token'] as String),
      if (media is Map) 'media': {'userId': media['userId'], 'userIdx': media['userIdx'], 'isLive': media['isLive']},
    });
  }

  String _line(String line) {
    final Object? reply;
    try {
      reply = jsonDecode(line);
    } on FormatException {
      return line;
    }
    if (reply is! Map<String, dynamic>) return line;
    final params = reply['params'];
    if (params is Map<String, dynamic> && params['token'] is String) {
      params['token'] = names.secret(params['token'] as String);
      record(r'$.params.token', 'secret');
    }
    final result = reply['result'];
    if (result is Map<String, dynamic>) {
      if (result['client'] is String) {
        result['client'] = names.secret(result['client'] as String);
        record(r'$.result.client', 'secret');
      }
      final subs = result['subs'];
      if (subs is Map<String, dynamic>) {
        result['subs'] = {for (final entry in subs.entries) names.secret(entry.key): entry.value};
        record(r'$.result.subs', 'secret');
      }
      final publication = result['data'];
      if (publication is Map<String, dynamic> && publication['data'] is Map<String, dynamic>) {
        publication['data'] = _message(publication['data'] as Map<String, dynamic>);
      }
    }
    return jsonEncode(reply);
  }

  Map<String, dynamic> _message(Map<String, dynamic> message) {
    final type = '${message['type']}';
    if (PandaliveProtocol.chatTypes.contains(type)) {
      record(r'$.result.data.data[chat]', 'person');
      return {
        for (final key in const ['type', 'message', 'emoticon', 'filtered', 'created_at'])
          if (message.containsKey(key)) key: message[key],
        if (message['id'] is String) 'id': names.secret(message['id'] as String),
        if (message['idx'] != null) 'idx': int.tryParse(names.digits('${message['idx']}')) ?? 0,
        if (message['nk'] is String) 'nk': names.person(message['nk'] as String),
      };
    }
    if (type == 'SponCoin' || type == 'ItemCoin') {
      final raw = message['message'];
      Object? body;
      try {
        body = raw is String ? jsonDecode(raw) : raw;
      } on FormatException {
        body = null;
      }
      if (body is Map<String, dynamic>) {
        record(r'$.result.data.data[gift]', 'person');
        final kept = {
          if (body['coin'] != null) 'coin': body['coin'],
          if (body.containsKey('heart')) 'heart': const <String, Object?>{},
          if (body['id'] is String) 'id': names.secret(body['id'] as String),
          if (body['idx'] != null) 'idx': int.tryParse(names.digits('${body['idx']}')) ?? 0,
          if (body['nick'] is String) 'nick': names.person(body['nick'] as String),
        };
        return {'type': type, 'message': jsonEncode(kept), 'created_at': message['created_at']};
      }
    }
    record(r'$.result.data.data[other]', 'dropped');
    return {'type': type, 'created_at': message['created_at']};
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    return utf8.encode('$text\n${text.replaceAll(r'\"', '"').replaceAll(r'\/', '/')}');
  }
}

/// 17LIVE (spec/sites/17live.md §11): the anonymous Ably token (auth
/// answer and handshake URL), the connection's id, key and server; message
/// payloads are gunzipped, reduced and gzipped again: comments keep their
/// text and time, gifts their id, live info its viewer count, each with the
/// sender's id and name replaced; other types keep only their type (their
/// payloads name viewers and supporters).
class SeventeenliveFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  Uri scrubUrl(Uri url) {
    final token = url.queryParameters['access_token'];
    if (token == null) return url;
    record('handshake.access_token', 'secret');
    return url.replace(queryParameters: {...url.queryParameters, 'access_token': names.secret(token)});
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(frame.bytes));
    } on FormatException {
      return frame.bytes;
    }
    if (root is! Map<String, dynamic>) return frame.bytes;
    if (root['token'] is String) {
      root['token'] = names.secret(root['token'] as String);
      record(r'$.token', 'secret');
    }
    if (root['connectionId'] is String) {
      root['connectionId'] = names.secret(root['connectionId'] as String);
      record(r'$.connectionId', 'secret');
    }
    final details = root['connectionDetails'];
    if (details is Map<String, dynamic>) {
      for (final key in const ['connectionKey', 'serverId']) {
        if (details[key] is String) {
          details[key] = names.secret(details[key] as String);
          record('\$.connectionDetails.$key', 'secret');
        }
      }
    }
    final messages = root['messages'];
    if (messages is List) {
      for (final message in messages) {
        if (message is! Map<String, dynamic>) continue;
        final payload = SeventeenliveProtocol.payload(message['data']);
        if (payload == null) continue;
        message['data'] = base64.encode(gzip.encode(utf8.encode(jsonEncode(_reduce(payload)))));
      }
    }
    return utf8.encode(_elsewhere(names, jsonEncode(root)));
  }

  Map<String, Object?> _user(Object? user) {
    if (user is! Map) return const {};
    return {
      if (user['userID'] is String) 'userID': names.secret(user['userID'] as String),
      if (user['displayName'] is String) 'displayName': names.person(user['displayName'] as String),
    };
  }

  Map<String, Object?> _reduce(Map<String, dynamic> payload) {
    final type = payload['type'];
    final comment = payload['commentMsg'];
    if (type == 3 && comment is Map) {
      record(r'$.messages[*].data[type 3]', 'person');
      final body = comment['comment'];
      return {
        'type': type,
        'commentMsg': {
          'comment': {'text': body is Map ? body['text'] : null},
          'content': comment['content'],
          'sendTime': comment['sendTime'],
          'displayUser': _user(comment['displayUser']),
        },
      };
    }
    final gift = payload['giftMsg'];
    if (type == 13 && gift is Map) {
      record(r'$.messages[*].data[type 13]', 'person');
      return {
        'type': type,
        'giftMsg': {'giftID': gift['giftID'], 'displayUser': _user(gift['displayUser'])},
      };
    }
    final info = payload['liveinfo'];
    if (type == 38 && info is Map) {
      return {
        'type': type,
        'liveinfo': {'liveViewerCount': info['liveViewerCount']},
      };
    }
    record(r'$.messages[*].data[other]', 'dropped');
    return {'type': type};
  }

  @override
  List<int> plain(CapturedFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    final decoded = StringBuffer(text);
    try {
      final root = jsonDecode(text);
      final messages = root is Map ? root['messages'] : null;
      for (final message in messages is List ? messages : const <Object?>[]) {
        final payload = message is Map ? SeventeenliveProtocol.payload(message['data']) : null;
        if (payload != null) decoded.write('\n${jsonEncode(payload)}');
      }
    } on FormatException {
      // Not JSON: the text alone.
    }
    return utf8.encode(decoded.toString());
  }
}
