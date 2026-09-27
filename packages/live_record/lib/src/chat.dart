import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/naming.dart';
import 'package:meta/meta.dart';

/// One ordinary chat message to record (spec §17). The app converts
/// `live_danmaku` messages into this; gifts, entries and system notices are
/// not recorded.
@immutable
final class RecordChatMessage {
  /// Creates a message.
  const new({required this.text, this.id, this.userId, this.userName = '', this.color, this.sentAt, this.receivedAt});

  /// Platform message id for de-duplication, when there is one.
  final String? id;

  /// Sender id, for the stable user hash.
  final String? userId;

  /// Sender name.
  final String userName;

  /// Text.
  final String text;

  /// RGB colour (0xRRGGBB); white when null.
  final int? color;

  /// When the platform says it was sent.
  final DateTime? sentAt;

  /// When it arrived; the session stamps it when null.
  final DateTime? receivedAt;
}

/// Supplies a room's chat while it is recorded. The app implements it with
/// `live_danmaku` (connect with `RoomDetail.danmakuKeys`, map chat messages to
/// [RecordChatMessage]). The stream ending or failing is retried after 30 s
/// while the session runs; chat never affects the video (spec §17).
abstract interface class RecordChatSource {
  /// Connects to [room]'s chat.
  Stream<RecordChatMessage> connect(RoomDetail room);
}

/// CRC-32 (IEEE) of [bytes], for the stable user hash of the XML (spec §17).
int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return crc ^ 0xffffffff;
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

bool _allowed(int rune) =>
    rune == 0x9 ||
    rune == 0xA ||
    rune == 0xD ||
    (rune >= 0x20 && rune <= 0xD7FF) ||
    (rune >= 0xE000 && rune <= 0xFFFD) ||
    (rune >= 0x10000 && rune <= 0x10FFFF);

/// Escapes [text] for XML 1.0 and drops characters XML 1.0 does not allow.
String xmlEscape(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (!_allowed(rune)) continue;
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3C:
        buffer.write('&lt;');
      case 0x3E:
        buffer.write('&gt;');
      case 0x22:
        buffer.write('&quot;');
      case 0x27:
        buffer.write('&apos;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// The XML head of a chat file.
const chatXmlHead = '<?xml version="1.0" encoding="UTF-8"?>\n<i>\n<chatserver>pure_live</chatserver>\n';

/// The XML tail of a chat file.
const chatXmlTail = '</i>\n';

/// Formats one `<d>` line of the Bilibili chat XML (DanmakuFactory, PotPlayer,
/// biliup and blrec read it), or null for an empty text.
String? chatXmlLine(RecordChatMessage message, {required int fileTimeMs, required DateTime receivedAt}) {
  final text = xmlEscape(message.text.trim());
  if (text.isEmpty) return null;
  final seconds = '${fileTimeMs ~/ 1000}.${(fileTimeMs % 1000).toString().padLeft(3, '0')}';
  final color = (message.color ?? 0xffffff) & 0xffffff;
  final unix = (message.sentAt ?? receivedAt).millisecondsSinceEpoch ~/ 1000;
  final identity = message.userId ?? message.userName;
  final hash = crc32(utf8.encode(identity)).toRadixString(16);
  return '<d p="$seconds,1,25,$color,$unix,0,$hash,0" user="${xmlEscape(message.userName)}">$text</d>\n';
}

/// Writes the chat of one session as one XML per segment (spec §17).
final class ChatXmlWriter {
  /// Creates a writer; `fileTime` maps a wall time to the current segment's file time.
  new(this._files, this._fileTime);

  final RecordFiles _files;
  final int? Function(DateTime wall) _fileTime;
  final _seen = <String>{};
  RecordSink? _sink;
  String? _path;
  Future<void> _chain = Future.value();

  /// Messages written.
  int written = 0;

  /// Opens the XML of the segment planned at [segmentPath] (`.flv` → `.xml`),
  /// closing the previous one.
  Future<void> openFor(String segmentPath) {
    final path = '${segmentPath.substring(0, segmentPath.lastIndexOf('.'))}.xml';
    return _enqueue(() async {
      await _closeCurrent();
      final target = await uniquePath(_files, path);
      final sink = await _files.create('$target$partSuffix');
      await sink.write(utf8.encode(chatXmlHead));
      _sink = sink;
      _path = target;
    });
  }

  /// Appends [message] at the current file time; duplicates (same id among
  /// the last 2048) and empty texts are skipped.
  void add(RecordChatMessage message) {
    final id = message.id;
    if (id != null) {
      if (!_seen.add(id)) return;
      if (_seen.length > 2048) _seen.remove(_seen.first);
    }
    final receivedAt = message.receivedAt ?? clock.now();
    final fileTime = _fileTime(receivedAt);
    if (fileTime == null) return;
    final line = chatXmlLine(message, fileTimeMs: fileTime, receivedAt: receivedAt);
    if (line == null) return;
    unawaited(
      _enqueue(() async {
        final sink = _sink;
        if (sink == null) return;
        await sink.write(utf8.encode(line));
        written++;
      }),
    );
  }

  /// Closes the current XML (writes `</i>`, waits for the real close, renames).
  Future<void> close() => _enqueue(_closeCurrent);

  Future<void> _closeCurrent() async {
    final sink = _sink;
    final path = _path;
    _sink = null;
    _path = null;
    if (sink == null || path == null) return;
    await sink.write(utf8.encode(chatXmlTail));
    await sink.flush();
    await sink.close();
    await _files.rename('$path$partSuffix', path);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    // Chat failures never affect the recording.
    return _chain = _chain.then((_) => action()).catchError((Object _) {});
  }
}
