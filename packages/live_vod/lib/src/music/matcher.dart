import 'dart:math' as math;

import 'package:live_core/live_core.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/music/third_party.dart';
import 'package:meta/meta.dart';

/// A scored candidate.
@immutable
final class TrackMatch {
  /// Creates a match.
  const new({required this.archive, required this.score, required this.reason});

  /// The archive.
  final VodArchive archive;

  /// Score; higher is better.
  final int score;

  /// Which rule placed it: `both` (title has song and artist), `one`, `word`,
  /// `chinese` (a shared Chinese run of 4+ characters).
  final String reason;
}

/// Song (name, artist, length) → Bilibili archive, the rules of the bmsc
/// playlist importer as pure_live_TV `b9d2f739` `playlist_matcher.dart`
/// ports them.
///
/// Search `"<song> - <artist>"`, then score each video hit:
///
/// 1. Partitions `音Mad`, `音乐现场`, `翻唱`, `学科科普`, `运动综合` are
///    dropped.
/// 2. The title is split into words (runs of letters, digits, `_` and CJK
///    ideographs, lower case). Base score:
///    - the song's words and the artist's words both appear as consecutive
///      runs: 100000 (whatever the length);
///    - otherwise a length difference over 20 s drops the hit;
///    - one of the two appears: 10;
///    - any word of the query appears: 5;
///    - the query and the title share a Chinese run of 4+ characters: 0;
///    - else the hit is dropped.
/// 3. + 1000 for partitions `MV`, `音乐综合`, `电台`.
/// 4. − the length difference in seconds.
/// 5. + 5 × log10(plays).
///
/// The best score wins; ties keep the search order.
abstract final class TrackMatcher {
  static const Set<String> _excluded = {'音Mad', '音乐现场', '翻唱', '学科科普', '运动综合'};
  static const Set<String> _preferred = {'MV', '音乐综合', '电台'};
  static final RegExp _separator = RegExp('[^a-zA-Z0-9_一-龥]+');
  static final RegExp _chinese = RegExp('[一-龥]+');

  /// Longest-shared-Chinese-run threshold.
  static const int minChineseRun = 4;

  /// The search keyword for [track].
  static String keyword(ImportedTrack track) =>
      track.artist.trim().isEmpty ? track.name.trim() : '${track.name.trim()} - ${track.artist.trim()}';

  /// Words of [text].
  static List<String> words(String text) =>
      text.toLowerCase().split(_separator).where((word) => word.isNotEmpty).toList();

