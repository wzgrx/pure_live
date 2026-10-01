import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Switches to another room without going back (3.x `PlayOther`): the
/// followed rooms on air, followed replays and the watch history. The
/// current room is left out; picking one replaces this page. The refresh
/// button beside the title refreshes every follow (F.1c); the lists follow
/// the store, so they change as the fresh details are written.
Future<void> showRoomSwitcher(BuildContext context, LiveRoom current) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => RoomSwitcher(current: current),
);

/// The three lists of the switcher.
class RoomSwitcher extends ConsumerStatefulWidget {
  /// Creates the switcher; [current] is not offered.
  const new({required this.current, super.key});

  /// The room playing now.
  final LiveRoom current;

  /// Refreshes every follow without the follows page's progress bar (3.x
  /// sent `refresh_favorite_rooms`, and the follows page refreshed them all
  /// silently). Set by the app (`app/app.dart`): a feature does not reach
  /// into another one. Null: no refresh button.
  static Future<void> Function()? refreshFollows;

  @override
  ConsumerState<RoomSwitcher> createState() => _RoomSwitcherState();
}

class _RoomSwitcherState extends ConsumerState<RoomSwitcher> {
  bool _refreshing = false;

  LiveRoom get current => widget.current;

  /// The refresh button (3.x `room-history-refresh`): greyed while a refresh
  /// runs; the lists change as the store does.
  Future<void> _refresh(Future<void> Function() refresh) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await refresh();
    } on Object {
      // The follows page logs its own failures; the lists keep what they had.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(storeProvider);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    final refresh = RoomSwitcher.refreshFollows;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: 3,
          animationDuration: pureLiveTabTransitionDuration,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16, right: refresh == null ? 16 : 4),
                child: Row(
                  children: [
                    Expanded(child: Text(i18n('switch_live_room'), style: Theme.of(context).textTheme.titleMedium)),
                    if (refresh != null)
                      IconButton(
                        key: const ValueKey('switch-refresh'),
                        tooltip: i18n('refresh'),
                        onPressed: _refreshing ? null : () => unawaited(_refresh(refresh)),
                        icon: _refreshing
                            ? const SizedBox.square(
                                key: ValueKey('switch-refreshing'),
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(AppIcons.refresh),
                      ),
                  ],
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: i18n('online_room_title')),
                  Tab(text: i18n('live_play_switch_replays')),
                  Tab(text: i18n('watch_history')),
                ],
              ),
              Expanded(
                child: TabBarView(
                  physics: const PureLiveBoundedScrollPhysics(),
                  children: [
                    _RoomList(
                      key: const ValueKey('switch-online'),
                      rooms: store.follows.watchAll().map(
                        (rooms) => [
                          for (final room in rooms)
                            if (room.isLiveNow && !room.hasSameIdentity(current)) room,
                        ],
                      ),
                    ),
                    _RoomList(
                      key: const ValueKey('switch-replays'),
                      rooms: store.follows.watchAll().map(
                        (rooms) => [
                          for (final room in rooms)
                            if (room.isRecord && !room.hasSameIdentity(current)) room,
                        ],
                      ),
                    ),
                    _RoomList(
                      key: const ValueKey('switch-history'),
                      rooms: store.history.watchAll().map(
                        (rooms) => [
                          for (final room in rooms)
                            if (!room.hasSameIdentity(current)) room,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  const new({required this.rooms, super.key});

  final Stream<List<LiveRoom>> rooms;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<LiveRoom>>(
    stream: rooms,
    builder: (context, snapshot) {
      final list = snapshot.data;
      if (list == null) return const Center(child: CircularProgressIndicator());
      if (list.isEmpty) {
        return AppStatusView(
          type: AppStatusType.empty,
          isMini: true,
          title: i18n('live_play_switch_empty'),
          subtitle: '',
        );
      }
      final theme = Theme.of(context);
      return ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final room = list[index];
          final platform = platformName(room.platform);
          final title = room.title.trim();
          return ListTile(
            key: ValueKey('switch-room-${room.platform}-${room.roomId}'),
            leading: CommonAvatar(avatarUrl: room.avatar, radius: 20, fallbackName: room.nick),
            title: Text(room.displayNick(platform), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [platform, if (title.isNotEmpty) title].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            trailing: room.isLiveNow ? Icon(Icons.live_tv_rounded, color: theme.colorScheme.primary, size: 18) : null,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(AppNavigator.offAndToRoomDetail(liveRoom: room));
            },
          );
        },
      );
    },
  );
}
