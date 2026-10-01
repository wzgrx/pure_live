import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/history/history_sections.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// The watch history, newest first.
final StreamProvider<List<LiveRoom>> tvHistoryProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(storeProvider).history.watchAll(),
);

/// Watch history (pure_live_TV `HistoryPage` over v4's history store): the
/// rooms newest first with when they were watched and their platform; the
/// card dialog can delete one entry (asked first), the button above clears
/// what is shown (asked first, the focus on cancel: U.15a c12).
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
      confirmLabel: i18n('tv_history_clear'),
      danger: true,
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
    if (!history.hasValue) return const TvSkeletonGrid();
    if (rooms.isEmpty) {
      return TvStatusView(icon: TvIcons.noHistory, title: i18n('tv_no_history'), subtitle: i18n('tv_no_history_hint'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(8), scale.px(12), 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i18n('tv_history_count', args: {'count': '${rooms.length}'}),
                  style: scale.font(TvTextSize.body, color: palette.textSecondary),
                ),
              ),
              TvButton(
                key: const ValueKey('tv-history-clear'),
                focusNode: _clear,
                icon: TvIcons.clearAll,
                label: i18n('tv_history_clear'),
                kind: TvButtonKind.danger,
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
            showPlatform: true,
            detail: (room) => historyWatchedLabel(room.lastWatchedAt, now),
            actions: (room) => [
              TvRoomAction(
                key: const ValueKey('tv-history-delete'),
                icon: TvIcons.delete,
                label: i18n('tv_history_delete'),
                confirmTitle: i18n('tv_history_delete'),
                confirmMessage: i18n('tv_history_delete_message', args: {'name': roomLabel(room)}),
                onSelected: () => unawaited(ref.read(storeProvider).history.remove(room)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
