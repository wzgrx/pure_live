/// FLT-4 similarity, written for v4 to replace fuzzywuzzy (GPL-2.0-only,
/// ADR 0006): a partial ratio. The shorter text is compared with every
/// window of the same length in the longer one; each comparison scores
/// `100 × LCS / length` (the indel ratio of two equal-length strings); the
/// best window wins. Texts are compared as Unicode code points, cut to
/// [maxLength].
///
/// Against fuzzywuzzy's `partialRatio` it scores every window rather than
/// only those aligned to matching blocks, so a score is never lower; the
/// README records the review.
int partialRatio(String a, String b) {
  final left = _runes(a);
  final right = _runes(b);
  if (left.isEmpty || right.isEmpty) return 0;
  final (shorter, longer) = left.length <= right.length ? (left, right) : (right, left);
  return (100 * _bestWindow(shorter, longer, shorter.length) / shorter.length).round();
}

/// Whether [partialRatio] of [a] and [b] reaches [threshold], stopping early.
bool isSimilar(String a, String b, int threshold) {
  if (a == b) return a.isNotEmpty;
  final left = _runes(a);
  final right = _runes(b);
  if (left.isEmpty || right.isEmpty) return false;
  final (shorter, longer) = left.length <= right.length ? (left, right) : (right, left);
  // round(100 × lcs / m) >= threshold  ⇔  lcs >= (threshold − 0.5) × m / 100.
  final needed = ((threshold - 0.5) * shorter.length / 100).ceil();
  // The LCS against the whole longer text bounds every window's.
  if (_lcs(shorter, longer, 0, longer.length) < needed) return false;
  return _bestWindow(shorter, longer, needed) >= needed;
}

/// Longest text compared, in code points.
const maxLength = 256;

List<int> _runes(String text) {
  final runes = text.trim().runes.toList();
  return runes.length > maxLength ? runes.sublist(0, maxLength) : runes;
}

/// The best LCS of [shorter] against a window of [longer] of the same
/// length; stops once [enough] is reached.
int _bestWindow(List<int> shorter, List<int> longer, int enough) {
  final m = shorter.length;
  var best = 0;
  for (var start = 0; start + m <= longer.length; start++) {
    final score = _lcs(shorter, longer, start, start + m);
    if (score > best) best = score;
    if (best >= enough || best == m) break;
  }
  return best;
}

/// Length of the longest common subsequence of [pattern] and
/// `text[start, end)`: bit-parallel (Hyyrö) for patterns up to 62 code
/// points, dynamic programming beyond.
int _lcs(List<int> pattern, List<int> text, int start, int end) {
  final m = pattern.length;
  if (m <= 62) {
    final masks = <int, int>{};
    for (var i = 0; i < m; i++) {
      masks[pattern[i]] = (masks[pattern[i]] ?? 0) | (1 << i);
    }
    final all = (1 << m) - 1;
    var v = all;
    for (var j = start; j < end; j++) {
      final u = v & (masks[text[j]] ?? 0);
      v = ((v + u) | (v - u)) & all;
    }
    return m - _popCount(v);
  }
  var previous = List<int>.filled(end - start + 1, 0);
  var current = List<int>.filled(end - start + 1, 0);
  for (var i = 0; i < m; i++) {
    for (var j = start; j < end; j++) {
      final k = j - start + 1;
      current[k] = pattern[i] == text[j]
          ? previous[k - 1] + 1
          : (previous[k] > current[k - 1] ? previous[k] : current[k - 1]);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[end - start];
}

int _popCount(int value) {
  var count = 0;
  var rest = value;
  while (rest != 0) {
    rest &= rest - 1;
    count++;
  }
  return count;
}
