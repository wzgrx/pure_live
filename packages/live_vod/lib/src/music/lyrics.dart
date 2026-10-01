import 'package:live_vod/src/music/third_party.dart';
import 'package:live_vod/src/store.dart';
import 'package:meta/meta.dart';

/// One timed lyric line.
@immutable
final class LyricLine {
  /// Creates a line.
  const new({required this.start, required this.text, this.end});

  /// When it starts (after the file's offset).
  final Duration start;

  /// When it ends, when the format says (rangotec's `[start,end]`).
  final Duration? end;

  /// Text; empty for an instrumental gap.
  final String text;
}

/// A parsed LRC file.
@immutable
final class LyricDocument {
  /// Creates a document.
  const new({required this.lines, this.title = '', this.artist = '', this.album = ''});

  /// Lines by start time.
  final List<LyricLine> lines;

  /// `[ti:]`.
  final String title;

  /// `[ar:]`.
  final String artist;

  /// `[al:]`.
  final String album;

  /// Whether it has any timed text.
  bool get isEmpty => lines.every((line) => line.text.isEmpty);

  /// The index of the line showing at [position], or -1 before the first.
  int indexAt(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lines[middle].start <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }
}

/// LRC parsing and the checks that keep a wrong song's lyric out (pure_live_TV
/// `b9d2f739` `music_lyric_service.dart`, rewritten as a parser).
///
/// Formats read: `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, `[mm:ss:xx]`,
/// `[hh:mm:ss.xxx]`, several stamps on one line, and rangotec's
/// `[mm:ss:mmm,mm:ss:mmm]` start-end pairs; `[offset:±ms]` moves every line
/// (positive shows lines earlier). The TV client kept the text and turned
/// stamps into `[mm:ss.xx]` with a regex that did not match rangotec's
/// pairs, so every rangotec lyric was dropped, and it required the text to
/// contain `[00:`, dropping lyrics that start after the first minute.
abstract final class Lrc {
  static final RegExp _stamp = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?::(\d{1,2}))?(?:[.:](\d{1,3}))?(?:,(\d{1,3}):(\d{1,2})[.:](\d{1,3}))?\]',
  );
  static final RegExp _tag = RegExp(r'^\[([a-zA-Z#]+):([^\]]*)\]\s*$');

  /// Parses [text]; lines without a stamp are ignored.
  static LyricDocument parse(String text) {
    final tags = <String, String>{};
    final raw = <({Duration start, Duration? end, String text})>[];
    for (final source in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final line = source.trim();
      if (line.isEmpty) continue;
      final tag = _tag.firstMatch(line);
      if (tag != null) {
        tags[tag.group(1)!.toLowerCase()] = tag.group(2)!.trim();
        continue;
      }
      final stamps = <({Duration start, Duration? end})>[];
      var rest = line;
      while (true) {
        final match = _stamp.matchAsPrefix(rest);
        if (match == null) break;
        stamps.add(_times(match));
        rest = rest.substring(match.end);
      }
      if (stamps.isEmpty) continue;
      final words = rest.trim();
      for (final stamp in stamps) {
        raw.add((start: stamp.start, end: stamp.end, text: words));
      }
    }
    final offset = Duration(milliseconds: int.tryParse(tags['offset'] ?? '') ?? 0);
    Duration shift(Duration time) {
      final moved = time - offset;
      return moved.isNegative ? Duration.zero : moved;
    }

    final lines = [
      for (final line in raw)
        LyricLine(start: shift(line.start), end: line.end == null ? null : shift(line.end!), text: line.text),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return LyricDocument(lines: lines, title: tags['ti'] ?? '', artist: tags['ar'] ?? '', album: tags['al'] ?? '');
  }

  static ({Duration start, Duration? end}) _times(Match match) {
    Duration fraction(String? digits) {
      if (digits == null || digits.isEmpty) return Duration.zero;
      // 1–3 digits are tenths, hundredths or thousandths.
      return Duration(milliseconds: int.parse(digits.padRight(3, '0').substring(0, 3)));
    }

    final a = int.parse(match.group(1)!);
    final b = int.parse(match.group(2)!);
    final c = match.group(3);
    final fractionText = match.group(4);
    Duration start;
    if (c != null && fractionText != null) {
      // hh:mm:ss.xxx
      start = Duration(hours: a, minutes: b, seconds: int.parse(c)) + fraction(fractionText);
    } else if (c != null) {
      // mm:ss:xx (a colon before the fraction).
      start = Duration(minutes: a, seconds: b) + fraction(c);
    } else {
      start = Duration(minutes: a, seconds: b) + fraction(fractionText);
    }
    final endMinutes = match.group(5);
    final end = endMinutes == null
        ? null
        : Duration(minutes: int.parse(endMinutes), seconds: int.parse(match.group(6)!)) + fraction(match.group(7));
    return (start: start, end: end);
  }

  /// The song name inside a part title: decorations (`【…】`, `(…)`, `[…]`),
  /// part numbers (`P3.`, `03 `, `第3首`) removed (TV `cleanTitle`).
  static String cleanTitle(String title) {
    var text = title.trim();
    text = text.replaceAll(RegExp(r'【[^】]*】|\([^)]*\)|（[^）]*）|\[[^\]]*\]'), ' ').trim();
    text = text.replaceFirst(RegExp(r'^第\s*[0-9一二三四五六七八九十]{1,3}\s*[首曲集部]?\s*'), '');
    text = text.replaceFirst(RegExp(r'^p\s*\d{1,3}\s*[.、\-—_:：]?\s*', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^(?:\d{1,3}\s*[.、\-—_:：]\s*|0\d{1,2}\s+)'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? title.trim() : text;
  }

  static String _fold(String text) => text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// Whether [candidate] plausibly names the song [query]: equal or a prefix
  /// of each other after folding, or a Sørensen–Dice bigram similarity of at
  /// least 0.7 (TV `plausible`). Blank sides cannot be checked and pass.
  static bool plausible(String query, String candidate) {
    final a = _fold(query);
    final b = _fold(candidate);
    if (a.isEmpty || b.isEmpty) return true;
    if (a == b || a.startsWith(b) || b.startsWith(a)) return true;
    return dice(a, b) >= 0.7;
  }

  /// Sørensen–Dice coefficient of character bigrams.
  static double dice(String a, String b) {
    if (a == b) return 1;
    if (a.length < 2 || b.length < 2) return 0;
    final counts = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final gram = a.substring(i, i + 2);
      counts[gram] = (counts[gram] ?? 0) + 1;
    }
    var shared = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final gram = b.substring(i, i + 2);
      final count = counts[gram] ?? 0;
      if (count > 0) {
        counts[gram] = count - 1;
        shared++;
      }
    }
    return 2 * shared / (a.length + b.length - 2);
  }
}

