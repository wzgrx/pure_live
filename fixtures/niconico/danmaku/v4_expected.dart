// Writes fixtures/niconico/danmaku/S07-live/expected.json: what the archived
// v4 niconico comment decoder read from the recording
// (docs/modules/M5.14-niconico.md, "与归档 v4 的对照"). 3.x had no niconico
// comments (`EmptyDanmaku`), and pure_live_TV has none either, so the
// archived v4 is the only earlier implementation; it recorded this sample
// itself (`live_cli danmaku niconico lv351482215 --seconds 75 --record
// S07-live`).
//
// Below the harness, `NiconicoSegment`, `NiconicoView`, `NiconicoTimedEvent`
// and `NiconicoChatProtocol` are copied verbatim from archive/v4 (6ba709135)
// packages/live_danmaku/lib/src/sites/niconico.dart, and `ProtoField` and
// `ProtoMessage` from its lib/src/codec/protobuf.dart (the protobuf reader
// the decoder used; its writer is left out). Only what they import from
// elsewhere is stubbed: v4's event types (DanmakuChat, DanmakuOnline,
// AudienceKind) with the fields the decoder sets, and `DecodeContext`.
//
// The harness reads every recorded `view` answer with `view` and every
// recorded window with `messages`, and writes, per line of frames.jsonl, the
// windows and `next` of a view, or the timed events of a window (projected;
// times in microseconds since the epoch).
//
// Run from the repository root:
//
//   dart run fixtures/niconico/danmaku/v4_expected.dart
//
// Review the diff of expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

const _sample = 'fixtures/niconico/danmaku/S07-live';
const _generator =
    'archived v4 NiconicoChatProtocol.view and NiconicoChatProtocol.messages with its ProtoMessage '
    '(archive/v4 6ba709135) over every recorded view answer and window of S07-live '
    '(fixtures/niconico/danmaku/v4_expected.dart)';

