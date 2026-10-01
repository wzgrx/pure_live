import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

/// Rooms in a [TvGrid] (pure_live_TV's room grids):
///
/// - OK opens the room with the grid's rooms as its channel list; back from
///   the room, the focus lands on the room shown last (after switching
///   channels) or on the card that was opened;
/// - a held OK opens the shared card menu (M12.2) with [actions];
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

  /// Extra card-menu actions of a room (history: delete the entry).
  final List<RoomMenuAction> Function(LiveRoom room)? actions;

  /// The detail of a card (history: when it was watched).
  final String? Function(LiveRoom room)? detail;

  /// Numbers the cards (IPTV channel lists).
  final bool numbered;

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

  void _menu(LiveRoom room, int index) {
    unawaited(
      showRoomMenu(
        context,
        store: ref.read(storeProvider),
        room: room,
        onOpen: () => unawaited(_open(room, index)),
        detail: widget.detail?.call(room),
        actions: widget.actions?.call(room) ?? const [],
      ),
    );
    tvFocusFirstInRoute();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final policy = watchAudiencePolicy(ref);
    final followed = ref.watch(tvFollowKeysProvider).value ?? const <String>{};
    final columns = tvRoomColumns(watchSetting(ref, Settings.textScaleFactor));
    return TvGrid(
      key: _grid,
      itemCount: widget.rooms.length,
      columns: columns,
      aspectRatio: tvRoomAspectRatio(columns),
      crossSpacing: scale(watchSetting(ref, Settings.crossAxisSpacing) + 18),
      mainSpacing: scale(watchSetting(ref, Settings.mainAxisSpacing) + 18),
      onEndReached: widget.onEndReached,
      onLeaveUp: widget.onLeaveUp,
      itemBuilder: (context, index, node, onKey) {
        final room = widget.rooms[index];
        return TvRoomCard(
          key: ValueKey('tv-room-${room.identityKey}'),
          data: policy.cardOf(room),
          focusNode: node,
          onKey: onKey,
          followed: followed.contains(room.identityKey),
          channelNumber: widget.numbered ? index + 1 : null,
          detail: widget.detail?.call(room),
          onTap: () => unawaited(_open(room, index)),
          onLongPress: () => _menu(room, index),
        );
      },
    );
  }
}

/// The identity keys of the follows (the followed chip on cards).
final StreamProvider<Set<String>> tvFollowKeysProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(storeProvider).follows.watchAll().map((rooms) => {for (final room in rooms) room.identityKey}),
);