/// What a lyric is looked up for.
@immutable
final class LyricQuery {
  /// Creates a query.
  const new({required this.title, this.artist = '', this.bvid = '', this.cid = 0, this.aid = 0});

  /// The part title (cleaned by [Lrc.cleanTitle] before searching).
  final String title;

  /// Artist hint (the uploader or the imported artist).
  final String artist;

  /// The archive, for the BGM source.
  final String bvid;

  /// The part.
  final int cid;

  /// The archive's aid.
  final int aid;
}

/// A source of lyric candidates.
typedef LyricSource = Future<List<LyricCandidate>> Function(LyricQuery query);

/// The lyric chain of music mode (TV `MusicLyricService`): the user's own
/// pick, then the stored hit, then each source in order (Bilibili BGM,
/// lrc.cx, rangotec, NetEase by default); the first candidate whose own
/// title fits the track and which has timed text wins. Hits are stored by
/// cleaned title; misses are remembered for the session only.
final class LyricLookup {
  /// Creates the chain.
  new({required this.sources, required this.store});

  /// Sources in order.
  final List<LyricSource> sources;

  /// Where picks and hits are kept.
  final VodKeyValueStore store;

  final Map<String, LyricDocument?> _session = {};

  static String _manualKey(String title) => 'music.lyric.manual.$title';
  static String _cacheKey(String title) => 'music.lyric.cache.$title';

  /// The lyric of [query], or null when no source has one that fits.
  Future<LyricDocument?> find(LyricQuery query) async {
    final title = Lrc.cleanTitle(query.title);
    if (title.isEmpty) return null;
    final manual = store.read(_manualKey(title));
    if (manual != null) return Lrc.parse(manual);
    if (_session.containsKey(title)) return _session[title];
    final stored = store.read(_cacheKey(title));
    if (stored != null) return _session[title] = Lrc.parse(stored);
    for (final source in sources) {
      List<LyricCandidate> candidates;
      try {
        candidates = await source(query);
      } on Exception {
        continue;
      }
      for (final candidate in candidates) {
        final document = accept(title, candidate);
        if (document == null) continue;
        await store.write(_cacheKey(title), candidate.lrc);
        return _session[title] = document;
      }
    }
    return _session[title] = null;
  }

  /// Every candidate of every source for the picker, verified, without
  /// duplicate texts; the current manual pick first.
  Future<List<({LyricCandidate candidate, LyricDocument document})>> candidates(LyricQuery query) async {
    final title = Lrc.cleanTitle(query.title);
    final out = <({LyricCandidate candidate, LyricDocument document})>[];
    final seen = <String>{};
    void add(LyricCandidate candidate) {
      final document = accept(title, candidate);
      if (document == null || !seen.add(candidate.lrc.trim())) return;
      out.add((candidate: candidate, document: document));
    }

    final manual = store.read(_manualKey(title));
    if (manual != null) add(LyricCandidate(source: 'manual', lrc: manual, title: title));
    for (final source in sources) {
      try {
        (await source(query)).forEach(add);
      } on Exception {
        continue;
      }
    }
    return out;
  }

  /// Makes [lrc] the lyric of [title] from now on.
  Future<void> pick(String title, String lrc) async {
    final key = Lrc.cleanTitle(title);
    await store.write(_manualKey(key), lrc);
    _session.remove(key);
  }

  /// Forgets the pick of [title]; the chain answers again.
  Future<void> clearPick(String title) async {
    final key = Lrc.cleanTitle(title);
    await store.remove(_manualKey(key));
    _session.remove(key);
  }

  /// [candidate] parsed when it fits [title]: its own title (from the
  /// source or the `[ti:]` tag) must be plausible, and it must have timed
  /// text.
  static LyricDocument? accept(String title, LyricCandidate candidate) {
    if (candidate.title.isNotEmpty && !Lrc.plausible(title, candidate.title)) return null;
    final document = Lrc.parse(candidate.lrc);
    if (document.isEmpty) return null;
    if (document.title.isNotEmpty && !Lrc.plausible(title, document.title)) return null;
    return document;
  }
}
