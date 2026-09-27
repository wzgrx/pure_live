import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_record/src/files.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

final _unsafe = RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*\s]');
final _underscores = RegExp('_+');
final _trailing = RegExp(r'[. ]+$');
final _reserved = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);

/// Cleans one path component (spec §9): control characters, `<>:"/\|?*` and
/// whitespace become `_`, runs of `_` collapse, trailing dots and spaces go,
/// at most [maxLength] characters, Windows reserved names get a leading `_`,
/// and an empty result is `unknown`. [transliterate] (pinyin folders,
/// `record.pinyinFolders`) runs first when given.
String sanitizePathComponent(String input, {int maxLength = 80, String Function(String)? transliterate}) {
  var text = transliterate == null ? input : transliterate(input);
  text = text.replaceAll(_unsafe, '_').replaceAll(_underscores, '_').replaceAll(_trailing, '');
  final runes = text.runes.toList();
  if (runes.length > maxLength) text = String.fromCharCodes(runes.take(maxLength)).replaceAll(_trailing, '');
  if (text.isEmpty || text == '_') return 'unknown';
  if (_reserved.hasMatch(text)) text = '_$text';
  return text;
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Session prefix from the local start time: `yyyyMMdd_HHmmss_SSS` (spec §9, REG-RECORD-014).
String sessionPrefix(DateTime start) {
  final t = start.toLocal();
  return '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}_'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}_${t.millisecond.toString().padLeft(3, '0')}';
}

/// Where one recording session's files go (spec §9).
@immutable
final class SessionLayout {
  /// Creates the layout of a session started at [startedAt] in [directory] with [prefix].
  const new({required this.directory, required this.prefix, required this.startedAt});

  /// `<root>/<platform>/<anchor>/<yyyy-MM-dd>/` for a session of [room]
  /// (streamer [anchorName]) started at [start] (local time).
  factory at(String root, RoomRef room, String anchorName, DateTime start, {String Function(String)? transliterate}) {
    final local = start.toLocal();
    final day = '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)}';
    final anchor = anchorName.trim().isEmpty ? room.roomId : anchorName;
    return SessionLayout(
      directory: p.join(
        root,
        sanitizePathComponent(room.platform),
        sanitizePathComponent(anchor, transliterate: transliterate),
        day,
      ),
      prefix: sessionPrefix(start),
      startedAt: start,
    );
  }

  /// Restores a persisted layout.
  factory fromJson(Map<String, Object?> json) => SessionLayout(
    directory: json['directory']! as String,
    prefix: json['prefix']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
  );

  /// Session directory.
  final String directory;

  /// File name prefix.
  final String prefix;

  /// Session start.
  final DateTime startedAt;

  /// FLV segment [index] (1-based): `<prefix>_<NNN>.flv`.
  String segment(int index, {String extension = 'flv'}) =>
      p.join(directory, '${prefix}_${index.toString().padLeft(3, '0')}.$extension');

  /// `<prefix>.gaps.json`.
  String get gaps => p.join(directory, '$prefix.gaps.json');

  /// JSON form for persistence.
  Map<String, Object?> toJson() => {
    'directory': directory,
    'prefix': prefix,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
}

/// Suffix of a file still being written; renamed away when complete.
const partSuffix = '.part';

/// Suffix of a remux output until it is committed (spec §10).
const partialSuffix = '.partial';

/// The first of [path], `<stem>-1<ext>`, `<stem>-2<ext>`… that is free, also
/// counting `<candidate>.part` as taken (spec §6.9: exclusive, never overwrite).
Future<String> uniquePath(RecordFiles files, String path) async {
  final extension = p.extension(path);
  final stem = path.substring(0, path.length - extension.length);
  for (var n = 0; ; n++) {
    final candidate = n == 0 ? path : '$stem-$n$extension';
    if (!await files.exists(candidate) &&
        !await files.exists('$candidate$partSuffix') &&
        !await files.exists('$candidate$partialSuffix')) {
      return candidate;
    }
  }
}

/// The recording root rules of spec §15.
abstract final class RecordRoot {
  /// Folder created inside a user-chosen directory.
  static const folderName = 'PureLiveRecords';

  /// Marker file inside the managed root.
  static const markerName = '.pure_live_recording_root';

  /// The directory recordings go to: [defaultRoot] (the app's `RECORDS`
  /// folder) when [chosen] is empty or an Android private path; otherwise
  /// `<chosen>/PureLiveRecords`, or [chosen] itself when it already is a
  /// marked `PureLiveRecords` folder ([isMarked]).
  static String resolve({required String defaultRoot, String? chosen, bool isMarked = false}) {
    final value = chosen?.trim() ?? '';
    if (value.isEmpty || value.startsWith('/data/user/') || value.startsWith('/data/data/')) return defaultRoot;
    if (p.basename(p.normalize(value)) == folderName && isMarked) return value;
    return p.join(value, folderName);
  }

  /// Prepares [root] (creates it and the marker) and proves it writable by
  /// writing and deleting a uniquely named probe file. Returns null when
  /// writable, else the error (classify it with `classifyFileError`).
  static Future<FileSystemException?> prepare(String root, {RecordFiles files = const IoRecordFiles()}) async {
    try {
      await files.createDirectory(root);
      final marker = p.join(root, markerName);
      if (!await files.exists(marker)) await files.writeAtomic(marker, const []);
      final probe = p.join(root, '.probe-${Random().nextInt(1 << 32).toRadixString(16)}');
      await files.writeAtomic(probe, const [1]);
      await files.delete(probe);
      return null;
    } on FileSystemException catch (error) {
      return error;
    }
  }
}
