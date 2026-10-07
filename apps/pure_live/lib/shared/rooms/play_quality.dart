import 'package:live_core/live_core.dart';

/// The quality to start with (3.x `_setDefaultResolution`; the live room
/// and every multi-view cell): the one named like the preference, else the
/// same relative position in the list (3.x's five names from best to
/// worst). 3.x's multi-view always took the best one.
///
/// With [preferH264] (the "优先 H.264" setting) a name match whose codec
/// hint is HEVC is passed over while the room offers anything else: the
/// relative position decides, and should it land on HEVC too the nearest
/// other quality is taken (the better one on a tie). HEVC is then played
/// only when picked by hand or when nothing else is on offer (G01.3).
int defaultQualityIndex(List<LivePlayQuality> qualities, String preferred, {bool preferH264 = false}) {
  if (qualities.isEmpty) return 0;
  bool hevc(int index) => qualities[index].codec == 'hevc';
  final exact = qualities.indexWhere((q) => q.quality == preferred);
  final skip = exact >= 0 && preferH264 && hevc(exact) && qualities.any((q) => q.codec != 'hevc');
  if (exact >= 0 && !skip) return exact;
  final position = _relativePosition(qualities.length, preferred);
  if (!skip || !hevc(position)) return position;
  for (var distance = 1; distance < qualities.length; distance++) {
    for (final index in [position - distance, position + distance]) {
      if (index >= 0 && index < qualities.length && !hevc(index)) return index;
    }
  }
  return position;
}

/// The index at [preferred]'s place among 3.x's five names, scaled to
/// [length] qualities; the first for a name not among them.
int _relativePosition(int length, String preferred) {
  const names = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
  final level = names.indexOf(preferred);
  if (level < 0) return 0;
  final ratio = level / (names.length - 1);
  return (ratio * (length - 1)).round().clamp(0, length - 1);
}
