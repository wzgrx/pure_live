import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_artwork.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The area pictures learned from every catalogue (one per app run).
final Provider<AreaPictures> areaPicturesProvider = Provider((ref) {
  final pictures = AreaPictures(ref.watch(storeProvider).meta);
  // Best effort: borrowed pictures appear once the saved ones are read.
  pictures.load().ignore();
  return pictures;
});

/// The areas page's catalogues, one per platform, kept while the app runs
/// (I03.2 c2, like the popular page's): back on the tab, the catalogues
/// already loaded show at once.
final class AreaCatalogs {
  /// Creates the catalogues; [_create] makes the one of a platform.
  new(this._create);

  final AreaCatalog Function(String platform) _create;
  final Map<String, AreaCatalog> _catalogs = {};

  /// The catalogue of [platform].
  AreaCatalog of(String platform) => _catalogs[platform] ??= _create(platform);

  /// Releases the catalogues of platforms not in [platforms].
  void retain(Iterable<String> platforms) {
    final kept = platforms.toSet();
    for (final id in _catalogs.keys.where((id) => !kept.contains(id)).toList()) {
      _catalogs.remove(id)!.dispose();
    }
  }

  /// Releases every catalogue.
  void dispose() {
    for (final catalog in _catalogs.values) {
      catalog.dispose();
    }
    _catalogs.clear();
  }
}

/// The catalogues (I03.2 c2). Offline, a load fails with [Offline] without
/// asking the platform (c1; the mobile-data notice is the rooms lists').
final Provider<AreaCatalogs> areaCatalogsProvider = Provider((ref) {
  final sites = ref.watch(sitesProvider);
  final pictures = ref.watch(areaPicturesProvider);
  final probe = ref.watch(networkProbeProvider);
  final catalogs = AreaCatalogs(
    (id) => AreaCatalog(
      sites.of(id),
      pictures: pictures,
      precheck: () async {
        if (await probe() == NetworkKind.none) throw const Offline();
      },
    ),
  );
  ref.onDispose(catalogs.dispose);
  return catalogs;
});

/// The name of [area] to show: its name, else "unnamed area" (3.x).
String areaDisplayName(LiveArea area) {
  final name = area.areaName.trim();
  return name.isEmpty ? i18n('unnamed_area') : name;
}

/// Height of an area card [itemWidth] wide (docs/A-界面设计/A09-浏览界面/A09.4-分区 c3): the
/// square picture and one line (the name, 40 high) or two (name and
/// category, 72 high, 3.x `areaCardGridMainAxisExtent`), growing with the
/// text scale.
double areaCardExtent(BuildContext context, double itemWidth, {required bool twoLines}) {
  final scaler = MediaQuery.textScalerOf(context);
  final titleHeight = scaler.scale(12) * 1.3;
  if (!twoLines) return itemWidth + math.max(40, titleHeight + 22);
  final subtitleHeight = scaler.scale(12) * 1.3;
  return itemWidth + math.max(72, titleHeight + subtitleHeight + 32);
}

/// "platform · category" under an area's name (U.4d, U.4f).
String areaPlatformAndCategory(LiveArea area) =>
    [platformName(area.platform), if (area.typeName.trim() case final type when type.isNotEmpty) type].join(' · ');

/// The dialog of an area card (long press or right click): the room card's
/// dialog of U.4a with the area's name, "platform · category" and "关注分区",
/// or "取消关注" for a followed area, which asks first (U.4d X3 as changed
/// by the coordinator on 2026-10-01: one component for one action, UI_PLAN
/// §3 rule 7; it was a small menu in the confirmed design).
Future<void> showAreaDialog(BuildContext context, WidgetRef ref, LiveArea area) async {
  final picked = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final followed = ref.watch(followedAreaKeysProvider).value?.contains(area.identityKey) ?? false;
        return CardDialog(
          key: const ValueKey('area-menu'),
          leading: PlatformLogo(area.platform),
          title: areaDisplayName(area),
          subtitle: areaPlatformAndCategory(area),
          closeLabel: i18n('close'),
          actions: [
            [
              CardDialogAction(
                key: const ValueKey('area-menu-follow'),
                icon: followed ? AppIcons.unfollowArea : AppIcons.followArea,
                label: i18n(followed ? 'unfollow' : 'area_follow'),
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ],
        );
      },
    ),
  );
  if (picked != true || !context.mounted) return;
  await toggleAreaFollow(context, ref, area);
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

/// Asks whether to unfollow [name]: the room's dialog, its button saying
/// "取消关注" (U.4e as changed by the coordinator on 2026-10-01, U.1d D2;
/// 3.x's said "确认").
Future<bool> confirmUnfollow(BuildContext context, String name) => confirmUnfollowRoom(context, name: name);

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
