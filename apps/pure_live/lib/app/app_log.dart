import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// Log levels, lowest first (3.x's `Log.d/i/w/e`).
enum LogLevel {
  /// Details for debugging.
  debug,

  /// Normal events.
  info,

  /// Something went wrong but the app carries on (failed requests).
  warning,

  /// Errors (framework errors, uncaught exceptions).
  error;

  /// The stored name's level; [info] for anything else.
  static LogLevel parse(String name) => values.asNameMap()[name] ?? info;
}

/// One log line.
@immutable
final class LogEntry {
  /// Creates the entry.
  const new({required this.time, required this.level, required this.tag, required this.message});

  /// When it happened.
  final DateTime time;

  /// How serious.
  final LogLevel level;

  /// Where it came from (`flutter`, `http`, `app`...).
  final String tag;

  /// What happened, already redacted.
  final String message;

  /// `2026-10-01 12:00:00.000 [WARNING] http: ...`.
  String format() {
    final stamp = time.toIso8601String().replaceFirst('T', ' ');
    return '${stamp.length > 23 ? stamp.substring(0, 23) : stamp} [${level.name.toUpperCase()}] $tag: $message';
  }
}

/// Names whose values are secret wherever they appear: cookies, tokens,
/// passwords and signatures of the platforms (Bilibili `SESSDATA`,
/// `bili_jct`, Douyu `acf_auth`/`dy_auth`, `LTP0`, Huya `udb_biztoken`,
/// Twitch `auth-token`, OAuth `access_token`...).
const List<String> _secretNames = [
  'cookie',
  'set-cookie',
  'authorization',
  'proxy-authorization',
  'token',
  'access_token',
  'refresh_token',
  'auth-token',
  'auth_token',
  'csrf',
  'csrf_token',
  'password',
  'passwd',
  'pwd',
  'secret',
  'sessdata',
  'bili_jct',
  'dedeuserid__ckmd5',
  'acf_auth',
  'acf_stk',
  'dy_auth',
  'ltp0',
  'udb_biztoken',
  'udb_passport',
  'yyuid',
  'sessionid',
  'sessionid_ss',
  'sid_tt',
  'sid_guard',
  'uid_tt',
  'passport_csrf_token',
  'odin_tt',
  'kuaishou.server.web_st',
  'kuaishou.server.web_ph',
  'userid',
  'pairing',
  'x-purelive-pairing',
  'sign',
  'signature',
  'wts',
  'w_rid',
  'key',
  'apikey',
  'api_key',
];

final RegExp _headerLine = RegExp(
  r'^(\s*(?:cookie|set-cookie|authorization|proxy-authorization|x-purelive-pairing)\s*:\s*)(.+)$',
  caseSensitive: false,
  multiLine: true,
);

final RegExp _jsonPair = RegExp(
  '("(?:${_secretNames.map(RegExp.escape).join('|')})"\\s*:\\s*)"(?:[^"\\\\]|\\\\.)*"',
  caseSensitive: false,
);

final RegExp _namedValue = RegExp(
  '(^|[\\s;&?,{(\'"])((?:${_secretNames.map(RegExp.escape).join('|')}))(\\s*[=:]\\s*)([^\\s;&,"\'})]+)',
  caseSensitive: false,
);

