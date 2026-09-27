import 'dart:async';
import 'dart:convert';

import 'package:live_record/src/files.dart';
import 'package:meta/meta.dart';

/// Why media is missing (spec §6.4).
enum GapReason {
  /// The upstream ended.
  eof,

  /// A connection failed.
  network,

  /// A lease renewal changed the source.
  lease,

  /// The old connection ended before the spliced successor was ready (at most one GOP).
  splice,

  /// The CDN answered 4xx.
  http4xx,

  /// The CDN answered 5xx.
  http5xx,

  /// HLS media sequence jumped.
  sequenceJump,

  /// HLS media sequence went back.
  reset,

  /// Unfinished data dropped at stop.
  stop,

  /// The app ended without finishing the session (recovered at the next start).
  crash,
}

/// One gap in a session's `gaps.json` (spec §6.4).
@immutable
final class RecordGap {
  /// Creates a gap.
  const new({
    required this.part,
    required this.atMs,
    required this.reason,
    this.wallStart,
    this.wallEnd,
    this.missingMs,
    this.source = 'flv',
    this.fromSeq,
    this.toSeq,
  });

  /// Restores a gap from `gaps.json`.
  factory fromJson(Map<String, Object?> json) => RecordGap(
    part: json['part'] as String? ?? '',
    atMs: (json['atMs'] as num?)?.toInt() ?? 0,
    reason: GapReason.values.asNameMap()[json['reason']] ?? GapReason.eof,
    wallStart: json['wallStart'] == null ? null : DateTime.parse(json['wallStart']! as String),
    wallEnd: json['wallEnd'] == null ? null : DateTime.parse(json['wallEnd']! as String),
    missingMs: (json['missingMs'] as num?)?.toInt(),
    source: json['source'] as String? ?? 'flv',
    fromSeq: (json['fromSeq'] as num?)?.toInt(),
    toSeq: (json['toSeq'] as num?)?.toInt(),
  );

  /// File name of the segment the gap is in.
  final String part;

  /// File time of the gap inside [part], in ms.
  final int atMs;

  /// Why.
  final GapReason reason;

  /// When media stopped arriving.
  final DateTime? wallStart;

  /// When media arrived again.
  final DateTime? wallEnd;

  /// Estimated missing media; null when unknown (crash).
  final int? missingMs;

  /// `flv`, `hls:video`, `hls:audio` or `ts`.
  final String source;

  /// First missing HLS sequence number.
  final int? fromSeq;

  /// Last missing HLS sequence number.
  final int? toSeq;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'part': part,
    'atMs': atMs,
    'wallStart': wallStart?.toUtc().toIso8601String(),
    'wallEnd': wallEnd?.toUtc().toIso8601String(),
    'missingMs': missingMs,
    'reason': reason.name,
    'source': source,
    'fromSeq': fromSeq,
    'toSeq': toSeq,
  };
}

/// A session's `gaps.json`: rewritten atomically after every gap and once more
/// when the session ends, so it exists (as an empty list) even without gaps.
final class GapLedger {
  /// Creates the ledger for [path] of session [session] in room [room] (`platform:roomId`).
  new({required this._files, required this.path, required this.room, required this.session});

  final RecordFiles _files;

  /// Path of the JSON file.
  final String path;

  /// Room key.
  final String room;

  /// Session prefix.
  final String session;

  final List<RecordGap> _gaps = [];
  Future<void> _writing = Future.value();

  /// Gaps so far.
  List<RecordGap> get gaps => List.unmodifiable(_gaps);

  /// Loads an existing file (crash recovery); a missing or unreadable one starts empty.
  Future<void> load() async {
    try {
      if (!await _files.exists(path)) return;
      final json = jsonDecode(utf8.decode(await _files.read(path))) as Map<String, Object?>;
      _gaps
        ..clear()
        ..addAll([
          for (final gap in json['gaps'] as List? ?? const []) RecordGap.fromJson((gap as Map).cast<String, Object?>()),
        ]);
    } on Object {
      // Damaged: keep what the session knows.
    }
  }

  /// Records [gap] and rewrites the file.
  Future<void> add(RecordGap gap) {
    _gaps.add(gap);
    return write();
  }

  /// Rewrites the file with the current gaps (writes run one at a time).
  Future<void> write() {
    final snapshot = {
      'version': 1,
      'room': room,
      'session': session,
      'gaps': [for (final gap in _gaps) gap.toJson()],
    };
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(snapshot));
    return _writing = _writing.then((_) => _files.writeAtomic(path, bytes)).catchError((Object _) {});
  }
}
