import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/discover/discover_refresh.dart';
import 'package:pure_live_app/features/discover/followed_areas.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Rooms of one area.
class AreaPage extends ConsumerWidget {
  const new({required this.platform, required this.area, super.key});

  /// Platform id.
  final String platform;

  /// The area; null when the page was restored without it.
  final Area? area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = this.area;
    final followed = area != null && isAreaFollowed(ref.watch(followedAreasProvider).value ?? const [], platform, area);
    return Scaffold(
      appBar: AppBar(
        title: Text(area?.name ?? ''),
        actions: [
          if (area != null)
            IconButton(
              tooltip: followed ? t.discover.unfollowArea : t.discover.followArea,
              icon: Icon(followed ? Icons.star : Icons.star_border),
              onPressed: () {
                final store = ref.read(storeProvider).followAreas;
                final entry = followedAreaOf(platform, area);
                unawaited(followed ? store.unfollow(entry) : store.follow(entry));
              },
            ),
        ],
      ),
      body: area == null
          ? MessageView(title: t.discover.areaGone, actionLabel: t.common.back, onAction: () => context.pop())
          : RoomGrid(query: AreaQuery(platform, area), refreshOn: discoverRefreshProvider),
    );
  }
}