final RegExp _bearer = RegExp(r'\b(Bearer|Basic|OAuth)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

final RegExp _userInfo = RegExp(r'(\b[a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@', caseSensitive: false);

/// [text] without cookies, tokens, passwords or signatures: header lines
/// (`Cookie: ...`), JSON fields (`"token": "..."`), `name=value` pairs of
/// cookies and query strings, bearer tokens and passwords in URLs become
/// `***`. The names stay so the line is still readable.
String redactSecrets(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAllMapped(_headerLine, (m) => '${m[1]}***')
      .replaceAllMapped(_jsonPair, (m) => '${m[1]}"***"')
      .replaceAllMapped(_namedValue, (m) => '${m[1]}${m[2]}${m[3]}***')
      .replaceAllMapped(_bearer, (m) => '${m[1]} ***')
      .replaceAllMapped(_userInfo, (m) => '${m[1]}***@');
}

/// The app log (3.x `Log` and `LogController`): the last [capacity] entries
/// in memory for the log page, and, while [Settings.enableLocalLog] is on, a
/// file per session in [directory]. Entries below [Settings.logLevel] are
/// dropped. Every message passes [redactSecrets] first.
///
/// [install] routes Flutter's framework errors and uncaught errors here;
/// the app's HTTP client reports failed requests (live_net `LoggingHttp`).
final class AppLog extends ChangeNotifier {
  /// Creates a log; tests make their own, the app uses [instance].
  new({this.capacity = 2000, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The app's log.
  static final AppLog instance = AppLog();

  /// Entries kept in memory (3.x `maxDebugEntries`).
  final int capacity;

  final DateTime Function() _now;
  final Queue<LogEntry> _entries = Queue();
  SettingsStore? _settings;
  final List<StreamSubscription<Object>> _watches = [];
  Directory? _directory;
  IOSink? _sink;
  File? _file;
  LogLevel _level = LogLevel.info;

  /// The entries in memory, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// The lowest level kept.
  LogLevel get level => _level;

  /// The folder of the log files; null until [attach].
  Directory? get directory => _directory;

  /// This session's file while writing.
  File? get file => _file;

  /// Whether a file is being written.
  bool get writing => _sink != null;

  /// Follows [settings] (level, file) and writes files to [directory].
  Future<void> attach(SettingsStore settings, {required Directory directory}) async {
    _settings = settings;
    _directory = directory;
    for (final watch in _watches) {
      await watch.cancel();
    }
    _watches
      ..clear()
      ..add(settings.watch(Settings.logLevel).listen((_) => _applyLevel()))
      ..add(settings.watch(Settings.enableLocalLog).listen((_) => unawaited(_applyFile())));
    _applyLevel();
    await _applyFile();
  }

  void _applyLevel() {
    final settings = _settings;
    if (settings == null) return;
    _level = LogLevel.parse(settings.get(Settings.logLevel));
    notifyListeners();
  }

  Future<void> _applyFile() async {
    final want = _settings?.get(Settings.enableLocalLog) ?? false;
    if (want == writing) return;
    if (!want) {
      final sink = _sink;
      _sink = null;
      _file = null;
      await sink?.flush();
      await sink?.close();
      notifyListeners();
      return;
    }
    final directory = _directory;
    if (directory == null) return;
    try {
      await directory.create(recursive: true);
      final stamp = _now().toIso8601String().replaceAll(':', '-').split('.').first.replaceFirst('T', '_');
      final file = File(p.join(directory.path, '$stamp.log'));
      final sink = file.openWrite(mode: FileMode.append)
        ..writeln('Pure Live log · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('Locale ${Platform.localeName}')
        ..writeln();
      for (final entry in _entries) {
        sink.writeln(entry.format());
      }
      _sink = sink;
      _file = file;
    } on Object catch (error) {
      debugPrint('Log file failed: $error');
    }
    notifyListeners();
  }

  /// Adds an entry at [level] from [tag] when the level is kept.
  void add(LogLevel level, String tag, Object? message, [Object? error, StackTrace? stack]) {
    if (level.index < _level.index) return;
    final text = StringBuffer('$message');
    if (error != null) text.write('\n$error');
    if (stack != null) text.write('\n$stack');
    final entry = LogEntry(time: _now(), level: level, tag: tag, message: redactSecrets(text.toString().trim()));
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _sink?.writeln(entry.format());
    notifyListeners();
  }

  /// [add] at [LogLevel.debug].
  void debug(String tag, Object? message) => add(LogLevel.debug, tag, message);

  /// [add] at [LogLevel.info].
  void info(String tag, Object? message) => add(LogLevel.info, tag, message);

  /// [add] at [LogLevel.warning].
  void warning(String tag, Object? message, [Object? error]) => add(LogLevel.warning, tag, message, error);

  /// [add] at [LogLevel.error].
  void error(String tag, Object? message, [Object? error, StackTrace? stack]) =>
      add(LogLevel.error, tag, message, error, stack);

  /// Empties the memory and deletes the log files (this session's file
  /// starts again empty).
  Future<void> clear() async {
    _entries.clear();
    final directory = _directory;
    final current = _file;
    if (directory != null && directory.existsSync()) {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.log') && entity.path != current?.path) {
          try {
            await entity.delete();
          } on FileSystemException {
            // In use elsewhere.
          }
        }
      }
    }
    if (current != null && _sink != null) {
      await _sink!.flush();
      await _sink!.close();
      _sink = current.openWrite();
    }
    notifyListeners();
  }

  /// The log files, newest first.
  Future<List<File>> files() async {
    final directory = _directory;
    if (directory == null || !directory.existsSync()) return const [];
    final files = [
      await for (final entity in directory.list())
        if (entity is File && entity.path.endsWith('.log')) entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Writes the entries in memory to a file in [into] for sharing; returns it.
  Future<File> export(Directory into) async {
    await into.create(recursive: true);
    final stamp = _now().toIso8601String().replaceAll(':', '-').split('.').first.replaceFirst('T', '_');
    final file = File(p.join(into.path, 'pure_live_log_$stamp.txt'));
    await file.writeAsString([for (final entry in _entries) entry.format()].join('\n'), flush: true);
    return file;
  }

  /// Flushes the file.
  Future<void> flush() async => await _sink?.flush();

  /// Routes Flutter's framework errors, uncaught errors and `debugPrint`
  /// here; each keeps its previous behaviour too (the console). Call once in
  /// `main`.
  void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      add(LogLevel.error, 'flutter', details.exceptionAsString(), details.context?.toDescription(), details.stack);
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousUncaught = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      add(LogLevel.error, 'uncaught', error.runtimeType, error, stack);
      return previousUncaught?.call(error, stack) ?? false;
    };
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) add(LogLevel.debug, 'print', message);
      previousPrint(message, wrapWidth: wrapWidth);
    };
  }

  /// Stops following the settings and closes the file.
  Future<void> close() async {
    for (final watch in _watches) {
      await watch.cancel();
    }
    _watches.clear();
    final sink = _sink;
    _sink = null;
    await sink?.flush();
    await sink?.close();
  }
}
