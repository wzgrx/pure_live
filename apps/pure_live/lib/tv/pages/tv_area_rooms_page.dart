import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/pages/tv_popular_pane.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// An area's rooms on the TV (arguments `[LiveSite, LiveArea]`, the phone's
/// `RoutePath.kAreaRooms`): the shared area feed (`AreaRoomSource`, M12.2)
/// in a room grid under the sub-page header (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c13: the
/// area and its platform, the follow button on the right, no "返回"
/// button). The focus starts on the first room once they arrive; Back
/// leaves.
class TvAreaRoomsPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<TvAreaRoomsPage> createState() => _TvAreaRoomsPageState();
}

class _TvAreaRoomsPageState extends ConsumerState<TvAreaRoomsPage> {
  final GlobalKey<TvRoomGridState> _grid = GlobalKey();
  final FocusNode _follow = FocusNode(debugLabel: 'area follow');
  RoomFeed? _feed;
  LiveArea? _area;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    final arguments = widget.route.arguments;
    if (arguments case [final LiveSite site, final LiveArea area]) {
      _area = area;
      final services = ref.read(appServicesProvider);
      final settings = services.store.settings;
      final probe = ref.read(networkProbeProvider);
      final feed = _feed = RoomFeed(
        platform: site.id,
        source: AreaRoomSource(areaRoomLoader(site, area), areaName: area.areaName),
        visible: (room) =>
            settings.get(Settings.showUnplayableInDiscover) ||
            !cannotPlayHere(room, signedIn: signedInOn(services.cookies, room.platform)),
        maxRooms: 5000,
        // I03.2 c1: offline and mobile data, as on the phone.
        precheck: () => MobileDataNotice.precheck(probe),
      )..addListener(_loaded);
      unawaited(feed.open(count: tvPageSize));
    }
  }

  void _loaded() {
    final feed = _feed;
    if (_focused || feed == null || feed.rooms.isEmpty) return;
    _focused = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _grid.currentState?.enter();
    });
  }

  @override
  void dispose() {
    _feed?.removeListener(_loaded);
    _feed?.dispose();
    _follow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final feed = _feed;
    final area = _area;
    final followed = ref.watch(followedAreaKeysProvider).value ?? const <String>{};
    return Scaffold(
      backgroundColor: palette.background,
      body: TvBackground(
        child: feed == null || area == null
            ? TvStatusView(
                icon: TvIcons.loadFailed,
                title: i18n('get_room_info_failed_retry'),
                subtitle: i18n('tv_room_switch_hint'),
              )
            : Padding(
                padding: EdgeInsets.fromLTRB(scale.px(36), scale.px(28), scale.px(36), 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: scale.px(12)),
                      child: TvPageHeader(
                        title: areaDisplayName(area),
                        subtitle: platformName(area.platform),
                        actions: [
                          TvButton(
                            key: const ValueKey('tv-area-follow'),
                            focusNode: _follow,
                            icon: followed.contains(area.identityKey) ? TvIcons.followedArea : TvIcons.followArea,
                            label: i18n(followed.contains(area.identityKey) ? 'tv_area_followed' : 'tv_area_follow'),
                            selected: followed.contains(area.identityKey),
                            onTap: () => unawaited(toggleAreaFollow(context, ref, area)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TvFeedGrid(
                        feed: feed,
                        gridKey: _grid,
                        onLeaveUp: _follow.requestFocus,
                        emptyHint: 'tv_empty_area',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
