import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// Followed areas (spec/product.md F-FAV-07, merged into 发现).
final StreamProvider<List<FollowedArea>> followedAreasProvider = StreamProvider<List<FollowedArea>>(
  (ref) => ref.watch(storeProvider).followAreas.watchAll(),
);

/// The stored form of [area] on [platform].
FollowedArea followedAreaOf(String platform, Area area, {String categoryName = ''}) => FollowedArea(
  platform: platform,
  areaId: area.id,
  areaName: area.name,
  typeName: categoryName,
  areaPic: area.icon?.toString(),
);

/// Whether [area] is followed.
bool isAreaFollowed(List<FollowedArea> followed, String platform, Area area) =>
    followed.any((f) => f.platform == platform && f.areaId == area.id);

/// Followed areas of [platform] found in its current category list; areas the
/// platform no longer lists are skipped.
List<(Area, String)> followedAreasIn(List<FollowedArea> followed, String platform, List<Category> categories) => [
  for (final f in followed.where((f) => f.platform == platform))
    for (final category in categories)
      for (final area in category.areas)
        if (area.id == f.areaId) (area, category.name),
];
