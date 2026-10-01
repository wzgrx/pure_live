import 'package:live_core/live_core.dart';

/// The quality to start with (3.x `_setDefaultResolution`; the live room
/// and every multi-view cell): the one named like the preference, else the
/// same relative position in the list (3.x's five names from best to
/// worst). 3.x's multi-view always took the best one.
int defaultQualityIndex(List<LivePlayQuality> qualities, String preferred) {
  if (qualities.isEmpty) return 0;
  final exact = qualities.indexWhere((q) => q.quality == preferred);
  if (exact >= 0) return exact;
  const names = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
  final level = names.indexOf(preferred);
  if (level < 0) return 0;
  final ratio = level / (names.length - 1);
  return (ratio * (qualities.length - 1)).round().clamp(0, qualities.length - 1);
}
