import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// One recorded frame of `fixtures/<platform>/danmaku/<case>/frames.jsonl`.
final class Frame {
  /// Parses a frames.jsonl line.
  factory fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    return Frame._(
      incoming: json['dir'] == 'in',
      millis: json['t'] as int,
      bytes: text != null ? utf8.encode(text) : base64.decode(json['b64'] as String),
      text: text,
      url: json['url'] == null ? null : Uri.parse(json['url'] as String),
    );
  }

  new _({required this.incoming, required this.millis, required this.bytes, this.text, this.url});

  /// Received (true) or sent.
  final bool incoming;

  /// Milliseconds since the recording started.
  final int millis;

  /// Frame bytes (UTF-8 of [text] for HTTP bodies).
  final List<int> bytes;

  /// HTTP body text, for polled platforms.
  final String? text;

  /// HTTP request URL, for polled platforms.
  final Uri? url;
}

/// A recorded chat capture (docs/adr/0009-fixture-format.md rule 3).
final class DanmakuFixture {
  /// Loads `fixtures/<platform>/danmaku/<name>`; tests run from the
  /// package directory.
  factory load(String platform, String name) {
    final directory = Directory('../../fixtures/$platform/danmaku/$name');
    final meta = jsonDecode(File('${directory.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
    final frames = [
      for (final line in File('${directory.path}/frames.jsonl').readAsLinesSync())
        if (line.trim().isNotEmpty) Frame.fromJson(jsonDecode(line) as Map<String, dynamic>),
    ];
    return DanmakuFixture._(meta, frames);
  }

  new _(this.meta, this.frames);

  /// meta.json.
  final Map<String, dynamic> meta;

  /// Every frame in order.
  final List<Frame> frames;

  /// Received frames.
  Iterable<Frame> get incoming => frames.where((frame) => frame.incoming);

  /// Sent frames.
  Iterable<Frame> get outgoing => frames.where((frame) => !frame.incoming);

  /// `platform:roomId`.
  String get room => meta['room'] as String;

  /// The recorded danmaku keys.
  Map<String, String> get keys => (meta['danmakuKeys'] as Map<String, dynamic>).cast<String, String>();

  /// When the capture started.
  DateTime get capturedAt => DateTime.parse(meta['capturedAt'] as String);

  /// A room detail carrying [keys].
  RoomDetail get detail {
    final ref = RoomRef.parse(room);
    return RoomDetail(
      card: RoomCard(ref: ref, title: 'fixture', anchorName: 'anchor', state: LiveState.live),
      link: Uri.parse('https://example.test/${ref.roomId}'),
      danmakuKeys: keys,
    );
  }

  /// A decode context for frame [frame].
  DecodeContext context(Frame frame, {int session = 0}) => DecodeContext(
    room: room,
    session: session,
    receivedAt: frame.millis * 1000,
    now: capturedAt.add(Duration(milliseconds: frame.millis)),
  );
}
