import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';

/// Rooms in a [TvGrid] (pure_live_TV's room grids):
///
/// - OK opens the room with the grid's rooms as its channel list; back from
///   the room, the focus lands on the room shown last (after switching
///   channels) or on the card that was opened;
/// - a held OK or the menu key opens the card dialog ([showTvRoomDialog],
///   docs/ui/compare/U.15a c9, c10) with [actions];
/// - the platform chip shows in lists that mix platforms ([showPlatform]);
/// - columns follow the text size like pure_live_TV's (four, fewer as the
///   text grows), the gaps are the grid-spacing settings.
class TvRoomGrid extends ConsumerStatefulWidget {
  /// Creates the grid.
  const new({
    required this.rooms,
    this.onEndReached,
    this.onLeaveUp,
    this.onOpen,
    this.actions,
    this.detail,
    this.numbered = false,
    this.showPlatform = false,
    this.showFollowed = true,
    super.key,
  });

  /// The rooms, in order.
  final List<LiveRoom> rooms;

  /// The focus reached the last two rows: load more.
  final VoidCallback? onEndReached;

  /// Up on the first row; when null the focus moves by geometry.
  final VoidCallback? onLeaveUp;

  /// Opens a room; null opens the TV room ([openTvRoom]) with [rooms] as its
  /// list. Completes with the room shown last.
  final Future<LiveRoom?> Function(LiveRoom room, int index)? onOpen;

  /// The page's own actions in the card dialog (history: delete the entry).
  final List<TvRoomAction> Function(LiveRoom room)? actions;

  /// The detail of a card (history: when it was watched).
  final String? Function(LiveRoom room)? detail;

  /// Numbers the cards (IPTV channel lists).
  final bool numbered;

  /// Shows each card's platform (lists that mix platforms, U.15a c7).
  final bool showPlatform;

  /// Marks followed rooms with a heart (not on the follows page itself).
  final bool showFollowed;

  @override
  ConsumerState<TvRoomGrid> createState() => TvRoomGridState();
}

/// The room grid's state: [enter] and [focusIndex] put the focus on a card.
class TvRoomGridState extends ConsumerState<TvRoomGrid> {
  final GlobalKey<TvGridState> _grid = GlobalKey();

  /// Focuses the card focused last, else the first; false when empty.
  bool enter() => _grid.currentState?.enter() ?? false;

  /// Focuses card [index].
  bool focusIndex(int index) => _grid.currentState?.focusIndex(index) ?? false;

  Future<void> _open(LiveRoom room, int index) async {
    final open = widget.onOpen;
    final shown = open != null ? await open(room, index) : await openTvRoom(room, playlist: widget.rooms);
    if (!mounted) return;
    final back = shown == null ? index : widget.rooms.indexWhere(shown.hasSameIdentity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusIndex(back < 0 ? index : back);
    });
  }

  void _menu(LiveRoom room) {
    unawaited(
      showTvRoomDialog(
        context,
        store: ref.read(storeProvider),
        room: room,
        actions: widget.actions?.call(room) ?? const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final policy = watchAudiencePolicy(ref);
    final followed = ref.watch(tvFollowKeysProvider).value ?? const <String>{};
    final columns = tvRoomColumns(watchSetting(ref, Settings.textScaleFactor));
    final crossSpacing = scale(watchSetting(ref, Settings.crossAxisSpacing) + 26);
    final mainSpacing = scale(watchSetting(ref, Settings.mainAxisSpacing) + 26);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The card's 16:9 cover over its two lines sets the cell's shape.
        final width = (constraints.maxWidth - scale.px(24) - crossSpacing * (columns - 1)) / columns;
        return TvGrid(
          key: _grid,
          itemCount: widget.rooms.length,
          columns: columns,
          aspectRatio: width > 0 ? width / TvRoomCard.heightFor(width, scale) : 1.2,
          crossSpacing: crossSpacing,
          mainSpacing: mainSpacing,
          onEndReached: widget.onEndReached,
          onLeaveUp: widget.onLeaveUp,
          itemBuilder: (context, index, node, onKey) {
            final room = widget.rooms[index];
            return TvRoomCard(
              key: ValueKey('tv-room-${room.identityKey}'),
              data: policy.cardOf(room),
              focusNode: node,
              onKey: onKey,
              followed: widget.showFollowed && followed.contains(room.identityKey),
              showPlatform: widget.showPlatform,
              channelNumber: widget.numbered ? index + 1 : null,
              detail: widget.detail?.call(room),
              onTap: () => unawaited(_open(room, index)),
              onLongPress: () => _menu(room),
            );
          },
        );
      },
    );
  }
}

/// The identity keys of the follows (the followed chip on cards).
final StreamProvider<Set<String>> tvFollowKeysProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(storeProvider).follows.watchAll().map((rooms) => {for (final room in rooms) room.identityKey}),
);
