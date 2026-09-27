import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';

/// A recording booked for a time window (F-IPTV-10, part of the recording
/// center): an IPTV programme, or any room between two times.
@immutable
final class ScheduledRecording {
  const new({required this.room, required this.title, required this.start, required this.stop});

  /// The booking of [programme] on channel [room].
  factory ofProgramme(RoomRef room, IptvProgramme programme) =>
      ScheduledRecording(room: room, title: programme.title, start: programme.start, stop: programme.stop);

  final RoomRef room;
  final String title;

  /// Window start and end (UTC).
  final DateTime start;
  final DateTime stop;

  /// Identity: one booking per room and start.
  String get key => '${room.key}@${start.millisecondsSinceEpoch}';

  Map<String, Object?> toJson() => {
    'platform': room.platform,
    'roomId': room.roomId,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'stop': stop.millisecondsSinceEpoch,
  };

  static ScheduledRecording? fromJson(Object? json) {
    if (json is! Map) return null;
    final (platform, roomId, title, start, stop) = (
      json['platform'],
      json['roomId'],
      json['title'],
      json['start'],
      json['stop'],
    );
    if (platform is! String || roomId is! String || title is! String || start is! int || stop is! int) return null;
    if (stop <= start) return null;
    try {
      return ScheduledRecording(
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
  bool operator ==(Object other) => other is ScheduledRecording && other.key == key && other.stop == stop;

  @override
  int get hashCode => Object.hash(key, stop);
}

/// What the schedule does to the recorder; tests replace it.
abstract interface class ScheduleRecorder {
  /// Starts recording [room]; true when this call started it (the room was
  /// not being recorded already).
  Future<bool> start(RoomRef room);

  /// Stops recording [room].
  Future<void> stop(RoomRef room);
}

/// [ScheduleRecorder] over the app's recorder and adapters.
final class ManagerScheduleRecorder implements ScheduleRecorder {
  const new(this._ref);

  final Ref _ref;

  @override
  Future<bool> start(RoomRef room) async {
    final manager = _ref.read(recordManagerProvider);
    final existing = manager.tasks.where((task) => task.room == room).firstOrNull;
    if (existing != null && existing.state.active) return false;
    final detail = await _ref.read(sitesProvider).of(room.platform).rooms.detail(room);
    await manager.add(detail);
    return true;
  }

  @override
  Future<void> stop(RoomRef room) => _ref.read(recordManagerProvider).stop(room.key);
}

/// The recorder the schedule drives.
final Provider<ScheduleRecorder> scheduleRecorderProvider = Provider<ScheduleRecorder>(ManagerScheduleRecorder.new);

/// The schedule's clock; tests replace it.
final Provider<DateTime Function()> scheduleClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Scheduled recordings (F-IPTV-10): each starts recording at its start (at
/// once when the app opens inside the window) and stops at its end, while
/// the process lives. A recording the user had already started is left
/// running at the end. The list is kept in the `meta` table.
class RecordScheduleNotifier extends Notifier<List<ScheduledRecording>> {
  static const metaKey = 'record.schedules';

  final Map<String, Timer> _timers = {};
  final Set<String> _started = {};
  Future<void>? _restored;

  @override
  List<ScheduledRecording> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const [];
  }

  DateTime _now() => ref.read(scheduleClockProvider)().toUtc();

  /// Loads the stored list once and schedules it.
  Future<void> restore() => _restored ??= _restore();

  Future<void> _restore() async {
    String? text;
    try {
      text = await ref.read(storeProvider).meta.get(metaKey);
    } on Object {
      text = null;
    }
    if (!ref.mounted) return;
    final now = _now();
    final stored = _decode(text);
    final pending = {
      for (final item in [...stored, ...state])
        if (now.isBefore(item.stop)) item.key: item,
    }.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    state = pending;
    if (pending.length != stored.length) await _save();
    pending.forEach(_schedule);
  }

  /// Whether [item] is booked.
  bool contains(ScheduledRecording item) => state.any((booked) => booked.key == item.key);

  /// Books [item]; false when its window has already ended.
  Future<bool> add(ScheduledRecording item) async {
    await restore();
    if (!ref.mounted || !_now().isBefore(item.stop)) return false;
    state = [...state.where((booked) => booked.key != item.key), item]..sort((a, b) => a.start.compareTo(b.start));
    _schedule(item);
    await _save();
    return true;
  }

  /// Cancels [item]; a recording it started stops.
  Future<void> remove(ScheduledRecording item) async {
    await restore();
    if (!ref.mounted) return;
    _timers.remove('${item.key}:start')?.cancel();
    _timers.remove('${item.key}:stop')?.cancel();
    state = [...state.where((booked) => booked.key != item.key)];
    if (_started.remove(item.key)) await _stopRecording(item);
    await _save();
  }

  void _schedule(ScheduledRecording item) {
    final now = _now();
    _timers.remove('${item.key}:start')?.cancel();
    _timers.remove('${item.key}:stop')?.cancel();
    final untilStart = item.start.difference(now);
    _timers['${item.key}:start'] = Timer(
      untilStart.isNegative ? Duration.zero : untilStart,
      () => unawaited(_begin(item)),
    );
    _timers['${item.key}:stop'] = Timer(item.stop.difference(now), () => unawaited(_end(item)));
  }

  Future<void> _begin(ScheduledRecording item) async {
    _timers.remove('${item.key}:start');
    if (!ref.mounted || !contains(item)) return;
    try {
      if (await ref.read(scheduleRecorderProvider).start(item.room)) _started.add(item.key);
    } on Object {
      // The recorder shows why (offline, unsupported stream); the booking
      // stays until its end.
    }
  }

  Future<void> _end(ScheduledRecording item) async {
    _timers.remove('${item.key}:stop');
    if (!ref.mounted || !contains(item)) return;
    state = [...state.where((booked) => booked.key != item.key)];
    if (_started.remove(item.key)) await _stopRecording(item);
    await _save();
  }

  Future<void> _stopRecording(ScheduledRecording item) async {
    try {
      await ref.read(scheduleRecorderProvider).stop(item.room);
    } on Object {
      // Already stopped.
    }
  }

  Future<void> _save() async {
    if (!ref.mounted) return;
    final list = state;
    try {
      await ref
          .read(storeProvider)
          .meta
          .set(metaKey, list.isEmpty ? null : jsonEncode([for (final item in list) item.toJson()]));
    } on Object {
      // Kept in memory for this run.
    }
  }

  static List<ScheduledRecording> _decode(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final json = jsonDecode(text);
      if (json is! List) return const [];
      return [for (final item in json) ?ScheduledRecording.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }
}

/// The scheduled recordings.
final NotifierProvider<RecordScheduleNotifier, List<ScheduledRecording>> recordScheduleProvider =
    NotifierProvider<RecordScheduleNotifier, List<ScheduledRecording>>(RecordScheduleNotifier.new);

/// Restores the schedule at start; `PureLiveApp` watches it.
final Provider<void> recordScheduleStartupProvider = Provider<void>((ref) {
  unawaited(ref.read(recordScheduleProvider.notifier).restore());
});

/// 预约录制 on an upcoming programme of the guide (F-IPTV-10).
class ProgrammeRecordButton extends ConsumerWidget {
  const new({required this.room, required this.programme, super.key});

  final RoomRef room;
  final IptvProgramme programme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ScheduledRecording.ofProgramme(room, programme);
    final on = ref.watch(recordScheduleProvider).any((booked) => booked.key == item.key);
    return IconButton(
      tooltip: on ? '取消预约录制' : '预约录制',
      isSelected: on,
      icon: const Icon(Icons.radio_button_unchecked),
      selectedIcon: const Icon(Icons.radio_button_checked),
      onPressed: () {
        final schedule = ref.read(recordScheduleProvider.notifier);
        unawaited(on ? schedule.remove(item) : schedule.add(item));
      },
    );
  }
}
