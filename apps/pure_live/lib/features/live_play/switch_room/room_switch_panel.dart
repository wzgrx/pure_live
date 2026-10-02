import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_switch.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// What the panel needs from the follows: set by the app (`app/app.dart`),
/// since a feature does not reach into another one.
final class FollowsRefresher {
  /// Creates the link.
  const new({required this.refresh, required this.lastRefreshedAt});

  /// Refreshes every follow without the follows page's progress bar (3.x
  /// sent `refresh_favorite_rooms`); completes with the number of rooms
  /// whose request failed.
  final Future<int> Function() refresh;

  /// When every follow was last refreshed, or null.
  final DateTime? Function() lastRefreshedAt;
}

/// Opens the "切换直播间" panel of [controller]'s room (docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板):
/// the room page's panel, or the same panel in a sheet where there is no
/// room page around [context] (the app's adaptive panel, U.1d; picking a
/// room then replaces the page).
void showRoomSwitchPanel(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.switchRoom);
    return;
  }
  unawaited(
    showAdaptivePanel<void>(
      context,
      side: false,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: RoomSwitchPanel(
          controller: controller,
          onClose: () => Navigator.of(sheetContext).pop(),
          onPick: (room, _) {
            Navigator.of(sheetContext).pop();
            unawaited(AppNavigator.offAndToRoomDetail(liveRoom: room));
          },
        ),
      ),
    ),
  );
}

/// The live room's "切换直播间" panel (docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板; 3.x
/// `PlayOther`): one panel for every layout, placed by the page like the
/// record and danmaku panels (U.2f).
///
/// The header has the refresh with the last refresh time, the filter, the
/// grid or list style (kept in `roomSwitcherLayout`) and ✕. Under it the
/// groups (followed rooms on air, the list the room came from, the watch
/// history, followed replays), the filter field while filtering, the room
/// being watched (not a choice), then the rooms: 3.x's small cards or rows.
/// A tap picks a room ([onPick] with the group it is in); a long press opens
/// the room card's dialog.
class RoomSwitchPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const new({
    required this.controller,
    required this.onPick,
    required this.onClose,
    this.source = const [],
    this.group,
    this.dragToClose = false,
    this.now = DateTime.now,
    super.key,
  });

  /// The room being watched.
  final LiveRoomController controller;

  /// A room was picked from [List] (its group, for swiping on).
  final void Function(LiveRoom room, List<LiveRoom> group) onPick;

  /// Closes the panel.
  final VoidCallback onClose;

  /// The list the room was opened from (U.2b2), in its page's order.
  final List<LiveRoom> source;

  /// Remembers the group picked while the page stays (U.2m X1).
  final ValueNotifier<RoomSwitchGroup?>? group;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  /// The clock.
  final DateTime Function() now;

  /// The follows' refresh, linked by the app; null: no refresh button.
  static FollowsRefresher? follows;

  @override
  ConsumerState<RoomSwitchPanel> createState() => _RoomSwitchPanelState();
}

class _RoomSwitchPanelState extends ConsumerState<RoomSwitchPanel> {
  StreamSubscription<List<LiveRoom>>? _followsSub;
  StreamSubscription<List<LiveRoom>>? _historySub;
  List<LiveRoom>? _follows;
  List<LiveRoom>? _history;
  Object? _error;

  bool _refreshing = false;
  bool _refreshFailed = false;
  Timer? _clock;

