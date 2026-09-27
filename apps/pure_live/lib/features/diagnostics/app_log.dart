import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pure_live_app/features/diagnostics/log_scrubber.dart';

/// Severity of a log line.
enum LogLevel {
  info('I'),
  warning('W'),
  error('E');

  new(this.letter);

  /// One-letter tag in the file.
  final String letter;
}

/// The local rolling log (F-BAK-02, PLAN §12): `app.log` plus at most
/// [keepFiles] - 1 older files, each up to [maxFileBytes], so the log never
/// grows past `maxFileBytes * keepFiles`. Every line passes [LogScrubber]
/// first, so cookies and tokens never reach the disk. Nothing is sent
/// anywhere; the user can export the log in a diagnostics bundle.
///
/// Logging never throws: a full disk or a missing directory only loses lines.
final class AppLog {
  new _(this.directory, {required this.maxFileBytes, required this.keepFiles, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// A log kept only in memory (tests, and before main() opens the file).
  factory memory({DateTime Function()? clock}) => AppLog._(null, maxFileBytes: 0, keepFiles: 1, clock: clock);

  /// Opens the log in [directory], creating it when needed.
  static Future<AppLog> open(
    Directory directory, {
    int maxFileBytes = 256 * 1024,
    int keepFiles = 3,
    DateTime Function()? clock,
  }) async {
    final log = AppLog._(directory, maxFileBytes: maxFileBytes, keepFiles: keepFiles, clock: clock);
    try {
      await directory.create(recursive: true);
      final file = log.file;
      if (file != null && file.existsSync()) log._size = file.lengthSync();
    } on FileSystemException {
      // Keeps logging to memory.
    }
    return log;
  }

  /// The app-wide log; main() replaces the in-memory one with the file log.
  static AppLog current = AppLog.memory();

  /// Where the files are; null for an in-memory log.
  final Directory? directory;

  /// Size limit of one file in bytes.
  final int maxFileBytes;

  /// Number of files kept, the current one included.
  final int keepFiles;

  final DateTime Function() _clock;
  final ListQueue<String> _recent = ListQueue();
  int _size = 0;

  /// Lines kept in memory for the diagnostics page.
  static const recentLimit = 500;

  static const _stackLines = 40;

  /// The current file, or null for an in-memory log.
  File? get file => directory == null ? null : _fileAt(0);

  File _fileAt(int index) =>
      File('${directory!.path}${Platform.pathSeparator}${index == 0 ? 'app.log' : 'app.$index.log'}');

  /// The last lines written in this run, oldest first.
  List<String> get recent => List.unmodifiable(_recent);

  /// Records an event.
  void info(String tag, String message) => write(LogLevel.info, tag, message);

  /// Records a recoverable problem.
  void warning(String tag, String message, [Object? error]) => write(LogLevel.warning, tag, message, error);

  /// Records a failure with its [error] and [stack].
  void error(String tag, String message, [Object? error, StackTrace? stack]) =>
      write(LogLevel.error, tag, message, error, stack);

  /// Writes one entry.
  void write(LogLevel level, String tag, String message, [Object? error, StackTrace? stack]) {
    final text = StringBuffer()
      ..write(_clock().toUtc().toIso8601String())
      ..write(' ')
      ..write(level.letter)
      ..write(' ')
      ..write(tag)
      ..write(': ')
      ..write(message);
    if (error != null) text.write(' | $error');
    if (stack != null) {
      final lines = stack.toString().trimRight().split('\n');
      for (final line in lines.take(_stackLines)) {
        text.write('\n    ${line.trim()}');
      }
      if (lines.length > _stackLines) text.write('\n    … ${lines.length - _stackLines} more frames');
    }
    final entry = LogScrubber.scrub(text.toString());
    for (final line in entry.split('\n')) {
      _recent.addLast(line);
      if (_recent.length > recentLimit) _recent.removeFirst();
    }
    if (kDebugMode && level != LogLevel.info) debugPrint(entry);
    _append('$entry\n');
  }

  void _append(String text) {
    if (directory == null) return;
    try {
      final bytes = utf8.encode(text);
      if (_size > 0 && _size + bytes.length > maxFileBytes) _rotate();
      _fileAt(0).writeAsBytesSync(bytes, mode: FileMode.append);
      _size += bytes.length;
    } on FileSystemException {
      // Losing a line is better than failing the caller.
    }
  }

  void _rotate() {
    for (var index = keepFiles - 1; index >= 1; index--) {
      final older = _fileAt(index);
      final newer = _fileAt(index - 1);
      if (index == keepFiles - 1 && older.existsSync()) older.deleteSync();
      if (newer.existsSync()) newer.renameSync(older.path);
    }
    if (keepFiles <= 1 && _fileAt(0).existsSync()) _fileAt(0).deleteSync();
    _size = 0;
  }

  /// Every stored line, oldest first; the in-memory lines for a memory log.
  Future<List<String>> readAll() async {
    if (directory == null) return recent;
    final lines = <String>[];
    for (var index = keepFiles - 1; index >= 0; index--) {
      final file = _fileAt(index);
      try {
        if (file.existsSync()) {
          lines.addAll(const LineSplitter().convert(utf8.decode(await file.readAsBytes(), allowMalformed: true)));
        }
      } on FileSystemException {
        // Skips a file that vanished or is locked.
      }
    }
    return lines;
  }

  /// Deletes every log file and the in-memory lines.
  Future<void> clear() async {
    _recent.clear();
    _size = 0;
    if (directory == null) return;
    for (var index = 0; index < keepFiles; index++) {
      try {
        final file = _fileAt(index);
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // Removed on the next rotation.
      }
    }
  }
}
