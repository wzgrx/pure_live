import 'package:live_core/live_core.dart';

/// The area of [categories] called [name] (a room only carries its area's
/// name): the area name first, then the short name; case and outer spaces
/// ignored. Null when the platform lists no such area.
LiveArea? findAreaByName(List<LiveCategory> categories, String name) {
  final wanted = name.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final areas = categories.expand((category) => category.children).toList();
  for (final area in areas) {
    if (area.areaName.trim().toLowerCase() == wanted) return area;
  }
  for (final area in areas) {
    if (area.shortName.trim().toLowerCase() == wanted) return area;
  }
  return null;
}