  bool _searching = false;
  final TextEditingController _query = TextEditingController();
  RoomSwitchGroup? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.group?.value;
    _listen();
    // "2 分钟前" moves on while the panel is open.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && RoomSwitchPanel.follows?.lastRefreshedAt() != null) setState(() {});
    });
  }

  void _listen() {
    final store = ref.read(storeProvider);
    unawaited(_followsSub?.cancel());
    unawaited(_historySub?.cancel());
    void failed(Object error) {
      if (mounted) setState(() => _error = error);
    }

    _followsSub = store.follows.watchAll().listen((rooms) {
      if (mounted) setState(() => _follows = rooms);
    }, onError: (Object error, StackTrace _) => failed(error));
    _historySub = store.history.watchAll().listen((rooms) {
      if (mounted) setState(() => _history = rooms);
    }, onError: (Object error, StackTrace _) => failed(error));
  }

  void _retry() {
    setState(() {
      _error = null;
      _follows = null;
      _history = null;
    });
    _listen();
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_followsSub?.cancel());
    unawaited(_historySub?.cancel());
    _query.dispose();
    super.dispose();
  }

  /// The refresh button (3.x `room-history-refresh`): greyed with a spinner
  /// while it runs; the lists follow the store as the fresh details are
  /// written. Failures turn the button red and say how many rooms failed,
  /// in the app's toast with "重试" (U.1d).
  Future<void> _refresh(FollowsRefresher follows) async {
    // The toast's "重试" may come after the panel closed.
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    var failed = 0;
    var broken = false;
    try {
      failed = await follows.refresh();
    } on Object {
      broken = true;
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _refreshFailed = broken || failed > 0;
    });
    if (!broken && failed == 0) return;
    AppNavigator.showToast(
      AppToast(
        broken
            ? i18n('room_switch_refresh_failed')
            : i18n('room_switch_refresh_failed_count', args: {'count': '$failed'}),
        key: const ValueKey('switch-refresh-failed-toast'),
        actionLabel: i18n('retry'),
        onAction: () => unawaited(_refresh(follows)),
      ),
    );
  }

  void _pickGroup(RoomSwitchGroup group) {
    setState(() => _picked = group);
    widget.group?.value = group;
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _query.clear();
    });
  }

  void _toggleLayout(RoomSwitchLayout layout) {
    final next = layout == RoomSwitchLayout.grid ? RoomSwitchLayout.list : RoomSwitchLayout.grid;
    unawaited(ref.read(storeProvider).settings.set(Settings.roomSwitcherLayout, next.name));
  }

  Future<void> _menu(LiveRoom room) =>
      showRoomMenu(context, store: ref.read(storeProvider), room: room, onOpen: () => _open(room, const []));

  void _open(LiveRoom room, List<LiveRoom> group) => widget.onPick(room, group);

  @override
  Widget build(BuildContext context) {
    final layout = RoomSwitchLayout.of(watchSetting(ref, Settings.roomSwitcherLayout));
    final policy = watchAudiencePolicy(ref);
    final follows = _follows;
    final history = _history;
    final lists = follows == null || history == null
        ? null
        : roomSwitchLists(
            follows: follows,
            history: history,
            source: widget.source,
            current: widget.controller.room,
            rank: policy.rank,
          );
    final group = (lists ?? RoomSwitchLists.empty).initial(_picked);
    final hook = RoomSwitchPanel.follows;
    return RoomSidePanel(
      key: const ValueKey('live-play-switch-panel'),
      title: i18n('switch_live_room'),
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      actions: [
        if (hook != null)
          _RefreshButton(
            refreshing: _refreshing,
            failed: _refreshFailed,
            last: hook.lastRefreshedAt(),
            now: widget.now(),
            onPressed: () => unawaited(_refresh(hook)),
          ),
        IconButton(
          key: const ValueKey('switch-search'),
          tooltip: i18n('room_switch_search'),
          isSelected: _searching,
          onPressed: _toggleSearch,
          icon: const Icon(AppIcons.search),
        ),
        IconButton(
          key: const ValueKey('switch-layout'),
          tooltip: i18n(layout == RoomSwitchLayout.grid ? 'room_switch_show_list' : 'room_switch_show_grid'),
          onPressed: () => _toggleLayout(layout),
          icon: Icon(layout == RoomSwitchLayout.grid ? AppIcons.switchRoomList : AppIcons.switchRoomGrid),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupBar(lists: lists ?? RoomSwitchLists.empty, selected: group, onSelected: _pickGroup),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                key: const ValueKey('switch-search-field'),
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n('room_switch_search'),
                  prefixIcon: const Icon(AppIcons.search, size: 20),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('switch-search-clear'),
                          tooltip: i18n('close'),
                          onPressed: () => setState(_query.clear),
                          icon: const Icon(AppIcons.close, size: 18),
                        ),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
          _WatchingLine(controller: widget.controller),
          Expanded(child: _content(lists, group, layout, policy)),
        ],
      ),
    );
  }

  Widget _content(RoomSwitchLists? lists, RoomSwitchGroup group, RoomSwitchLayout layout, AudiencePolicy policy) {
    if (_error != null) {
      return _PanelMessage(
        key: const ValueKey('switch-error'),
        icon: AppIcons.playbackError,
        title: i18n('room_switch_load_failed'),
        action: i18n('retry'),
        onAction: _retry,
      );
    }
    if (lists == null) return const Center(child: CircularProgressIndicator());
    final all = lists.of(group);
    final query = _searching ? _query.text.trim() : '';
    final rooms = filterByStreamer(all, query);
    if (rooms.isEmpty) {
      if (query.isNotEmpty && all.isNotEmpty) {
        return _PanelMessage(
          key: const ValueKey('switch-no-match'),
          icon: AppIcons.switchRoomNoMatch,
          title: i18n('room_switch_no_match', args: {'query': query}),
        );
      }
      return _PanelMessage(
        key: ValueKey('switch-empty-${group.name}'),
        icon: AppIcons.switchRoomEmpty,
        title: i18n(switch (group) {
          RoomSwitchGroup.onAir => 'room_switch_empty_on_air',
          RoomSwitchGroup.source => 'room_switch_empty_source',
          RoomSwitchGroup.history => 'room_switch_empty_history',
          RoomSwitchGroup.replays => 'room_switch_empty_replays',
        }),
        subtitle: group == RoomSwitchGroup.onAir ? i18n('room_switch_empty_on_air_hint') : null,
      );
    }
    final now = widget.now();
    final mixed = mixesPlatforms(rooms);
    RoomSwitchTileData data(LiveRoom room) =>
        RoomSwitchTileData.of(room, policy: policy, now: now, history: group == RoomSwitchGroup.history);
    void open(LiveRoom room) => _open(room, all);
    return switch (layout) {
      RoomSwitchLayout.grid => LayoutBuilder(
        builder: (context, constraints) {
          final columns = roomSwitchColumns(constraints.maxWidth);
          final footer = math.max(roomSwitchCardFooter, MediaQuery.textScalerOf(context).scale(12) * 1.34 + 10);
          return GridView.builder(
            key: const ValueKey('switch-grid'),
            padding: const EdgeInsets.all(roomSwitchGridPadding),
            physics: const PureLiveScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: roomSwitchCardHeight(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                columns: columns,
                footer: footer,
              ),
              mainAxisSpacing: roomSwitchGridSpacing,
              crossAxisSpacing: roomSwitchGridSpacing,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return RoomSwitchCard(
                key: ValueKey('switch-room-${room.platform}-${room.roomId}'),
                data: data(room),
                footer: footer,
                showPlatform: mixed,
                onTap: () => open(room),
                onLongPress: () => unawaited(_menu(room)),
              );
            },
          );
        },
      ),
      RoomSwitchLayout.list => ListView.builder(
        key: const ValueKey('switch-list'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        physics: const PureLiveScrollPhysics(),
        itemExtent: roomSwitchRowHeight * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return RoomSwitchRow(
            key: ValueKey('switch-room-${room.platform}-${room.roomId}'),
            data: data(room),
            onTap: () => open(room),
            onLongPress: () => unawaited(_menu(room)),
          );
        },
      ),
    };
  }
}

