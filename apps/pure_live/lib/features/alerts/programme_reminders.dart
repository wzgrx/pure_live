import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// A reminder for an upcoming IPTV programme (F-IPTV-09, part of F-NEW-01).
@immutable
final class ProgrammeReminder {
  /// Creates a reminder.
  const new({required this.room, required this.title, required this.start, required this.stop});

  /// The reminder of [programme] on the channel [room].
  factory of(RoomRef room, IptvProgramme programme) =>
      ProgrammeReminder(room: room, title: programme.title, start: programme.start, stop: programme.stop);

  /// The channel (`iptv:<name>`).
  final RoomRef room;

  /// Programme title.
  final String title;

  /// Programme start (UTC).
  final DateTime start;

  /// Programme stop (UTC).
  final DateTime stop;

  /// How long before [start] the notification goes out.
  static const lead = Duration(minutes: 1);

  /// Identity: one reminder per channel and start time.
  String get key => '${room.key}@${start.millisecondsSinceEpoch}';

  /// When the notification goes out.
  DateTime get dueAt => start.subtract(lead);

  /// The notification; a tap opens the channel.
  AlertNotice get notice => AlertNotice(
    id: alertIdOf('programme:$key'),
    channel: AlertChannel.programme,
    title: t.alerts.programmeStarting(title: title),
    body: t.alerts.programmeBody(channel: room.roomId, time: clockText(start)),
    payload: roomLocation(room),
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'platform': room.platform,
    'roomId': room.roomId,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'stop': stop.millisecondsSinceEpoch,
  };

  /// Reads [toJson]; null when malformed.
  static ProgrammeReminder? fromJson(Object? json) {
    if (json is! Map) return null;
    final (platform, roomId, title, start, stop) = (
      json['platform'],
      json['roomId'],
      json['title'],
      json['start'],
      json['stop'],
    );
    if (platform is! String || roomId is! String || title is! String || start is! int || stop is! int) return null;
    try {
      return ProgrammeReminder(
        room: RoomRef(platform, roomId),
        title: title,
        start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
        stop: DateTime.fromMillisecondsSinceEpoch(stop, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProgrammeReminder && other.key == key && other.title == title && other.stop == stop;

  @override
  int get hashCode => Object.hash(key, title, stop);

  @override
  String toString() => 'ProgrammeReminder($key, $title)';
}

/// Where the reminder list is kept: the `meta` table (never backed up).
final class ReminderStorage {
  /// Creates the storage from a reader and a writer of the JSON text.
  const new({required this.read, required this.write});

  /// Meta key of the list.
  static const key = 'alerts.programmeReminders';

  /// Reads the stored JSON text, or null.
  final Future<String?> Function() read;

  /// Stores the JSON text; null removes it.
  final Future<void> Function(String? text) write;
}

/// The reminder list's storage in the app database.
final programmeReminderStorageProvider = Provider<ReminderStorage>((ref) {
  final meta = ref.watch(storeProvider).meta;
  return ReminderStorage(
    read: () => meta.get(ReminderStorage.key),
    write: (text) => meta.set(ReminderStorage.key, text),
  );
});

/// The clock of the reminders; tests replace it.
final alertClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Programme reminders (F-IPTV-09): each fires [ProgrammeReminder.lead]
/// before its programme starts while the process lives, then leaves the
/// list. The list is stored, so [restore] at start reschedules the ones whose
/// programme has not started: due ones fire at once, started ones are
/// dropped.
class ProgrammeRemindersNotifier extends Notifier<List<ProgrammeReminder>> {
  final Map<String, Timer> _timers = {};
  Future<int>? _restored;

  @override
  List<ProgrammeReminder> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const [];
  }

  DateTime _now() => ref.read(alertClockProvider)().toUtc();

  /// Loads the stored list once and schedules it; returns how many are
  /// pending.
  Future<int> restore() => _restored ??= _restore();

  Future<int> _restore() async {
    final storage = ref.read(programmeReminderStorageProvider);
    final stored = _decode(await storage.read());
    if (!ref.mounted) return 0;
    final now = _now();
    final pending = {
      for (final reminder in [...stored, ...state])
        if (now.isBefore(reminder.start)) reminder.key: reminder,
    }.values.toList()..sort(_byStart);
    state = pending;
    if (pending.length != stored.length) await _save();
    pending.forEach(_schedule);
    return pending.length;
  }

  /// Whether [reminder] is set.
  bool contains(ProgrammeReminder reminder) => state.any((item) => item.key == reminder.key);

  /// Sets [reminder], or removes it when it is set; returns whether it is set
  /// afterwards. A programme that already started cannot be set.
  Future<bool> toggle(ProgrammeReminder reminder) async {
    await restore();
    if (!ref.mounted) return false;
    if (contains(reminder)) {
      _timers.remove(reminder.key)?.cancel();
      state = [...state.where((item) => item.key != reminder.key)];
      await _save();
      return false;
    }
    if (!_now().isBefore(reminder.start)) return false;
    state = [...state, reminder]..sort(_byStart);
    _schedule(reminder);
    await _save();
    return true;
  }

  void _schedule(ProgrammeReminder reminder) {
    _timers.remove(reminder.key)?.cancel();
    final delay = reminder.dueAt.difference(_now());
    _timers[reminder.key] = Timer(delay.isNegative ? Duration.zero : delay, () => unawaited(_fire(reminder)));
  }

  Future<void> _fire(ProgrammeReminder reminder) async {
    _timers.remove(reminder.key);
    if (!ref.mounted || !contains(reminder)) return;
    state = [...state.where((item) => item.key != reminder.key)];
    try {
      await ref.read(alertNotifierProvider).show(reminder.notice);
    } on Object catch (error) {
      ref.read(appLogProvider).warning('alerts', 'programme reminder failed', error);
    }
    await _save();
  }

  Future<void> _save() async {
    if (!ref.mounted) return;
    final storage = ref.read(programmeReminderStorageProvider);
    final list = state;
    try {
      await storage.write(list.isEmpty ? null : jsonEncode([for (final reminder in list) reminder.toJson()]));
    } on Object catch (error) {
      ref.read(appLogProvider).warning('alerts', 'saving programme reminders failed', error);
    }
  }

  static int _byStart(ProgrammeReminder a, ProgrammeReminder b) => a.start.compareTo(b.start);

  static List<ProgrammeReminder> _decode(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final json = jsonDecode(text);
      if (json is! List) return const [];
      return [for (final item in json) ?ProgrammeReminder.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }
}

/// The programme reminders of the app.
final programmeRemindersProvider = NotifierProvider<ProgrammeRemindersNotifier, List<ProgrammeReminder>>(
  ProgrammeRemindersNotifier.new,
);
