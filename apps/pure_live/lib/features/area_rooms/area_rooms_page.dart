import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/area_rooms/follow_area_button.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The rooms of an area (3.x `lib/modules/area_rooms`).
///
/// Route: `RoutePath.kAreaRooms`; arguments `[LiveSite, LiveArea]` (3.x
/// crashed without them; here the page says the area is missing).
class AreaRoomsPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    if (route.arguments case [final LiveSite site, final LiveArea area]) {
      return AreaRoomsView(site: site, area: area);
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n('areas_title'))),
      body: AppStatusView(type: AppStatusType.error, title: i18n('area_rooms_missing_area')),
    );
  }
}

/// The rooms of [area] on [site] (docs/A-界面设计/A09-浏览界面/A09.5-分区房间): the area's name
/// with "platform · category" under it (c2) and the follow pill (c3) in the
/// app bar; the room cards of U.4a in the columns of UI_PLAN §5.3 (c7);
/// skeleton cards while loading (c8); on phones pull to refresh and more
/// rooms at the end, on desktops numbered pages with ← → (3.x); the jump
/// buttons at the bottom right (c4); the directory's explanation where the
/// platform has one.
class AreaRoomsView extends ConsumerStatefulWidget {
  /// Shows [area]'s rooms on [site].
  const new({required this.site, required this.area, this.loader, super.key});

  /// The platform.
  final LiveSite site;

  /// The area.
  final LiveArea area;

  /// Loads pages; null uses [areaRoomLoader] (tests pass their own).
  final RoomPageLoader? loader;

  @override
  ConsumerState<AreaRoomsView> createState() => _AreaRoomsViewState();
}

class _AreaRoomsViewState extends ConsumerState<AreaRoomsView> {
  late final RoomFeed _feed;
  late final StreamSubscription<Setting<Object>> _settings;
  late bool _showUnplayable;

  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    final probe = ref.read(networkProbeProvider);
    _showUnplayable = services.store.settings.get(Settings.showUnplayableInDiscover);
    // I03.2 c4: the setting changed while the page is open applies at once.
    _settings = services.store.settings.changes.listen((setting) {
      if (setting.key != Settings.showUnplayableInDiscover.key || !mounted) return;
      setState(() => _showUnplayable = services.store.settings.get(Settings.showUnplayableInDiscover));
      _feed.visibilityChanged();
    });
    _feed = RoomFeed(
      platform: widget.site.id,
      source: AreaRoomSource(widget.loader ?? areaRoomLoader(widget.site, widget.area), areaName: widget.area.areaName),
      // Rooms that cannot play here are hidden unless shown (UPGRADES 统一原则).
      visible: (room) =>
          _showUnplayable || !cannotPlayHere(room, signedIn: signedInOn(services.cookies, room.platform)),
      // 3.x kept up to 20000 rooms of a directory.
      maxRooms: 5000,
      // I03.2 c1: offline and mobile data, as on the popular page.
      precheck: () => MobileDataNotice.precheck(probe),
    );
  }

  void _showHidden() {
    setState(() => _showUnplayable = true);
    _feed.visibilityChanged();
  }

  @override
  void dispose() {
    unawaited(_settings.cancel());
    _feed.dispose();
    super.dispose();
  }

  String? get _notice {
    final site = widget.site;
    return site is LiveDirectoryNotice ? i18nOr((site as LiveDirectoryNotice).directoryNoticeKey, '') : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final area = widget.area;
    final category = area.typeName.trim();
    final platform = platformName(widget.site.id, fallback: widget.site.name);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              areaDisplayName(area),
              key: const ValueKey('area-rooms-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              category.isEmpty ? platform : '$platform · $category',
              key: const ValueKey('area-rooms-subtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [FollowAreaButton(area: area)],
      ),
      body: RoomFeedView(
        feed: _feed,
        keyPrefix: 'area-rooms',
        notice: _notice,
        openOnShow: true,
        empty: (
          icon: AppIcons.coverPlaceholder,
          title: i18n('empty_areas_room_title'),
          subtitle: ({required desktop}) => i18n('area_rooms_empty_hint'),
        ),
        hiddenNote: (count) => i18n('area_rooms_hidden_unplayable', args: {'count': '$count'}),
        onShowHidden: _showHidden,
      ),
    );
  }
}