/// The refresh with the last refresh time ("2 分钟前"), "正在刷新" with a
/// spinner meanwhile, "刷新失败" in the error colour after a failure.
class _RefreshButton extends StatelessWidget {
  const new({
    required this.refreshing,
    required this.failed,
    required this.last,
    required this.now,
    required this.onPressed,
  });

  final bool refreshing;
  final bool failed;
  final DateTime? last;
  final DateTime now;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = failed && !refreshing ? scheme.error : scheme.onSurfaceVariant;
    final label = refreshing
        ? i18n('room_switch_refreshing')
        : failed
        ? i18n('room_switch_refresh_failed')
        : switch (last) {
            final last? => agoText(last, now),
            null => i18n('refresh'),
          };
    return Tooltip(
      message: i18n('refresh'),
      child: TextButton(
        key: const ValueKey('switch-refresh'),
        onPressed: refreshing ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: scheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refreshing)
              const SizedBox.square(
                key: ValueKey('switch-refreshing'),
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(failed ? AppIcons.switchRoomRefreshFailed : AppIcons.refresh, size: 18),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                label,
                key: const ValueKey('switch-refresh-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The groups as pills in a row that scrolls sideways when it does not
/// fit; the followed groups show how many rooms they have.
class _GroupBar extends StatelessWidget {
  const new({required this.lists, required this.selected, required this.onSelected});

  final RoomSwitchLists lists;
  final RoomSwitchGroup selected;
  final ValueChanged<RoomSwitchGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    String label(RoomSwitchGroup group) {
      final name = i18n(switch (group) {
        RoomSwitchGroup.onAir => 'room_switch_on_air',
        RoomSwitchGroup.source => 'room_switch_source',
        RoomSwitchGroup.history => 'watch_history',
        RoomSwitchGroup.replays => 'room_switch_replays',
      });
      final count = lists.of(group).length;
      return group == RoomSwitchGroup.history || count == 0 ? name : '$name $count';
    }

    return SizedBox(
      height: 40,
      child: ListView(
        key: const ValueKey('switch-groups'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final group in lists.groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: ChoiceChip(
                  key: ValueKey('switch-group-${group.name}'),
                  label: Text(label(group)),
                  selected: group == selected,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelected(group),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "正在观看 · 主播 · 标题": the room playing now, pinned at the top and not
/// a choice (U.2m c6).
class _WatchingLine extends StatelessWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableSelector<String>(
      listenable: controller,
      selector: () {
        final room = controller.room;
        final title = room.title.trim();
        return [room.displayNick(platformName(room.platform)), if (title.isNotEmpty) title].join(' · ');
      },
      builder: (context, text, _) => Container(
        key: const ValueKey('switch-watching'),
        height: 36,
        color: scheme.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(AppIcons.switchRoomWatching, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              i18n('room_switch_watching'),
              style: theme.textTheme.labelMedium?.emphasis.copyWith(color: scheme.primary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An empty, no-match or failed group: an icon and a line (and a button),
/// scrolling when the panel is short.
class _PanelMessage extends StatelessWidget {
  const new({required this.icon, required this.title, this.subtitle, this.action, this.onAction, super.key});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 36, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(key: const ValueKey('switch-retry'), onPressed: onAction, child: Text(action)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
