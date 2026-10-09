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
/// already filtered (duplicates, the user's block lists), and the gifts
/// (filtered the same way) and super chats when the user records them
/// ("录制弹幕时包含礼物", H01.8; [RecordChatWriter] writes them), and calls
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
///
/// Gifts and super chats (H01.8, "录制弹幕时包含礼物"; the app delivers them
/// only when the user records them) are written the way BililiveRecorder
/// writes them and DanmakuFactory reads them, in the same file and on the
/// same time base as the `<d>` entries
/// (docs/H-录制/H01-录制核心/H01.8-弹幕XML带礼物/README.md):
///
/// - `<gift ts="…" user="…" giftname="…" giftcount="…" price="…" value="…" unit="…" />`:
///   one entry per combo, not per packet, by the chat list's combo rules
///   (`giftComboKey` and the rest, D07.1). It is written once no gift
///   counted on it for [comboWindow], timed at its first gift, with the
///   combo's count. A combo still going after [maxComboSpan] is written so
///   far and goes on in a new entry with the rest. A platform's summary of
///   a combo (Bilibili's `COMBO_SEND`) within [summaryWindow] of its last
///   gift adds only what the combo had not counted. `price` is the value
///   in thousandths of a yuan (厘, Bilibili's gold seeds: what blrec writes
///   and DanmakuFactory's `--giftminprice` compares) for the units whose
///   rate in yuan is fixed ([recordYuanUnits]), `0` for a free gift, and
///   left out otherwise; `value` and `unit` keep the platform's own number
///   and unit (the `LiveGiftUnit` name). Blanks in the gift's name become
///   no-break spaces: DanmakuFactory ends `giftname` at a blank.
/// - `<sc ts="…" user="…" price="…" time="…">text</sc>`: `time` is how many
///   seconds the platform shows it; `price` is in thousandths of a yuan on
///   the platforms whose super chat price is in yuan
///   ([recordYuanSuperChats]), elsewhere the platform's number is kept as
///   `value` (and its own text as `pricetext`, blanks again no-break
///   spaces). A replayed super chat (a
///   board shown on joining) happened before the recording and is left
///   out; the same one twice is written once.
///
/// While a combo is open the entries after its first gift are held back,
/// so the file stays in time order; with no gift and no super chat (the
/// setting off) every entry is written at the next [flush] exactly as
/// before.
final class RecordChatWriter {
  new _(this.file, this._file, this.startedAt, this._end, this.platform);

