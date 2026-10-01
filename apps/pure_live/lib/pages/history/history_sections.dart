import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// When a history entry was last watched, by calendar day.
enum HistorySection {
  /// Today.
  today('history_section_today'),

  /// Yesterday.
  yesterday('history_section_yesterday'),

  /// Two to six days ago.
  thisWeek('history_section_week'),

  /// Earlier, or no watch time (entries imported from old versions).
  earlier('history_section_earlier');

  new(this.titleKey);

  /// The heading's translation key.
  final String titleKey;

  /// The section of a watch at [watchedAt] (milliseconds since the epoch,
  /// local time) seen [now].
  static HistorySection of(int? watchedAt, DateTime now) {
    if (watchedAt == null || watchedAt <= 0) return earlier;
    final watched = DateTime.fromMillisecondsSinceEpoch(watchedAt);
    // Rounded: a day across a daylight-saving change is 23 or 25 hours.
    final days =
        (DateTime(now.year, now.month, now.day).difference(DateTime(watched.year, watched.month, watched.day)).inHours /
                24)
            .round();
    // A watch "in the future" (clock changed) counts as today.
    return switch (days) {
      <= 0 => today,
      1 => yesterday,
      < 7 => thisWeek,
      _ => earlier,
    };
  }
}

/// [rooms] (newest first) in their sections, in section order; empty
/// sections are left out and each keeps the stored order.
List<(HistorySection, List<LiveRoom>)> historySections(List<LiveRoom> rooms, DateTime now) {
  final grouped = <HistorySection, List<LiveRoom>>{};
  for (final room in rooms) {
    (grouped[HistorySection.of(room.lastWatchedAt, now)] ??= []).add(room);
  }
  return [
    for (final section in HistorySection.values)
      if (grouped[section] case final rooms?) (section, rooms),
  ];
}

/// [rooms] whose title, streamer, room id or platform name contains
/// [query] (any case); all of them for a blank query.
List<LiveRoom> filterHistory(List<LiveRoom> rooms, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return rooms;
  return [
    for (final room in rooms)
      if ([
        room.title,
        room.nick,
        room.roomId,
        room.platform,
        platformName(room.platform),
      ].any((text) => text.toLowerCase().contains(needle)))
        room,
  ];
}

/// The heading of [section].
String historySectionTitle(HistorySection section) => i18n(section.titleKey);

/// When [watchedAt] was, for the room menu: "today 21:05", "09-30 21:05",
/// "2025-09-30 21:05", or "watched earlier" without a time (3.x's room
/// switcher used the same words).
String historyWatchedLabel(int? watchedAt, DateTime now) {
  if (watchedAt == null || watchedAt <= 0) return i18n('history_earlier');
  final watched = DateTime.fromMillisecondsSinceEpoch(watchedAt);
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(watched.hour)}:${two(watched.minute)}';
  if (HistorySection.of(watchedAt, now) == HistorySection.today) {
    return i18n('watched_today_at', args: {'time': time});
  }
  final date = watched.year == now.year
      ? '${two(watched.month)}-${two(watched.day)}'
      : '${watched.year}-${two(watched.month)}-${two(watched.day)}';
  return i18n('watched_at', args: {'time': '$date $time'});
}
