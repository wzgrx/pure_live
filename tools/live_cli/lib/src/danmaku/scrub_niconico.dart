import 'dart:convert';
import 'dart:typed_data';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// niconico chat (spec/sites/niconico.md §7, §11). The watch page (it
/// carries this client's audience token) is dropped; the comment server's
/// path tokens (`/api/view/v4/…`, `/data/{segment,backward,snapshot}/v4/…`)
/// are replaced with same-shape values, in URLs and inside the protobuf
/// answers (same length, so the length prefixes stay valid); chat authors
/// (`name`, `raw_user_id`, `hashed_user_id`) are replaced by rebuilding
/// the messages. Comment text stays.
class NiconicoFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static final RegExp _token = RegExp('/(?:api/view|data/segment|data/backward|data/snapshot)/v4/([A-Za-z0-9_-]+)');

  String _tokens(String text) => text.replaceAllMapped(_token, (match) {
    final token = match.group(1)!;
    record('comment server path token', 'secret');
    return match.group(0)!.replaceFirst(token, names.secret(token));
  });

  @override
  Uri scrubUrl(Uri url) => Uri.parse(_tokens(url.toString()));

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final url = frame.url;
    if (url == null) return frame.bytes;
    if (url.host == 'live.nicovideo.jp' && url.path.startsWith('/watch/')) {
      record('watch page', 'dropped');
      return null;
    }
    if (url.path.startsWith('/data/segment/')) return _messages(frame.bytes);
    // View answers: segment links inside the protobuf entries.
    return latin1.encode(_tokens(latin1.decode(frame.bytes)));
  }

  List<int> _messages(List<int> bytes) {
    final out = BytesBuilder(copy: false);
    for (final chunk in NiconicoChatProtocol.delimited(bytes)) {
      final rebuilt = _chunk(ProtoMessage.decode(chunk));
      var length = rebuilt.length;
      while (length >= 0x80) {
        out.addByte(length & 0x7F | 0x80);
        length >>>= 7;
      }
      out
        ..addByte(length)
        ..add(rebuilt);
    }
    return out.takeBytes();
  }

  Uint8List _chunk(ProtoMessage chunk) {
    final writer = ProtoWriter();
    for (final field in chunk.fields) {
      if (field.number == 2 && field.value is Uint8List) {
        writer.bytes(2, _message(ProtoMessage.decode(field.value as Uint8List)));
      } else {
        writer.field(field);
      }
    }
    return writer.toBytes();
  }

  Uint8List _message(ProtoMessage message) {
    final writer = ProtoWriter();
    for (final field in message.fields) {
      if (field.number == 1 && field.value is Uint8List) {
        writer.bytes(1, _chat(ProtoMessage.decode(field.value as Uint8List)));
      } else {
        writer.field(field);
      }
    }
    return writer.toBytes();
  }

  Uint8List _chat(ProtoMessage chat) {
    final writer = ProtoWriter();
    for (final field in chat.fields) {
      switch ((field.number, field.value)) {
        case (2, final Uint8List name) when name.isNotEmpty:
          writer.string(2, names.person(utf8.decode(name, allowMalformed: true)));
          record('message.chat.name', 'person');
        case (5, final int id):
          writer.integer(5, int.parse(names.digits('$id')));
          record('message.chat.raw_user_id', 'person');
        case (6, final Uint8List hashed) when hashed.isNotEmpty:
          writer.string(6, names.secret(utf8.decode(hashed, allowMalformed: true)));
          record('message.chat.hashed_user_id', 'person');
        default:
          writer.field(field);
      }
    }
    return writer.toBytes();
  }
}