  /// Creates [file] and writes the header; times are seconds from
  /// [startedAt]. [platform] (the task's site id) tells how its super chats
  /// are priced.
  static Future<RecordChatWriter> open(File file, {required DateTime startedAt, String platform = ''}) async {
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeFrom(utf8.encode('$_header$_closing'));
      return RecordChatWriter._(file, handle, startedAt, _header.length, platform);
    } on Object {
      await handle.close();
      rethrow;
    }
  }

  static const _header = '<?xml version="1.0" encoding="UTF-8"?>\n<i>\n<chatserver>pure_live</chatserver>\n';
  static const _closing = '</i>\n';

  /// How long after a combo's last gift the next one still counts on it
  /// (the chat list's `GiftCombiner.comboWindow`, V03.5 §6.4).
  static const Duration comboWindow = Duration(seconds: 5);

  /// How long after a combo's last gift the platform's summary of it still
  /// counts on it (`GiftCombiner.summaryWindow`, D07.4: Bilibili's
  /// `COMBO_SEND` comes about 5 s after the last send).
  static const Duration summaryWindow = Duration(seconds: 15);

  /// The longest a combo's part is held before it is written, so a fan
  /// sending without a break for minutes holds back the chat behind it (and
  /// risks it with a killed process) for no longer than this.
  static const Duration maxComboSpan = Duration(seconds: 30);

  /// Combos remembered; beyond it the oldest is written and forgotten.
  static const int maxCombos = 256;

  static const int _maxSuperChats = 256;

  static final _blank = RegExp('[ \t\r\n]');

  /// The file.
  final File file;

  /// Time base: the start of the attempt's video.
  final DateTime startedAt;

  /// The task's site id.
  final String platform;

  final RandomAccessFile _file;
  final _pending = StringBuffer();
  final _combos = <String, _GiftCombo>{}; // Insertion ordered: the oldest goes first.
  final _held = <_HeldEntry>[];
  final _superChats = <LiveSuperChatMessage>{};
  int _end;
  var _count = 0;
  var _paidCount = 0;
  var _sequence = 0;
  var _closed = false;
  Future<void>? _writing;

  /// Chat entries added.
  int get count => _count;

  /// Gift entries (a combo counts once) and super chats added.
  int get paidCount => _paidCount;

  /// Adds [message] received at [receivedAt]; written at the next [flush],
  /// a gift once its combo is over.
  void add(LiveMessage message, {required DateTime receivedAt}) {
    if (_closed) return;
    switch (message.type) {
      case LiveMessageType.gift:
        _addGift(message, receivedAt);
      case LiveMessageType.superChat:
        _addSuperChat(message, receivedAt);
      case _:
        _addChat(message, receivedAt);
    }
  }

  void _addChat(LiveMessage message, DateTime receivedAt) {
    final text = escape(message.message);
    if (text.isEmpty) return;
    final offset = receivedAt.difference(startedAt).inMilliseconds / 1000.0;
    final seconds = offset < 0 ? 0.0 : offset;
    final color = (message.color.r << 16) | (message.color.g << 8) | message.color.b;
    final user = (message.userId.isNotEmpty ? message.userId : message.userName).hashCode.toUnsigned(32);
    final unix = (message.sentAt ?? receivedAt).millisecondsSinceEpoch ~/ 1000;
    _entry(
      _offsetMs(receivedAt),
      '<d p="${seconds.toStringAsFixed(3)},1,25,$color,$unix,0,${user.toRadixString(16)},0" '
      'user="${escape(message.userName)}">$text</d>\n',
    );
    _count++;
  }

  void _addGift(LiveMessage message, DateTime receivedAt) {
    final gift = message.gift;
    if (gift == null) return; // Not a platform's gift (local gifts, old engines).
    final key = giftComboKey(message, gift);
    final at = _offsetMs(receivedAt);
    final combo = _combos.remove(key);
    if (combo != null) {
      final idle = receivedAt.difference(combo.lastAt);
      // As the chat list's GiftCombiner: the platform's summary counts on
      // its combo, even one written already, for only what it had not
      // counted; a count that went back is a new combo.
      final near = giftIsComboSummary(gift) ? idle <= summaryWindow : !combo.ended && idle <= comboWindow;
      if (near && !giftComboRestarted(combo.running, gift)) {
        combo.count(message, gift, receivedAt, at, giftComboTotal(combo.total, gift));
        _combos[key] = combo;
        return;
      }
      _writeCombo(combo);
    }
    _combos[key] = _GiftCombo(message, gift, at: receivedAt, startMs: at, total: giftComboStart(gift));
    _paidCount++;
    if (_combos.length > maxCombos) _writeCombo(_combos.remove(_combos.keys.first)!);
  }

  void _addSuperChat(LiveMessage message, DateTime receivedAt) {
    final superChat = message.data;
    if (superChat is! LiveSuperChatMessage || message.replayed || !_superChats.add(superChat)) return;
    if (_superChats.length > _maxSuperChats) _superChats.remove(_superChats.first);
    final at = _offsetMs(receivedAt);
    final shown = superChat.endTime.difference(superChat.startTime).inSeconds;
    final price = superChat.price;
    final inYuan = price > 0 && recordYuanSuperChats.contains(platform);
    final attributes = StringBuffer('ts="${_seconds(at)}" user="${escape(superChat.userName)}"');
    if (inYuan) attributes.write(' price="${price * 1000}"');
    attributes.write(' time="${shown < 0 ? 0 : shown}"');
    if (!inYuan && price > 0) attributes.write(' value="$price"');
    // A blank would end the value for DanmakuFactory, as in a gift's name.
    final priceText = escape(superChat.priceText).replaceAll(_blank, '\u00A0');
    if (priceText.isNotEmpty) attributes.write(' pricetext="$priceText"');
    _entry(at, '<sc $attributes>${escape(superChat.message)}</sc>\n');
    _paidCount++;
  }

  /// Writes what [combo] counted and has not written yet.
  void _writeCombo(_GiftCombo combo) {
    final count = combo.total - combo.written;
    final at = combo.startMs;
    combo
      ..written = combo.total
      ..startMs = null
      ..openedAt = null;
    if (count <= 0 || at == null) return;
    final gift = combo.gift;
    final name = escape(gift.displayName).replaceAll(_blank, '\u00A0');
    final attributes = StringBuffer(
      'ts="${_seconds(at)}" user="${escape(combo.message.userName)}" giftname="$name" giftcount="$count"',
    );
    final value = giftValueOfCount(gift, count);
    final thousandths = recordGiftThousandths(gift, value);
    if (thousandths != null) attributes.write(' price="$thousandths"');
    if (value != null && value > 0) attributes.write(' value="$value" unit="${gift.unit.name}"');
    _entry(at, '<gift $attributes />\n');
  }

  /// Writes the combos that are over (or open for [maxComboSpan]; with
  /// [all] every one), then the held entries before the first combo still
  /// open.
  void _settle(DateTime now, {required bool all}) {
    if (_combos.isEmpty && _held.isEmpty) return;
    for (final combo in _combos.values) {
      final idle = now.difference(combo.lastAt);
      final opened = combo.openedAt;
      if (all || idle >= comboWindow || (opened != null && now.difference(opened) >= maxComboSpan)) {
        _writeCombo(combo);
      }
      if (idle >= comboWindow) combo.ended = true;
    }
    _combos.removeWhere((_, combo) => combo.startMs == null && now.difference(combo.lastAt) > summaryWindow);
    if (_held.isEmpty) return;
    int? until;
    for (final combo in _combos.values) {
      final at = combo.startMs;
      if (at != null && (until == null || at < until)) until = at;
    }
    _held.sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.sequence.compareTo(b.sequence));
    var ready = 0;
    while (ready < _held.length && (until == null || _held[ready].at < until)) {
      _pending.write(_held[ready].text);
      ready++;
    }
    _held.removeRange(0, ready);
  }

  /// Queues [text], timed [at] ms: straight for the file while nothing is
  /// held back, else in time order with the held entries.
  void _entry(int at, String text) {
    if (_held.isEmpty && !_combos.values.any((combo) => combo.startMs != null)) {
      _pending.write(text);
    } else {
      _held.add(_HeldEntry(at, _sequence++, text));
    }
  }

  int _offsetMs(DateTime receivedAt) {
    final offset = receivedAt.difference(startedAt).inMilliseconds;
    return offset < 0 ? 0 : offset;
  }

  static String _seconds(int ms) => (ms / 1000.0).toStringAsFixed(3);

  /// Writes the pending entries followed by the closing tag.
  Future<void> flush() => _flush(all: false);

  Future<void> _flush({required bool all}) async {
    while (_writing != null) {
      await _writing;
    }
    _settle(clock.now(), all: all);
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

  /// Flushes everything, open combos included, and closes the file.
  Future<void> close() async {
    if (_closed) return;
    try {
      await _flush(all: true);
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

/// The gift units whose rate in yuan the platform fixes: a recorded gift in
/// one of them gets a `price` in thousandths of a yuan (H01.8). The same set
/// as the gift line's "礼物价值换算成元" (the app's `giftYuanUnits`, A08.12; a
/// test keeps them equal); the overseas rates in [giftUnitsPerYuan] only
/// rank gifts.
const Set<LiveGiftUnit> recordYuanUnits = {
  LiveGiftUnit.fen,
  LiveGiftUnit.yuan,
  LiveGiftUnit.goldSeed,
  LiveGiftUnit.diamond,
  LiveGiftUnit.douyinCoin,
  LiveGiftUnit.acCoin,
};

/// The platforms whose `LiveSuperChatMessage.price` is in yuan: Bilibili's
/// `price`, and Douyu's `cprice` in fen made yuan (H01.8). Elsewhere (Huya
/// unchecked, CHZZK cheese, YouTube's text) the number is kept as it is.
const Set<String> recordYuanSuperChats = {SiteIds.bilibili, SiteIds.douyu};

/// What [gift] worth [value] (in its unit) is in thousandths of a yuan, the
/// recorded `price`: 0 when free, null when unknown or not in a unit fixed
/// in yuan.
int? recordGiftThousandths(LiveGift gift, int? value) {
  if (gift.free) return 0;
  final rate = giftUnitsPerYuan[gift.unit];
  if (value == null || value <= 0 || rate == null || !recordYuanUnits.contains(gift.unit)) return null;
  return (value * 1000 / rate).round();
}

/// One combo of gifts being recorded: the newest message and gift and when
/// it came; where in the file, and since when, the part not written yet
/// starts; its count and how much of it is written.
final class _GiftCombo {
  new(this.message, this.gift, {required DateTime at, required int this.startMs, required this.total})
    : lastAt = at,
      openedAt = at,
      running = gift.comboTotal;

  LiveMessage message;
  LiveGift gift;
  DateTime lastAt;
  DateTime? openedAt;
  int? startMs;
  int total;
  int written = 0;
  int? running;
  bool ended = false;

  /// [gift] of [message] counted on it at [receivedAt] ([at] ms into the
  /// file), the combo's count now [total].
  void count(LiveMessage message, LiveGift gift, DateTime receivedAt, int at, int total) {
    this.message = message;
    this.gift = gift;
    lastAt = receivedAt;
    running = gift.comboTotal ?? running;
    if (total <= this.total) return;
    this.total = total;
    ended = false;
    if (startMs == null) {
      startMs = at;
      openedAt = receivedAt;
    }
  }
}

/// An entry held back behind an open combo: its time (ms), arrival order
/// and text.
final class _HeldEntry {
  new(this.at, this.sequence, this.text);

  final int at;
  final int sequence;
  final String text;
}

final class _TaskChat {
  new(this.taskId);

  final String taskId;
  RecordChatConnection? connection;
  bool connecting = false;
  DateTime? failedAt;
  RecordChatWriter? writer;
  Future<RecordChatWriter?>? opening;
  String? writerKey;
  String? preparing;
  DateTime? session;
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
/// timed from before the stream was resolved, a few seconds early; an
/// attempt already running when the setting is switched on still is). A
/// reconnect gap has no video, so its chat is not written. A connection
/// that fails or ends is tried again after [retryDelay]. A task's own
/// choice (`RecordTask.recordDanmakuOverride`) wins over [enabled].
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

  /// Entries of the closed files of each task's session (keyed by the
  /// session's start), kept after the task stops for its summary.
  final _written = <String, ({DateTime? session, int count})>{};
  late final Timer _flushTimer;
  var _disposed = false;

  static const Set<RecordStatus> _connected = {RecordStatus.preparing, RecordStatus.running, RecordStatus.reconnecting};

  /// What reaches the file: chat, and the gifts and super chats the
  /// connector delivers when the user records them (H01.8).
  static const Set<LiveMessageType> _recordedTypes = {
    LiveMessageType.chat,
    LiveMessageType.gift,
    LiveMessageType.superChat,
  };

  /// The chat file of [taskId]'s current attempt (tests, diagnostics).
  File? fileOf(String taskId) => _tasks[taskId]?.writer?.file;

  /// Chat messages saved in [task]'s current or last session, over all its
  /// attempts (the live room's "弹幕 N 条").
  int countOf(RecordTask task) {
    final written = _written[task.taskId];
    final closed = written != null && written.session == task.recordingStartedAt ? written.count : 0;
    final state = _tasks[task.taskId];
    final open = state != null && state.session == task.recordingStartedAt ? state.writer?.count ?? 0 : 0;
    return closed + open;
  }

  /// Follows [tasks] (the recorder's list after a change, or after the
  /// setting changed).
  void sync(Iterable<RecordTask> tasks) {
    if (_disposed) return;
    final seen = <String>{};
    final wanted = enabled();
    for (final task in tasks) {
      seen.add(task.taskId);
      if (!task.recordsChat(fallback: wanted) || !_connected.contains(task.status)) {
        unawaited(_release(task.taskId));
        continue;
      }
      final state = _tasks.putIfAbsent(task.taskId, () => _TaskChat(task.taskId));
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
    state.session = task.recordingStartedAt;
    final directory = task.outputDir?.trim() ?? '';
    if (task.status == RecordStatus.preparing) state.preparing = task.recordingFilePrefix;
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
    // The video starts as the attempt turns from preparing to running; an
    // attempt already running when chat was switched on is timed from its
    // creation (3.x's base, a few seconds early).
    final startedAt = state.preparing == prefix ? clock.now() : task.createTime;
    final opening = RecordChatWriter.open(
      File(p.join(directory, '$prefix.xml')),
      startedAt: startedAt,
      platform: task.platform,
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
    if (state.released || writer == null || !_recordedTypes.contains(message.type)) return;
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
    if (writer != null && writer.count > 0) {
      final previous = _written[state.taskId];
      final base = previous != null && previous.session == state.session ? previous.count : 0;
      _written[state.taskId] = (session: state.session, count: base + writer.count);
    }
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