  /// [hits] scored for [track], best first.
  static List<TrackMatch> rank(ImportedTrack track, List<VodArchive> hits) {
    final query = keyword(track);
    final trackWords = words(track.name);
    final artistWords = words(track.artist);
    final queryWords = words(query).toSet();
    final scored = <({TrackMatch match, int order})>[];
    for (final (order, hit) in hits.indexed) {
      if (_excluded.contains(hit.typeName)) continue;
      final diff = (hit.duration.inSeconds - track.duration.inSeconds).abs();
      final title = decodeHtmlEntities(hit.title.replaceAll(RegExp('<[^>]*>'), ''));
      final titleWords = words(title);
      final hasTrack = _containsRun(titleWords, trackWords);
      final hasArtist = _containsRun(titleWords, artistWords);
      int base;
      String reason;
      if (hasTrack && hasArtist) {
        base = 100000;
        reason = 'both';
      } else if (diff > 20) {
        continue;
      } else if (hasTrack || hasArtist) {
        base = 10;
        reason = 'one';
      } else if (queryWords.intersection(titleWords.toSet()).isNotEmpty) {
        base = 5;
        reason = 'word';
      } else if (_sharesChineseRun(query, title)) {
        base = 0;
        reason = 'chinese';
      } else {
        continue;
      }
      final preferred = _preferred.contains(hit.typeName) ? 1000 : 0;
      final plays = hit.stat.views > 0 ? math.log(hit.stat.views) / math.ln10 : 0.0;
      final score = (base + preferred - diff + plays * 5).round();
      scored.add((match: TrackMatch(archive: hit, score: score, reason: reason), order: order));
    }
    scored.sort((a, b) {
      final byScore = b.match.score.compareTo(a.match.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    return [for (final entry in scored) entry.match];
  }

  /// The best of [hits] for [track], or null.
  static TrackMatch? best(ImportedTrack track, List<VodArchive> hits) => rank(track, hits).firstOrNull;

  /// Whether [run] appears in [words] consecutively (KMP); an empty run
  /// always does.
  static bool _containsRun(List<String> words, List<String> run) {
    if (run.isEmpty) return true;
    if (run.length > words.length) return false;
    final prefix = List<int>.filled(run.length, 0);
    for (var i = 1, length = 0; i < run.length; i++) {
      while (length > 0 && run[i] != run[length]) {
        length = prefix[length - 1];
      }
      if (run[i] == run[length]) length++;
      prefix[i] = length;
    }
    for (var i = 0, j = 0; i < words.length;) {
      if (words[i] == run[j]) {
        i++;
        j++;
        if (j == run.length) return true;
      } else if (j > 0) {
        j = prefix[j - 1];
      } else {
        i++;
      }
    }
    return false;
  }

  static bool _sharesChineseRun(String a, String b) {
    final x = _chinese.allMatches(a).map((m) => m.group(0)).join();
    final y = _chinese.allMatches(b).map((m) => m.group(0)).join();
    var previous = List<int>.filled(y.length + 1, 0);
    for (var i = 1; i <= x.length; i++) {
      final current = List<int>.filled(y.length + 1, 0);
      for (var j = 1; j <= y.length; j++) {
        if (x[i - 1] == y[j - 1]) {
          current[j] = previous[j - 1] + 1;
          if (current[j] >= minChineseRun) return true;
        }
      }
      previous = current;
    }
    return false;
  }
}

/// Progress of an import.
@immutable
final class ImportProgress {
  /// Creates the progress.
  const new({required this.done, required this.total, required this.matched, this.current});

  /// Songs handled.
  final int done;

  /// Songs in the playlist.
  final int total;

  /// Songs matched so far.
  final int matched;

  /// The song handled last.
  final ImportedTrack? current;
}

/// The outcome of an import.
@immutable
final class ImportResult {
  /// Creates the result.
  const new({required this.matched, required this.unmatched, this.cancelled = false});

  /// Songs and their archives, playlist order.
  final List<({ImportedTrack track, TrackMatch match})> matched;

  /// Songs nothing fit (or whose search failed).
  final List<ImportedTrack> unmatched;

  /// Stopped before the end.
  final bool cancelled;
}

/// Matches an imported playlist song by song, one search every [interval]
/// (the bmsc reference's pace; search answers -412 when hurried).
final class PlaylistImporter {
  /// Creates the importer; [search] is the video search (first page).
  new({
    required this.search,
    this.interval = const Duration(milliseconds: 1200),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  /// Video search.
  final Future<List<VodArchive>> Function(String keyword) search;

  /// Pause between searches.
  final Duration interval;

  final Future<void> Function(Duration) _sleep;

  /// Runs the import; [isCancelled] is checked before each song.
  Future<ImportResult> run(
    List<ImportedTrack> tracks, {
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final matched = <({ImportedTrack track, TrackMatch match})>[];
    final unmatched = <ImportedTrack>[];
    for (final (index, track) in tracks.indexed) {
      if (isCancelled?.call() ?? false) {
        return ImportResult(matched: matched, unmatched: [...unmatched, ...tracks.skip(index)], cancelled: true);
      }
      if (index > 0) await _sleep(interval);
      TrackMatch? best;
      try {
        best = TrackMatcher.best(track, await search(TrackMatcher.keyword(track)));
      } on SiteError {
        best = null;
      }
      if (best == null) {
        unmatched.add(track);
      } else {
        matched.add((track: track, match: best));
      }
      onProgress?.call(ImportProgress(done: index + 1, total: tracks.length, matched: matched.length, current: track));
    }
    return ImportResult(matched: matched, unmatched: unmatched);
  }
}
