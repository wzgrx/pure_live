import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live/i18n/i18n.dart';

/// What a programme of the guide is now (docs/T05/T05i/T05i.1 c17, c18).
enum GuideProgrammeKind {
  /// Ended and still kept: "回看".
  replayable,

  /// Ended, outside the catch-up window (or no catch-up): greyed.
  gone,

  /// On air: the live mark "正在直播".
  live,

  /// Being replayed now: "回看中".
  replaying,

  /// Not started yet.
  scheduled,
}

/// A line of the guide: a day's heading or a programme.
sealed class GuideEntry {
  const new();
}

/// "今天 · 10月1日 周四".
final class GuideDay extends GuideEntry {
  /// Creates the heading of [day].
  const new(this.day);

  /// Midnight of the day.
  final DateTime day;
}

/// A programme and what it is now.
final class GuideProgramme extends GuideEntry {
  /// Creates the line.
  const new(this.programme, this.kind);

  /// The programme.
  final EpgProgramme programme;

  /// What it is now.
  final GuideProgrammeKind kind;
}

/// The height of a programme line (c17: 52, fixed, so the list jumps to the
/// programme on air without measuring).
const double guideRowHeight = 52;

/// The height of a day's heading.
const double guideDayHeight = 32;

/// The guide's lines: [programmes] (sorted by start) under a heading per
/// day, each marked against [now], the channel's [catchUp] window and the
/// programme being [replaying].
List<GuideEntry> guideEntries(
  List<EpgProgramme> programmes, {
  required DateTime now,
  required CatchUp catchUp,
  EpgProgramme? replaying,
}) {
  final entries = <GuideEntry>[];
  DateTime? day;
  for (final programme in programmes) {
    final start = programme.start.toLocal();
    final midnight = DateTime(start.year, start.month, start.day);
    if (midnight != day) {
      day = midnight;
      entries.add(GuideDay(midnight));
    }
    entries.add(GuideProgramme(programme, _kind(programme, now: now, catchUp: catchUp, replaying: replaying)));
  }
  return entries;
}

GuideProgrammeKind _kind(
  EpgProgramme programme, {
  required DateTime now,
  required CatchUp catchUp,
  EpgProgramme? replaying,
}) {
  if (replaying != null && replaying.start == programme.start && replaying.title == programme.title) {
    return GuideProgrammeKind.replaying;
  }
  return switch (classifyIptvProgramme(start: programme.start, stop: programme.stop, now: now)) {
    IptvProgrammePhase.live => GuideProgrammeKind.live,
    IptvProgrammePhase.scheduled => GuideProgrammeKind.scheduled,
    IptvProgrammePhase.catchup =>
      evaluateIptvCatchupAvailability(
                programmeStop: programme.stop,
                now: now,
                mode: catchUp.mode,
                source: catchUp.source,
                days: catchUp.days,
              ) ==
              IptvCatchupAvailability.available
          ? GuideProgrammeKind.replayable
          : GuideProgrammeKind.gone,
  };
}

/// The scroll offset that puts the programme being watched (replayed, else
/// on air) on the third line (c17: the replayable ones just above show),
/// or 0 when there is none.
double guideAnchorOffset(List<GuideEntry> entries) {
  var target = entries.indexWhere((e) => e is GuideProgramme && e.kind == GuideProgrammeKind.replaying);
  if (target < 0) target = entries.indexWhere((e) => e is GuideProgramme && e.kind == GuideProgrammeKind.live);
  if (target < 0) return 0;
  var offset = 0.0;
  for (final entry in entries.take(target)) {
    offset += entry is GuideDay ? guideDayHeight : guideRowHeight;
  }
  final above = offset - 2 * guideRowHeight;
  return above < 0 ? 0 : above;
}

/// "今天 · 10月1日 周四" ("昨天", "明天"; other days only the date).
String guideDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final difference = DateTime(day.year, day.month, day.day).difference(today).inHours;
  final date = i18n(
    'live_play_guide_date',
    args: {'month': '${day.month}', 'day': '${day.day}', 'weekday': i18n('live_play_weekday_${day.weekday}')},
  );
  final relative = switch ((difference / 24).round()) {
    0 => i18n('history_section_today'),
    -1 => i18n('history_section_yesterday'),
    1 => i18n('live_play_guide_tomorrow'),
    _ => null,
  };
  return relative == null ? date : '$relative · $date';
}

/// The guide's note on catch-up: "可回看 2 天", "不支持回看", or empty when the
/// channel does not say how long it keeps (U.2g note 8).
String guideCatchupNote(CatchUp catchUp, DateTime now) {
  final availability = evaluateIptvCatchupAvailability(
    programmeStop: now,
    now: now,
    mode: catchUp.mode,
    source: catchUp.source,
    days: catchUp.days,
  );
  if (availability == IptvCatchupAvailability.disabled || availability == IptvCatchupAvailability.unsupported) {
    return i18n('live_play_guide_no_catchup');
  }
  final days = catchUp.days;
  if (days == null || !days.isFinite || days <= 0) return '';
  final shown = days == days.roundToDouble() ? '${days.round()}' : days.toStringAsFixed(1);
  return i18n('live_play_guide_catchup_days', args: {'days': shown});
}

/// "HH:mm" in local time.
String guideTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
