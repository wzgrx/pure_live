import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_artwork.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The area pictures learned from every catalogue (one per app run).
final Provider<AreaPictures> areaPicturesProvider = Provider((ref) {
  final pictures = AreaPictures(ref.watch(storeProvider).meta);
  // Best effort: borrowed pictures appear once the saved ones are read.
  pictures.load().ignore();
  return pictures;
});

/// The name of [area] to show: its name, else "unnamed area" (3.x).
String areaDisplayName(LiveArea area) {
  final name = area.areaName.trim();
  return name.isEmpty ? i18n('unnamed_area') : name;
}

/// Columns of the area grid at [width] (3.x: 3, 5, 7 or 9).
int areaGridColumns(double width) => width > 1280 ? 9 : (width > 960 ? 7 : (width > 640 ? 5 : 3));

/// Height of an area card [itemWidth] wide: the square picture and two text
/// lines that grow with the text scale (3.x `areaCardGridMainAxisExtent`).
double areaCardExtent(BuildContext context, double itemWidth) {
  final scaler = MediaQuery.textScalerOf(context);
  final titleHeight = scaler.scale(12) * 1.25;
  final subtitleHeight = scaler.scale(11) * 1.25;
  return itemWidth + math.max(72, titleHeight + subtitleHeight + 32);
}

/// Opens [area]: IPTV channels play directly, CC's official entries open in
/// the browser, other areas open their rooms (3.x `AreaCard.onTap`).
void openArea(WidgetRef ref, LiveArea area) {
  final site = ref.read(sitesProvider).maybeOf(area.platform);
  if (area.platform == SiteIds.iptv) {
    AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(
        platform: SiteIds.iptv,
        roomId: area.areaId,
        title: area.typeName,
        nick: area.areaName,
        avatar: area.areaPic,
        liveStatus: LiveStatus.live,
      ),
    ).ignore();
    return;
  }
  if (site == null) {
    AppNavigator.toast(i18n(SiteIds.isRetired(area.platform) ? 'platform_retired' : 'areas_platform_unavailable'));
    return;
  }
  AppNavigator.toCategoryDetail(site: site, category: area).ignore();
}

/// Follows or unfollows [area], asking before unfollowing (3.x
/// `FavoriteAreaFloatingButton`); tells the user what happened. Returns
/// whether the area is followed afterwards.
Future<bool> toggleAreaFollow(BuildContext context, WidgetRef ref, LiveArea area) async {
  final store = ref.read(storeProvider).followAreas;
  final name = areaDisplayName(area);
  try {
    if (!await store.contains(area)) {
      await store.add(area);
      AppNavigator.toast(i18n('areas_follow_done', args: {'name': name}));
      return true;
    }
    if (!context.mounted) return true;
    final confirmed = await confirmUnfollow(context, name);
    if (!confirmed) return true;
    await store.remove(area);
    AppNavigator.toast(i18n('areas_unfollow_done', args: {'name': name}));
    return false;
  } on Object {
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
    return await store.contains(area);
  }
}

/// Asks whether to unfollow [name] (3.x's dialog).
Future<bool> confirmUnfollow(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(i18n('unfollow')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(i18n('unfollow_message', args: {'name': name})),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(i18n('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n('confirm')),
          ),
        ],
      ),
    ) ??
    false;

/// The identities of the followed areas, updated on every change.
final StreamProvider<Set<String>> followedAreaKeysProvider = StreamProvider((ref) {
  final store = ref.watch(storeProvider).followAreas;
  return store.watchAll().map((areas) => {for (final area in areas) ?area.identityKey});
});

/// The followed areas in their saved order, updated on every change.
final StreamProvider<List<LiveArea>> followedAreasProvider = StreamProvider(
  (ref) => ref.watch(storeProvider).followAreas.watchAll(),
);

/// Reads the grid spacing settings (3.x `crossAxisSpacing`, `mainAxisSpacing`).
({double cross, double main}) gridSpacing(WidgetRef ref) =>
    (cross: watchSetting(ref, Settings.crossAxisSpacing), main: watchSetting(ref, Settings.mainAxisSpacing));
