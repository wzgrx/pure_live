import 'package:live_core/live_core.dart';
import 'package:live_record/src/settings.dart';
import 'package:meta/meta.dart';

String _normalize(String label) => label.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

/// Orders [offered] for recording (spec §4.2): de-duplicated by id, best first
/// by rank, the quality whose label matches [preference] exactly (ignoring
/// case, whitespace, `_` and `-`) moved to the front; without an exact match
/// the one at the preference's relative position among the five tiers.
List<Quality> orderQualities(List<Quality> offered, RecordQuality preference) {
  final seen = <String>{};
  final unique = [
    for (final quality in offered)
      if (seen.add(quality.id)) quality,
  ];
  if (unique.isEmpty) return unique;
  final ranked = unique.any((quality) => quality.rank != unique.first.rank)
      ? ([...unique]..sort((a, b) => b.rank.compareTo(a.rank)))
      : unique;
  final wanted = _normalize(preference.label);
  var index = ranked.indexWhere((quality) => _normalize(quality.label) == wanted);
  if (index < 0) {
    final tiers = RecordQuality.values.length - 1;
    index = ((preference.index / tiers) * (ranked.length - 1)).round();
  }
  final chosen = ranked[index];
  return [chosen, ...ranked.where((quality) => quality.id != chosen.id)];
}

/// Line identity for "same line" decisions: the adapter's stable line id.
bool sameLine(StreamLine a, StreamLine b) =>
    a.lineId == b.lineId || (a.url.scheme == b.url.scheme && a.url.host == b.url.host && a.url.path == b.url.path);

/// The persisted position of a task among qualities and lines (spec §2, §4.3):
/// a quality id and a line index, never a URL.
@immutable
final class RecordCursor {
  /// Creates a cursor.
  const new({required this.qualityId, required this.lineIndex});

  /// Restores a persisted cursor.
  factory fromJson(Map<String, Object?> json) =>
      RecordCursor(qualityId: json['qualityId']! as String, lineIndex: (json['lineIndex']! as num).toInt());

  /// Quality request id.
  final String qualityId;

  /// Line index within that quality's recordable lines.
  final int lineIndex;

  /// JSON form.
  Map<String, Object?> toJson() => {'qualityId': qualityId, 'lineIndex': lineIndex};

  @override
  bool operator ==(Object other) =>
      other is RecordCursor && other.qualityId == qualityId && other.lineIndex == lineIndex;

  @override
  int get hashCode => Object.hash(qualityId, lineIndex);

  @override
  String toString() => 'RecordCursor($qualityId #$lineIndex)';
}

/// Walks qualities and lines on failure (spec §4.3): the next line of the
/// same quality, then the first line of the next quality (cyclic); once every
/// position failed it reports exhaustion and starts again at the original
/// quality's first line.
final class LineCursor {
  /// Creates a cursor over [qualities] (in [orderQualities] order) starting at [start].
  new(this.qualities, {RecordCursor? start}) {
    final index = start == null ? 0 : qualities.indexWhere((quality) => quality.id == start.qualityId);
    _origin = index < 0 ? 0 : index;
    _quality = _origin;
    _line = index < 0 ? 0 : (start?.lineIndex ?? 0);
  }

  /// Qualities in order of preference.
  final List<Quality> qualities;

  late final int _origin;
  late int _quality;
  late int _line;
  var _failures = 0;
  var _wrapped = false;

  /// The quality to resolve (null when the platform offered none).
  Quality? get quality => qualities.isEmpty ? null : qualities[_quality];

  /// The line index within [quality]'s recordable lines.
  int get lineIndex => _line;

  /// The persisted form.
  RecordCursor? get position => quality == null ? null : RecordCursor(qualityId: quality!.id, lineIndex: _line);

  /// Failures since the last success.
  int get failures => _failures;

  /// The current line failed; moves on. Returns false once every quality has
  /// been tried since the last success (then the cursor is back at the origin).
  bool fail({required int linesInQuality}) {
    _failures++;
    if (_line + 1 < linesInQuality) {
      _line++;
      return true;
    }
    return _nextQuality();
  }

  /// The current quality has no recordable line at all.
  bool skipQuality() {
    _failures++;
    return _nextQuality();
  }

  bool _nextQuality() {
    _line = 0;
    if (qualities.length <= 1) {
      _wrapped = true;
    } else {
      _quality = (_quality + 1) % qualities.length;
      if (_quality == _origin) _wrapped = true;
    }
    if (_wrapped) {
      _wrapped = false;
      _quality = _origin;
      _failures = 0;
      return false;
    }
    return true;
  }

  /// The current line worked.
  void succeed() {
    _failures = 0;
  }
}
