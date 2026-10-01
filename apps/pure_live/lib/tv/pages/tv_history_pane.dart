import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/history/history_sections.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';

/// The watch history, newest first.
final StreamProvider<List<LiveRoom>> tvHistoryProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(storeProvider).history.watchAll(),
);

/// Watch history (pure_live_TV `HistoryPage` over v4's history store): the
/// rooms newest first with when they were watched; the card menu can delete
/// one entry, the button above clears what is shown.
class TvHistoryPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvHistoryPane> createState() => _TvHistoryPaneState();
}

class _TvHistoryPaneState extends ConsumerState<TvHistoryPane> {
  final GlobalKey<TvRoomGridState> _grid = GlobalKey();
  final FocusNode _clear = FocusNode(debugLabel: 'history clear');

  @override
  void dispose() {
    _clear.dispose();
    super.dispose();
  }

  Future<void> _clearAll(List<LiveRoom> rooms) async {
    final confirmed = await showTvConfirm(
      context,
      title: i18n('tv_history_clear'),
      message: i18n('tv_history_clear_message', args: {'count': '${rooms.length}'}),
    );
    if (!confirmed) return;
    await ref.read(storeProvider).history.clear(rooms);
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final history = ref.watch(tvHistoryProvider);
    final rooms = history.value ?? const <LiveRoom>[];
    final now = DateTime.now();
    if (!history.hasValue) return TvMessage(busy: true, title: i18n('tv_loading'));
    if (rooms.isEmpty) return TvMessage(icon: Icons.history_rounded, title: i18n('tv_no_history'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(scale(20), scale(16), scale(20), 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i18n('tv_history_count', args: {'count': '${rooms.length}'}),
                  style: scale.style(22, color: palette.textSecondary),
                ),
              ),
              TvButton(
                key: const ValueKey('tv-history-clear'),
                focusNode: _clear,
                icon: Icons.delete_sweep_rounded,
                label: i18n('tv_history_clear'),
                onTap: () => unawaited(_clearAll(rooms)),
              ),
            ],
          ),
        ),
        Expanded(
          child: TvRoomGrid(
            key: _grid,
            rooms: rooms,
            onLeaveUp: _clear.requestFocus,
            detail: (room) => historyWatchedLabel(room.lastWatchedAt, now),
            actions: (room) => [
              RoomMenuAction(
                key: const ValueKey('tv-history-delete'),
                icon: Icons.delete_outline_rounded,
                label: i18n('tv_history_delete'),
                danger: true,
                onSelected: () => unawaited(ref.read(storeProvider).history.remove(room)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