void main() {
  final lines = [
    for (final line in File('$_sample/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = jsonDecode(File('$_sample/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final room = meta['room'] as String;
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line['dir'] != 'in') continue;
    final url = Uri.parse(line['url'] as String);
    final bytes = base64.decode(line['b64'] as String);
    if (url.path.startsWith('/api/view/')) {
      final view = NiconicoChatProtocol.view(bytes);
      frames.add({
        'line': index + 1,
        'kind': 'view',
        'at': url.queryParameters['at'],
        'segments': [for (final segment in view.segments) _window(segment)],
        'previous': [for (final segment in view.previous) _window(segment)],
        'next': view.next,
      });
    } else {
      final context = DecodeContext(room: room, session: 1, receivedAt: line['t'] as int);
      frames.add({
        'line': index + 1,
        'kind': 'window',
        'path': url.path,
        'events': [
          for (final (:at, :event) in NiconicoChatProtocol.messages(bytes, context: context))
            {'at': at.microsecondsSinceEpoch, ..._project(event)},
        ],
      });
    }
  }
  final expected = {
    'generator': _generator,
    'value': {'room': room, 'frames': frames},
  };
  File('$_sample/expected.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(expected)}\n');
  stdout.writeln('wrote $_sample/expected.json: ${frames.length} frames');
}

Map<String, Object?> _window(NiconicoSegment segment) => {
  'from': segment.from.microsecondsSinceEpoch,
  'until': segment.until.microsecondsSinceEpoch,
  'uri': '${segment.uri}',
};

Map<String, Object?> _project(DanmakuEvent event) => switch (event) {
  DanmakuChat() => {
    'type': 'chat',
    'id': event.id,
    'userId': event.userId,
    'userName': event.userName,
    'text': event.text,
    'sentAt': event.sentAt?.microsecondsSinceEpoch,
  },
  DanmakuOnline() => {'type': 'online', 'audience': event.audience.name, 'value': event.value},
};

// Stubs of what the v4 code imports ------------------------------------------

final class DecodeContext {
  const DecodeContext({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

enum AudienceKind { popularity, online, cumulative }

sealed class DanmakuEvent {
  const DanmakuEvent({required this.room, required this.session, required this.receivedAt});
  final String room;
  final int session;
  final int receivedAt;
}

final class DanmakuChat extends DanmakuEvent {
  const DanmakuChat({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    this.id,
    this.sentAt,
    this.userId = '',
  });
  final String? id;
  final DateTime? sentAt;
  final String userId;
  final String userName;
  final String text;
}

final class DanmakuOnline extends DanmakuEvent {
  const DanmakuOnline({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.audience,
    required this.value,
  });
  final AudienceKind audience;
  final int value;
}

// archive/v4 packages/live_danmaku/lib/src/codec/protobuf.dart (reader) -------

/// One protobuf field as it appeared on the wire.
@immutable
final class ProtoField {
  /// Creates a field.
  const new(this.number, this.wireType, this.value);

  /// Field number.
  final int number;

  /// Wire type: 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32.
  final int wireType;

  /// `int` for varint and fixed types, [Uint8List] for length-delimited.
  final Object value;
}

/// A protobuf message decoded without a schema: the fields in wire order
/// (docs/adr/0019-danmaku-layer.md: a hand-written reader of the few fields the
/// connectors need instead of generated classes).
@immutable
final class ProtoMessage {
  /// Wraps [fields].
  const new(this.fields);

  /// Decodes [bytes]; throws [FormatException] on truncated or group fields.
  factory decode(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final fields = <ProtoField>[];
    var offset = 0;
    int varint() {
      var result = 0;
      for (var shift = 0; shift < 64; shift += 7) {
        if (offset >= data.length) throw const FormatException('Truncated varint');
        final byte = data[offset++];
        result |= (byte & 0x7F) << shift;
        if (byte < 0x80) return result;
      }
      throw const FormatException('Varint longer than 10 bytes');
    }

    int fixed(int size) {
      if (offset + size > data.length) throw const FormatException('Truncated fixed field');
      final view = ByteData.sublistView(data, offset, offset + size);
      offset += size;
      return size == 8 ? view.getInt64(0, Endian.little) : view.getUint32(0, Endian.little);
    }

    while (offset < data.length) {
      final key = varint();
      final number = key >>> 3;
      final wireType = key & 7;
      if (number == 0) throw const FormatException('Field number 0');
      switch (wireType) {
        case 0:
          fields.add(ProtoField(number, 0, varint()));
        case 1:
          fields.add(ProtoField(number, 1, fixed(8)));
        case 2:
          final length = varint();
          if (length < 0 || offset + length > data.length) throw const FormatException('Truncated bytes field');
          fields.add(ProtoField(number, 2, Uint8List.sublistView(data, offset, offset + length)));
          offset += length;
        case 5:
          fields.add(ProtoField(number, 5, fixed(4)));
        default:
          throw FormatException('Unsupported wire type $wireType');
      }
    }
    return ProtoMessage(fields);
  }

  /// Fields in wire order.
  final List<ProtoField> fields;

  ProtoField? _last(int number) {
    for (var i = fields.length - 1; i >= 0; i--) {
      if (fields[i].number == number) return fields[i];
    }
    return null;
  }

  /// The last varint or fixed value of [number]; null when absent.
  int? integer(int number) => switch (_last(number)?.value) {
    final int value => value,
    _ => null,
  };

  /// Whether [number] is a true bool.
  bool flag(int number) => (integer(number) ?? 0) != 0;

  /// The last length-delimited value of [number].
  Uint8List? bytes(int number) => switch (_last(number)?.value) {
    final Uint8List value => value,
    _ => null,
  };

  /// The last value of [number] as UTF-8 text; malformed bytes become U+FFFD.
  String? string(int number) {
    final value = bytes(number);
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }

  /// The last value of [number] as a nested message.
  ProtoMessage? message(int number) {
    final value = bytes(number);
    return value == null ? null : ProtoMessage.decode(value);
  }

  /// Every value of a repeated [number], as nested messages.
  Iterable<ProtoMessage> messages(int number) sync* {
    for (final field in fields) {
      if (field.number == number && field.value is Uint8List) yield ProtoMessage.decode(field.value as Uint8List);
    }
  }
}

// archive/v4 packages/live_danmaku/lib/src/sites/niconico.dart (protocol) ------

/// One comment window of the message server (spec/sites/niconico.md §7).
@immutable
final class NiconicoSegment {
  /// Creates a window.
  const new({required this.from, required this.until, required this.uri});

  /// Window start.
  final DateTime from;

  /// Window end.
  final DateTime until;

  /// Where its messages are read.
  final Uri uri;
}

/// One `view` answer: the windows under way or ahead, the finished ones,
/// and when to ask next.
typedef NiconicoView = ({List<NiconicoSegment> segments, List<NiconicoSegment> previous, int? next});

/// One decoded message of a window, with its time.
typedef NiconicoTimedEvent = ({DateTime at, DanmakuEvent event});

/// niconico's comment server ("NDGR", spec/sites/niconico.md §7), without
/// I/O: length-delimited protobuf entries from `view`, length-delimited
/// messages from each window.
abstract final class NiconicoChatProtocol {
  /// Splits varint-length-delimited protobuf messages.
  static List<Uint8List> delimited(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final out = <Uint8List>[];
    var offset = 0;
    while (offset < data.length) {
      var length = 0;
      var shift = 0;
      while (true) {
        if (offset >= data.length || shift > 63) throw const FormatException('Truncated length prefix');
        final byte = data[offset++];
        length |= (byte & 0x7F) << shift;
        if (byte < 0x80) break;
        shift += 7;
      }
      if (offset + length > data.length) throw const FormatException('Truncated message');
      out.add(Uint8List.sublistView(data, offset, offset + length));
      offset += length;
    }
    return out;
  }

  static DateTime? _time(ProtoMessage? timestamp) {
    final seconds = timestamp?.integer(1);
    if (seconds == null) return null;
    final nanos = timestamp?.integer(2) ?? 0;
    return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanos ~/ 1000, isUtc: true);
  }

  static NiconicoSegment? _segment(ProtoMessage? segment) {
    final from = _time(segment?.message(1));
    final until = _time(segment?.message(2));
    final uri = Uri.tryParse(segment?.string(3) ?? '');
    if (from == null || until == null || uri == null || !uri.hasScheme) return null;
    return NiconicoSegment(from: from, until: until, uri: uri);
  }

  /// §7 a `view` answer: entry 1 a window under way or ahead, 3 a finished
  /// window, 4 `next{at}`; 2 (backward and snapshot links) is not used.
  static NiconicoView view(List<int> bytes) {
    final segments = <NiconicoSegment>[];
    final previous = <NiconicoSegment>[];
    int? next;
    for (final entry in delimited(bytes)) {
      final message = ProtoMessage.decode(entry);
      if (_segment(message.message(1)) case final NiconicoSegment segment) segments.add(segment);
      if (_segment(message.message(3)) case final NiconicoSegment segment) previous.add(segment);
      next = message.message(4)?.integer(1) ?? next;
    }
    return (segments: segments, previous: previous, next: next);
  }

  /// §7 a window's messages: `message.chat` becomes a chat line,
  /// `state.statistics.viewers` the online figure; everything else
  /// (notifications, gifts, ads, signals) is left out.
  static List<NiconicoTimedEvent> messages(List<int> bytes, {required DecodeContext context}) {
    final out = <NiconicoTimedEvent>[];
    for (final chunk in delimited(bytes)) {
      final message = ProtoMessage.decode(chunk);
      final meta = message.message(1);
      final at = _time(meta?.message(2));
      if (at == null) continue;
      final chat = message.message(2)?.message(1);
      if (chat != null) {
        final text = (chat.string(1) ?? '').trim();
        if (text.isEmpty) continue;
        final id = meta?.string(1);
        final raw = chat.integer(5);
        out.add((
          at: at,
          event: DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null || id.isEmpty ? null : 'niconico:$id',
            sentAt: at,
            userId: chat.string(6) ?? (raw == null ? '' : '$raw'),
            userName: (chat.string(2) ?? '').trim(),
            text: text,
          ),
        ));
        continue;
      }
      final viewers = message.message(4)?.message(1)?.integer(1);
      if (viewers != null && viewers >= 0) {
        out.add((
          at: at,
          event: DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
        ));
      }
    }
    return out;
  }
}
