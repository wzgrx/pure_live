import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/src/task.dart';
import 'package:path/path.dart' as p;

/// A live chat connection opened for one recording task (3.x
/// `RecordingDanmakuConnection`).
final class RecordChatConnection {
  /// Creates the connection; [stop] releases it.
  const new({required this.stop});

  /// Closes the connection; nothing is delivered afterwards.
  final Future<void> Function() stop;
}

/// Opens the chat of [task]'s room. Delivers chat messages to `onMessage`,
/// already filtered (duplicates, the user's block lists), and calls
/// `onEnded` when the connection gave up for good. Returns null when the
/// platform has no chat. The app implements it over live_danmaku, which
/// live_record cannot depend on.
typedef RecordChatConnector = Future<RecordChatConnection?> Function(
  RecordTask task, {
  required void Function(LiveMessage message) onMessage,
  required void Function() onEnded,
});

/// Writes one recording attempt's chat as a Bilibili danmaku XML file
/// (`<d p="time,mode,size,color,unix,pool,user,row">text</d>`), which
/// DanmakuFactory, PotPlayer and the biliup/blrec tools read (3.x
/// `RecordingDanmakuWriter`).
///
/// Unlike 3.x the file is a complete document after every [flush]: the
/// closing `</i>` is rewritten after the new entries, so a killed process
/// leaves a readable file instead of an unterminated one.
final class RecordChatWriter {
  new _(this.file, this._file, this.startedAt, this._end);

  /// Creates [file] and writes the header; times are seconds from
  /// [startedAt].
  static Future<RecordChatWriter> open(File file, {required DateTime startedAt}) async {
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeFrom(utf8.encode('$_header$_closing'));
      return RecordChatWriter._(file, handle, startedAt, _header.length);
    } on Object {
      await handle.close();
      rethrow;
    }
  }

  static const _header = '<?xml version="1.0" encoding="UTF-8"?>\n<i>\n<chatserver>pure_live</chatserver>\n';
  static const _closing = '</i>\n';

  /// The file.
  final File file;

  /// Time base: the start of the attempt's video.
  final DateTime startedAt;

  final RandomAccessFile _file;
  final _pending = StringBuffer();
  int _end;
  var _count = 0;
  var _closed = false;
  Future<void>? _writing;

  /// Entries added.
  int get count => _count;

  /// Adds [message] received at [receivedAt]; written at the next [flush].
  void add(LiveMessage message, {required DateTime receivedAt}) {
    if (_closed) return;
    final text = escape(message.message);
    if (text.isEmpty) return;
    final offset = receivedAt.difference(startedAt).inMilliseconds / 1000.0;
    final seconds = offset < 0 ? 0.0 : offset;
    final color = (message.color.r << 16) | (message.color.g << 8) | message.color.b;
    final user = (message.userId.isNotEmpty ? message.userId : message.userName).hashCode.toUnsigned(32);
    final unix = (message.sentAt ?? receivedAt).millisecondsSinceEpoch ~/ 1000;
    _pending.write(
      '<d p="${seconds.toStringAsFixed(3)},1,25,$color,$unix,0,${user.toRadixString(16)},0" '
      'user="${escape(message.userName)}">$text</d>\n',
    );
    _count++;
  }

  /// Writes the pending entries followed by the closing tag.
  Future<void> flush() async {
    while (_writing != null) {
      await _writing;
    }
    if (_pending.isEmpty) return;
    final bytes = utf8.encode('$_pending');
    _pending.clear();
    final write = () async {
      await _file.setPosition(_end);
      await _file.writeFrom(bytes);
      _end += bytes.length;
      await _file.writeFrom(utf8.encode(_closing));
      await _file.flush();
    }();
    _writing = write;
    try {
      await write;
    } finally {
      _writing = null;
    }
  }

  /// Flushes and closes the file.
  Future<void> close() async {
    if (_closed) return;
    try {
      await flush();
    } finally {
      _closed = true;
      await _file.close();
    }
  }

  /// XML-escapes [value] and drops characters XML 1.0 cannot carry.
  static String escape(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final allowed =
          rune == 0x9 ||
          rune == 0xA ||
          rune == 0xD ||
          (rune >= 0x20 && rune <= 0xD7FF) ||
          (rune >= 0xE000 && rune <= 0xFFFD) ||
          rune >= 0x10000;
      if (!allowed) continue;
      buffer.write(switch (rune) {
        0x26 => '&amp;',
        0x3C => '&lt;',
        0x3E => '&gt;',
        0x22 => '&quot;',
        0x27 => '&apos;',
        _ => String.fromCharCode(rune),
      });
    }
    return buffer.toString().trim();
  }
}

final class _TaskChat {
  RecordChatConnection? connection;
  bool connecting = false;
  DateTime? failedAt;
  RecordChatWriter? writer;
  Future<RecordChatWriter?>? opening;
  String? writerKey;
  bool released = false;
}

