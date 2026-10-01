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
/// current room is left out; picking one replaces this page.
Future<void> showRoomSwitcher(BuildContext context, LiveRoom current) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => RoomSwitcher(current: current),
);

/// The three lists of the switcher.
class RoomSwitcher extends ConsumerWidget {
  /// Creates the switcher; [current] is not offered.
  const new({required this.current, super.key});

  /// The room playing now.
  final LiveRoom current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(storeProvider);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: 3,
          animationDuration: pureLiveTabTransitionDuration,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(i18n('switch_live_room'), style: Theme.of(context).textTheme.titleMedium),
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
