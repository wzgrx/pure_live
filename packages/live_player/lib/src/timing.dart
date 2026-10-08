import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';
import 'package:meta/meta.dart';

/// The time the start-up marks read (G03.1): a monotonic stopwatch from
/// the first read, not the wall clock. The wall clock may be set while a
/// room opens; a K90 line read `detail=869 … firstFrame=475 total=13`, its
/// steps adding up to 1.37 s. Inside a test's clock (`withClock`,
/// fake_async) it follows that clock. Replaceable in tests.
@visibleForTesting
DateTime Function() timingNow = _monotonicNow;

final Stopwatch _sinceFirstRead = Stopwatch()..start();
final DateTime _firstRead = DateTime.now();

DateTime _monotonicNow() {
  final zone = clock;
  if (!identical(zone, const Clock())) return zone.now();
  return _firstRead.add(_sinceFirstRead.elapsed);
}

/// G03.1: the room's half of the start-up timing. The room makes it when it
/// is entered (T0, or the release of a swipe) and marks, once each, when its
/// detail (T1), qualities (T2) and play URLs (T3) came back; the session
/// times the rest of the open from there ([PlaybackTiming]).
final class StartupMarks {
  /// Marks T0 now.
  new() : started = timingNow();

  /// T0: the room was entered.
  final DateTime started;

  DateTime? _detail;
  DateTime? _qualities;
  DateTime? _urls;

  /// T1: the room detail came back.
  DateTime? get detail => _detail;

  /// T2: the qualities came back.
  DateTime? get qualities => _qualities;

  /// T3: the play URLs came back.
  DateTime? get urls => _urls;

  /// Marks T1 (only the first call counts).
  void markDetail() => _detail ??= timingNow();

  /// Marks T2 (only the first call counts).
  void markQualities() => _qualities ??= timingNow();

  /// Marks T3 (only the first call counts).
  void markUrls() => _urls ??= timingNow();
}

/// Receives the timing of an open that ended (`PlaybackRequest.onTiming`).
typedef PlaybackTimingSink = void Function(PlaybackTiming timing);

/// G03.1: how long one open took, step by step, from the room's T0 (or the
/// session's open without a room) to the first `playing` or the error that
/// ended it. An open replaced by another one has no timing.
@immutable
final class PlaybackTiming {
  /// Creates a timing; [segments] follow [segmentNames].
  const new({
    required this.site,
    required this.route,
    required this.engineReused,
    required this.error,
    required this.segments,
    required this.total,
  });

  /// The names of [segments], in order: each one ends at its mark (T1 to T8)
  /// and starts at the latest mark before it.
  static const segmentNames = ['detail', 'qualities', 'urls', 'engineReady', 'input', 'load', 'firstFrame', 'playing'];

  /// The platform id.
  final String site;

  /// How the first input reached the engine; null when none opened.
  final MediaRoute? route;

  /// Whether the open found an engine already made (a reused player); null
  /// when it ended before it had one.
  final bool? engineReused;

  /// The code of the failure that ended the open; null when it played.
  final String? error;

  /// The steps of [segmentNames]; null where the mark was not reached, or
  /// came after a later one (it then counts in the later step).
  final List<Duration?> segments;

  /// From T0 (or the session's open) to the end.
  final Duration total;

  /// The step called [name] of [segmentNames].
  Duration? segment(String name) => segments[segmentNames.indexOf(name)];

  /// The log line, fixed fields for scripts, no address or header; [room]
  /// is a short tag of the room:
  /// `playback-timing site=bilibili room=1a2b3c route=direct engine=new
  /// result=playing detail=312 … playing=702 total=1697`.
  String line({String? room}) {
    final engine = switch (engineReused) {
      true => 'reused',
      false => 'new',
      null => '-',
    };
    final fields = StringBuffer('playback-timing site=$site room=${room ?? '-'}')
      ..write(' route=${route?.name ?? '-'} engine=$engine')
      ..write(' result=${error == null ? 'playing' : 'error:$error'}');
    for (final (index, name) in segmentNames.indexed) {
      fields.write(' $name=${segments[index]?.inMilliseconds ?? '-'}');
    }
    fields.write(' total=${total.inMilliseconds}');
    return fields.toString();
  }

  @override
  String toString() => line();
}

/// The session's half of one open's timing: T4 engine ready, T5 input
/// opened, T6 `engine.open` returned, T7 first video size, T8 first playing.
/// Only [timingNow] reads while the open runs; nothing once it ended.
@internal
final class OpenTiming {
  /// Starts timing an open of [site] that continues [startup].
  new({required this.site, required this.startup, required this.sink}) : opened = timingNow();

  /// T4: the engine is ready.
  static const engineReady = 0;

  /// T5: the input opened.
  static const input = 1;

  /// T6: the engine's open returned.
  static const loaded = 2;

  /// T7: the first video size.
  static const firstFrame = 3;

  /// T8: the first `playing`.
  static const playing = 4;

  /// The platform id.
  final String site;

  /// The room's marks, if a room opened it.
  final StartupMarks? startup;

  /// Where the timing goes.
  final PlaybackTimingSink sink;

  /// When the session's open was called.
  final DateTime opened;

  final List<DateTime?> _marks = List.filled(5, null);
  MediaRoute? _route;
  bool? _reused;

  /// Whether [index] was marked.
  bool has(int index) => _marks[index] != null;

  /// Marks [index] now, once; a mark after a later one is dropped (that
  /// step then counts in the later one), so the steps never go negative.
  void mark(int index) {
    for (var later = index; later < _marks.length; later++) {
      if (_marks[later] != null) return;
    }
    _marks[index] = timingNow();
  }

  /// T4, and whether the engine was there already.
  void engineReadyAt({required bool reused}) {
    _reused ??= reused;
    mark(engineReady);
  }

  /// T5, and the input's route.
  void inputOpened(MediaRoute route) {
    _route ??= route;
    mark(input);
  }

  /// Ends the open now: [error] is the failure's code, null when it plays.
  PlaybackTiming finish({String? error}) {
    final end = timingNow();
    final room = startup;
    final start = room?.started ?? opened;
    var previous = start;
    final segments = <Duration?>[];
    for (final at in [room?.detail, room?.qualities, room?.urls, ..._marks]) {
      if (at == null) {
        segments.add(null);
        continue;
      }
      segments.add(at.difference(previous));
      previous = at;
    }
    return PlaybackTiming(
      site: site,
      route: _route,
      engineReused: _reused,
      error: error,
      segments: List.unmodifiable(segments),
      total: end.difference(start),
    );
  }
}