/// Saves the live chat beside each recorded attempt when the user asked for
/// it (3.x `RecordingDanmakuService`, the "record danmaku" setting).
///
/// It only observes task snapshots ([sync] with `Recorder.changes`), never
/// takes part in stream selection, FFmpeg or joining, so a chat failure
/// cannot touch the video. A task that is preparing, running or
/// reconnecting keeps one chat connection (across its attempts); each
/// attempt's chat goes to `<prefix>.xml` beside the attempt's
/// `<prefix>.mp4`, timed from the moment the attempt's video started (3.x
/// timed from before the stream was resolved, a few seconds early). A
/// reconnect gap has no video, so its chat is not written. A connection
/// that fails or ends is tried again after [retryDelay].
final class RecordChatRecorder {
  /// Creates the recorder; [enabled] reads the setting.
  new({
    required this.enabled,
    required this.connect,
    this.retryDelay = const Duration(seconds: 30),
    this.flushInterval = const Duration(seconds: 2),
  }) {
    _flushTimer = Timer.periodic(flushInterval, (_) => unawaited(_flushAll()));
  }

  /// Whether chat is recorded.
  final bool Function() enabled;

  /// Opens a task's chat.
  final RecordChatConnector connect;

  /// Wait before connecting again after a failure.
  final Duration retryDelay;

  /// How often written entries reach the file.
  final Duration flushInterval;

  final _tasks = <String, _TaskChat>{};
  late final Timer _flushTimer;
  var _disposed = false;

  static const Set<RecordStatus> _connected = {RecordStatus.preparing, RecordStatus.running, RecordStatus.reconnecting};

  /// The chat file of [taskId]'s current attempt (tests, diagnostics).
  File? fileOf(String taskId) => _tasks[taskId]?.writer?.file;

  /// Follows [tasks] (the recorder's list after a change, or after the
  /// setting changed).
  void sync(Iterable<RecordTask> tasks) {
    if (_disposed) return;
    final seen = <String>{};
    final wanted = enabled();
    for (final task in tasks) {
      seen.add(task.taskId);
      if (!wanted || !_connected.contains(task.status)) {
        unawaited(_release(task.taskId));
        continue;
      }
      final state = _tasks.putIfAbsent(task.taskId, _TaskChat.new);
      _ensureConnection(task, state);
      _syncWriter(task, state);
    }
    for (final taskId in _tasks.keys.where((id) => !seen.contains(id)).toList()) {
      unawaited(_release(taskId));
    }
  }

  void _ensureConnection(RecordTask task, _TaskChat state) {
    if (state.connection != null || state.connecting) return;
    final failedAt = state.failedAt;
    if (failedAt != null && clock.now().difference(failedAt) < retryDelay) return;
    state.connecting = true;
    unawaited(() async {
      RecordChatConnection? connection;
      try {
        connection = await connect(
          task,
          onMessage: (message) => _onMessage(state, message),
          onEnded: () {
            if (state.released) return;
            final ended = state.connection;
            state
              ..connection = null
              ..failedAt = clock.now();
            if (ended != null) unawaited(ended.stop().catchError((Object _) {}));
          },
        );
      } on Object {
        connection = null;
      }
      state.connecting = false;
      if (state.released || _disposed) {
        await connection?.stop().catchError((Object _) {});
        return;
      }
      if (connection == null) {
        state.failedAt = clock.now();
      } else {
        state.connection = connection;
      }
    }());
  }

  void _syncWriter(RecordTask task, _TaskChat state) {
    final directory = task.outputDir?.trim() ?? '';
    if (task.status != RecordStatus.running || directory.isEmpty) {
      // Preparing or reconnecting: the previous attempt's video has ended.
      unawaited(_closeWriter(state));
      return;
    }
    final prefix = task.recordingFilePrefix;
    final key = '$directory\u0000$prefix';
    if (state.writerKey == key) return;
    unawaited(_closeWriter(state));
    state.writerKey = key;
    final opening = RecordChatWriter.open(
      File(p.join(directory, '$prefix.xml')),
      startedAt: clock.now(),
    ).then<RecordChatWriter?>((writer) => writer, onError: (Object _) => null);
    state.opening = opening;
    unawaited(
      opening.then((writer) async {
        if (!identical(state.opening, opening)) return;
        state.opening = null;
        if (writer == null) return; // A failing path is not retried for this attempt.
        if (state.released || state.writerKey != key) {
          await writer.close().catchError((Object _) {});
          return;
        }
        state.writer = writer;
      }),
    );
  }

  void _onMessage(_TaskChat state, LiveMessage message) {
    final writer = state.writer;
    if (state.released || writer == null || message.type != LiveMessageType.chat) return;
    try {
      writer.add(message, receivedAt: clock.now());
    } on Object {
      // A failing chat file never affects the recording.
    }
  }

  Future<void> _flushAll() async {
    for (final state in _tasks.values.toList()) {
      await state.writer?.flush().catchError((Object _) {});
    }
  }

  Future<void> _closeWriter(_TaskChat state) async {
    final opening = state.opening;
    state
      ..opening = null
      ..writerKey = null;
    final writer = state.writer ?? await opening;
    state.writer = null;
    await writer?.close().catchError((Object _) {});
  }

  Future<void> _release(String taskId) async {
    final state = _tasks.remove(taskId);
    if (state == null) return;
    state.released = true;
    // Awaited so dispose returns with the file closed (Windows keeps open
    // files locked).
    await _closeWriter(state);
    final connection = state.connection;
    state.connection = null;
    await connection?.stop().catchError((Object _) {});
  }

  /// Closes every file and connection.
  Future<void> dispose() async {
    _disposed = true;
    _flushTimer.cancel();
    await Future.wait(_tasks.keys.toList().map(_release));
  }
}
