import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_actions.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follow_status.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/onboarding/onboarding_page.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/search/search_empty.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Which follows to show: live, all, or all by group (principles §4.1).
enum _Filter { live, all, group }

/// The sort menu entry that opens the custom order page.
const _editOrder = 'editOrder';

/// Menu labels of the orders (F-FAV-01).
Map<FollowSort, String> get followSortLabels => {
  FollowSort.audience: t.follows.sort.audience,
  FollowSort.liveTime: t.follows.sort.liveTime,
  FollowSort.platform: t.follows.sort.platform,
  FollowSort.custom: t.follows.sort.custom,
};

/// Followed streamers: live ones as cover cards, the rest as compact rows
/// without covers (principles §4.1, §4.3), in the remembered order
/// (F-FAV-01). Until the first refresh after launch publishes, nothing is
/// shown as live (F-FAV-03).
class FollowsPage extends ConsumerStatefulWidget {
  const new({this.filter, this.request, super.key});

  /// `live` opens the live tab (the combined live alert, F-NEW-01).
  final String? filter;

  /// Changes with each outside request, so a repeated request applies
  /// [filter] again after the user switched tabs.
  final String? request;

  @override
  ConsumerState<FollowsPage> createState() => _FollowsPageState();
}

class _FollowsPageState extends ConsumerState<FollowsPage> {
  late _Filter _filter = _requested ?? _Filter.all;

  _Filter? get _requested => widget.filter == 'live' ? _Filter.live : null;

  /// Multi-select (principles §4.1, spec/product.md F-FAV-09): the keys of
  /// the chosen follows in the order they were chosen; null outside it.
  List<String>? _selection;

  /// Where a Shift-click range starts: the last follow clicked.
  String? _anchor;

  /// The follows as shown, for ranges and 全选; set by each build.
  List<FollowEntry> _shown = const [];

  bool get _selecting => _selection != null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(FollowsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = _requested;
    if (requested != null && (widget.request != oldWidget.request || widget.filter != oldWidget.filter)) {
      _filter = requested;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Esc leaves multi-select first (principles §6.2); Ctrl+A chooses every
  /// shown follow. Only while this page is the one on screen.
  bool _onKey(KeyEvent event) {
    if (!_selecting || event is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true) || !TickerMode.valuesOf(context).enabled) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _endSelection();
      return true;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyA && (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _selectAll();
      return true;
    }
    return false;
  }

  void _beginSelection(FollowEntry entry) => setState(() {
    _selection = [followKey(entry)];
    _anchor = followKey(entry);
  });

  void _endSelection() => setState(() {
    _selection = null;
    _anchor = null;
  });

  void _toggle(FollowEntry entry) => setState(() {
    final key = followKey(entry);
    final selection = [...?_selection];
    if (!selection.remove(key)) selection.add(key);
    _anchor = key;
    _selection = selection.isEmpty ? null : selection;
  });

  /// Shift-click: every follow shown from the anchor to [entry] joins, in the
  /// direction of the click.
  void _extend(FollowEntry entry) => setState(() {
    final keys = [for (final shown in _shown) followKey(shown)];
    final to = keys.indexOf(followKey(entry));
    final from = _anchor == null ? -1 : keys.indexOf(_anchor!);
    final range = from < 0 || to < 0 ? [followKey(entry)] : keys.sublist(math.min(from, to), math.max(from, to) + 1);
    final selection = [...?_selection];
    for (final key in from > to ? range.reversed : range) {
      if (!selection.contains(key)) selection.add(key);
    }
    _selection = selection;
  });

  void _selectAll() => setState(() {
    final selection = [...?_selection];
    for (final entry in _shown) {
      if (!selection.contains(followKey(entry))) selection.add(followKey(entry));
    }
    _selection = selection;
  });

  /// A tap or click on [entry]: true when it changed the selection instead
  /// of opening the room. Ctrl (⌘) or Shift clicks start multi-select on
  /// desktops; while selecting, a tap chooses or unchooses, and Shift adds a
  /// range. Not on TV.
  bool _selectTap(FollowEntry entry) {
    if (TvScope.of(context).enabled) return false;
    final keyboard = HardwareKeyboard.instance;
    final range = keyboard.isShiftPressed;
    final add = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!_selecting) {
      if (!range && !add) return false;
      _beginSelection(entry);
    } else if (range) {
      _extend(entry);
    } else {
      _toggle(entry);
    }
    return true;
  }

  /// The chosen follows that are shown, in the order they were chosen.
  List<FollowEntry> _chosen() {
    final byKey = {for (final entry in _shown) followKey(entry): entry};
    return [for (final key in _selection ?? const <String>[]) ?byKey[key]];
  }

  /// 加入多画面: the chosen rooms in the order chosen fill the empty cells; a
  /// window's layouts hold a limited number, and more are said to be left out
  /// (spec/modules/multiview.md ENT-1). Platforms this build cannot play are
  /// skipped.
  void _toMultiview(List<FollowEntry> chosen) {
    final capacity = multiviewCapacity();
    final width = WindowLayout(MediaQuery.sizeOf(context)).width;
    final limit = multiviewRoomLimit(multiviewLayoutsFor(width, capacity: capacity), capacity: capacity);
    final rooms = [
      for (final entry in chosen)
        if (entry.status != FollowStatus.unsupported) entry.follow.ref,
    ];
    if (rooms.isEmpty) return;
    if (rooms.length > limit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.follows.multiviewLimit(n: limit))));
    }
    _endSelection();
    unawaited(context.push('/multiview', extra: rooms.take(limit).toList()));
  }

  Future<void> _setGroups(List<FollowEntry> chosen) async {
    final rooms = [for (final entry in chosen) entry.follow.ref];
    final saved = await editRoomsGroups(context, ref, rooms, t.follows.selectedStreamers(n: chosen.length));
    if (saved && mounted) _endSelection();
  }

  Future<void> _unfollow(List<FollowEntry> chosen) async {
    _endSelection();
    await unfollowManyWithUndo(context, ref, [for (final entry in chosen) entry.follow.ref]);
  }

  PreferredSizeWidget _selectionBar() {
    final chosen = _chosen();
    final none = chosen.isEmpty;
    return PageAppBar(
      leading: IconButton(tooltip: t.follows.cancelSelection, icon: const Icon(Icons.close), onPressed: _endSelection),
      title: Text(t.follows.selectedCount(n: chosen.length)),
      actions: [
        IconButton(
          tooltip: t.follows.selectAll,
          icon: const Icon(Icons.select_all),
          onPressed: chosen.length == _shown.length ? null : _selectAll,
        ),
        IconButton(
          tooltip: t.room.addToMultiview,
          icon: const Icon(Icons.grid_view),
          onPressed: none ? null : () => _toMultiview(chosen),
        ),
        IconButton(
          tooltip: t.rooms.setGroups,
          icon: const Icon(Icons.folder_outlined),
          onPressed: none ? null : () => unawaited(_setGroups(chosen)),
        ),
        IconButton(
          tooltip: t.common.unfollow,
          icon: const Icon(Icons.heart_broken_outlined),
          onPressed: none ? null : () => unawaited(_unfollow(chosen)),
        ),
      ],
    );
  }

  PreferredSizeWidget _pageBar(List<FollowEntry> live, FollowSort sort, {required bool refreshing}) => PageAppBar(
    title: Text(t.app.tabs.follows),
    actions: [
      PopupMenuButton<Object>(
        tooltip: t.follows.sortTooltip,
        icon: const Icon(Icons.sort),
        onSelected: (choice) async {
          final setting = ref.read(followSortSetting.notifier);
          if (choice is FollowSort) {
            await setting.set(choice);
            return;
          }
          // "调整顺序" switches to the custom order it edits.
          await setting.set(FollowSort.custom);
          if (mounted) unawaited(context.push('/follows/order'));
        },
        itemBuilder: (context) => [
          for (final MapEntry(key: option, value: label) in followSortLabels.entries)
            CheckedPopupMenuItem<Object>(value: option, checked: option == sort, child: Text(label)),
          const PopupMenuDivider(),
          PopupMenuItem<Object>(value: _editOrder, child: Text(t.follows.editCustomOrder)),
        ],
      ),
      IconButton(
        tooltip: t.follows.openMultiview,
        icon: const Icon(Icons.grid_view),
        // Live follows in their shown order fill the grid (ENT-1).
        onPressed: () => unawaited(context.push('/multiview', extra: [for (final entry in live) entry.follow.ref])),
      ),
      if (refreshing)
        const Padding(
          padding: EdgeInsets.all(Space.s4),
          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else
        IconButton(
          tooltip: t.follows.refreshStatus,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(followRefreshProvider.notifier).refresh(),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final refresh = ref.watch(followRefreshProvider);
    final session = FollowSession.of(refresh);
    final sites = ref.watch(sitesProvider);
    final sort = ref.watch(followSortSetting);
    final platforms = ref.watch(enabledPlatformsProvider);
    final tv = TvScope.of(context).enabled;
    final entries = [
      for (final follow in follows.value ?? const <FollowedRoom>[])
        (follow: follow, status: session.statusOf(follow, supported: sites.containsKey(follow.ref.platform))),
    ];
    final live = sortLive(
      entries.where((entry) => entry.status == FollowStatus.live),
      sort,
      platforms: platforms,
      liveSince: session.liveSince,
    );
    final rows = sortRows(entries.where((entry) => entry.status != FollowStatus.live), sort, platforms: platforms);
    final tags = _filter == _Filter.group ? ref.watch(tagsProvider).value ?? const <Tag>[] : const <Tag>[];
    final sections = _filter == _Filter.group ? followSections(tags, live, rows) : const <FollowSection>[];
    // A follow in several groups shows in each; it is chosen once.
    final shown = <String, FollowEntry>{
      for (final entry in switch (_filter) {
        _Filter.live => live,
        _Filter.all => [...live, ...rows],
        _Filter.group => [
          for (final section in sections) ...[...section.cards, ...section.rows],
        ],
      })
        followKey(entry): entry,
    };
    _shown = shown.values.toList();
    final selection = _selection;
    final appBar = selection != null ? _selectionBar() : _pageBar(live, sort, refreshing: refresh.isLoading);
    final body = follows.when(
      loading: () =>
          RoomGridSkeleton(density: ref.watch(denseFollowsSetting) ? CardDensity.compact : CardDensity.standard),
      error: (error, _) =>
          ErrorView(error, title: t.follows.loadFailed, onRetry: () => ref.invalidate(followsProvider)),
      data: (rooms) {
        // principles §3.3: the three ways to get follows.
        if (rooms.isEmpty) {
          return MessageView(
            illustration: Illustration.followsEmpty,
            title: t.follows.emptyTitle,
            message: t.follows.emptyMessage,
            actionLabel: t.follows.goDiscover,
            onAction: () => context.go('/discover'),
            actions: [
              MessageAction(t.follows.pasteLink, () => pasteRoomLink(context)),
              MessageAction(t.follows.importData, () => context.push(welcomeLocation)),
            ],
          );
        }
        return PageBody(
          child: RefreshIndicator(
            onRefresh: () => ref.read(followRefreshProvider.notifier).refresh(),
            child: _FollowList(
              live: live,
              rows: rows,
              sections: sections,
              tagsShown: tags.isNotEmpty,
              session: session,
              filter: _filter,
              onFilter: (filter) => setState(() => _filter = filter),
              selected: selection?.toSet(),
              onSelectTap: _selectTap,
              onSelectMenu: (entry) {
                if (!_selecting) return false;
                _toggle(entry);
                return true;
              },
              // TV has no multi-select (principles §4.1).
              onBeginSelection: tv ? null : _beginSelection,
            ),
          ),
        );
      },
    );
    // principles §5.2: a landscape phone lets the top bar scroll away, except
    // while it holds the multi-select actions.
    final short = WindowLayout(MediaQuery.sizeOf(context)).isShortLandscape && !tv;
    return PopScope(
      // Back leaves multi-select first (principles §6.3: back steps out one
      // level at a time).
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _endSelection();
      },
      child: short
          ? Scaffold(
              body: ScrollAwayHeader(
                pinned: _selecting,
                header: SizedBox(
                  height: appBar.preferredSize.height + MediaQuery.paddingOf(context).top,
                  child: appBar,
                ),
                body: body,
              ),
            )
          : Scaffold(appBar: appBar, body: body),
    );
  }
}

/// A follow's identity in the multi-select.
String followKey(FollowEntry entry) => entry.follow.ref.key;

/// One section of the group view (F-FAV-05): a group, or 未分组 (id ''),
/// with its live cards and offline rows.
typedef FollowSection = ({
  String id,
  String title,
  String description,
  List<FollowEntry> cards,
  List<FollowEntry> rows,
});

/// The group view's sections: one per tag in the user's order, then the
/// follows without tags (left out when there are none); a follow in several
/// groups shows in each.
List<FollowSection> followSections(List<Tag> tags, List<FollowEntry> live, List<FollowEntry> rows) {
  bool ungrouped(FollowEntry entry) => entry.follow.tagIds.every((id) => !tags.any((tag) => tag.id == id));
  final rest = (cards: live.where(ungrouped).toList(), rows: rows.where(ungrouped).toList());
  return [
    for (final tag in tags)
      (
        id: tag.id,
        title: tag.name,
        description: tag.description,
        cards: [
          for (final entry in live)
            if (entry.follow.tagIds.contains(tag.id)) entry,
        ],
        rows: [
          for (final entry in rows)
            if (entry.follow.tagIds.contains(tag.id)) entry,
        ],
      ),
    if (rest.cards.isNotEmpty || rest.rows.isNotEmpty)
      (id: '', title: t.follows.ungrouped, description: '', cards: rest.cards, rows: rest.rows),
  ];
}

class _FollowList extends ConsumerStatefulWidget {
  const new({
    required this.live,
    required this.rows,
    required this.sections,
    required this.tagsShown,
    required this.session,
    required this.filter,
    required this.onFilter,
    required this.selected,
    required this.onSelectTap,
    required this.onSelectMenu,
    required this.onBeginSelection,
  });

  /// Live follows in the chosen order.
  final List<FollowEntry> live;

  /// The rest in the chosen order.
  final List<FollowEntry> rows;

  /// The group view's sections.
  final List<FollowSection> sections;

  /// Whether there are groups (the group view explains them otherwise).
  final bool tagsShown;
  final FollowSession session;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  /// Keys of the chosen follows while multi-selecting; null otherwise.
  final Set<String>? selected;

  /// A tap: true when it went to the selection instead of the room.
  final bool Function(FollowEntry entry) onSelectTap;

  /// A long press or right click: true when it went to the selection
  /// instead of the card menu.
  final bool Function(FollowEntry entry) onSelectMenu;

  /// The card menu's 多选; null where there is no multi-select (TV).
  final ValueChanged<FollowEntry>? onBeginSelection;

  @override
  ConsumerState<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends ConsumerState<_FollowList> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'follows-grid');
  final Map<String, TvGridFocus> _groupFocus = {};

  /// The failed platforms whose banner was dismissed; a refresh that fails
  /// on other platforms shows it again.
  Set<String> _dismissed = const {};

  @override
  void dispose() {
    _focus.dispose();
    for (final focus in _groupFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final filter = widget.filter;
    final session = widget.session;
    final selected = widget.selected;
    final failedPlatforms = session.result?.failedPlatforms ?? const <String>{};
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final dense = ref.watch(denseFollowsSetting);
    final preferOnline = ref.watch(preferRealOnlineSetting);
    final density = dense ? CardDensity.compact : CardDensity.standard;
    final recording = ref.watch(recordingRoomsProvider).value ?? const <String>{};
    final period = ref.watch(coverPeriodProvider);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final now = DateTime.now();
    // Up and down in a room opened here step through the live follows as
    // shown (F-NEW-04); rooms opened from the rows use it too.
    final origin = RoomOrigin([
      for (final entry in live)
        RoomEntry(entry.follow.ref, name: entry.follow.room.anchorName, title: entry.follow.room.title),
    ], label: t.follows.liveFollows);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = CardGridGeometry.of(context, constraints.maxWidth, density: density);
        final margin = TvScope.of(context).enabled ? grid.padding.left : layout.margin;
        // Offline rows are as wide as a reading column on the grid's left
        // line, so the logo stays near the name (principles §4.3).
        final rowWidth = Sizes.readingWidth + 2 * margin;

        void open(FollowEntry entry) {
          if (widget.onSelectTap(entry)) return;
          final room = entry.follow.ref;
          if (entry.status == FollowStatus.unsupported) {
            // F-FAV-08: say so instead of opening a room that cannot load.
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(t.follows.platformRetired(name: platformName(room.platform)))));
            return;
          }
          unawaited(context.push(roomLocation(room), extra: origin));
        }

        void menu(FollowEntry entry) {
          if (widget.onSelectMenu(entry)) return;
          final begin = widget.onBeginSelection;
          unawaited(
            showRoomCardMenu(
              context,
              ref,
              room: entry.follow.ref,
              anchorName: entry.follow.room.anchorName,
              onSelect: begin == null ? null : () => begin(entry),
            ),
          );
        }

        Widget liveGrid(List<FollowEntry> cards, TvGridFocus focus) => SliverPadding(
          padding: EdgeInsets.fromLTRB(grid.padding.left, Space.s1, grid.padding.right, 0),
          sliver: SliverGrid.builder(
            gridDelegate: grid.delegate,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final entry = cards[index];
              final room = entry.follow.room;
              final audience = shownAudience(room.audience, preferOnline: preferOnline);
              final since = session.liveSince(entry.follow);
              final card = RoomCardView(
                platformId: room.ref.platform,
                anchorName: room.anchorName,
                title: room.title,
                isLive: true,
                cover: networkImage(room.cover, logicalWidth: grid.cellWidth, devicePixelRatio: dpr, period: period),
                audience: audience == null ? null : formatCount(audience),
                liveFor: since == null ? null : formatLiveDuration(now.difference(since)),
                recording: recording.contains(room.ref.key),
                density: density,
                focusNode: focus.node(index),
                onFocusChange: (focused) {
                  if (focused) focus.focused(index);
                },
                onKeyEvent: (node, event) => focus.handleKey(
                  index,
                  event,
                  count: cards.length,
                  columns: grid.columns,
                  rowExtent: grid.rowExtent,
                ),
                onTap: () => open(entry),
                onMenu: () => menu(entry),
              );
              return selected == null
                  ? card
                  : SelectableCard(selected: selected.contains(followKey(entry)), child: card);
            },
          ),
        );

        Widget rowList(List<FollowEntry> rows) => SliverConstrainedCrossAxis(
          maxExtent: rowWidth,
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final entry = rows[index];
              final room = entry.follow.room;
              final last = room.lastLiveAt;
              final lastText = last == null ? null : t.follows.lastLive(ago: formatAgo(last, now));
              final (String? tag, String subtitle) = switch (entry.status) {
                FollowStatus.unsupported => (
                  t.follows.tag.unsupported,
                  t.follows.unsupportedPlatform(name: platformName(room.ref.platform)),
                ),
                FollowStatus.unknown => (t.follows.tag.unknown, lastText ?? t.follows.unknownDetail),
                FollowStatus.missing => (t.follows.tag.missing, lastText ?? t.follows.missingDetail),
                FollowStatus.replay => (t.follows.tag.replay, lastText ?? t.follows.replayDetail),
                FollowStatus.checking => (null, lastText ?? t.follows.checking),
                FollowStatus.offline || FollowStatus.live => (null, lastText ?? t.common.offline),
              };
              final row = OfflineRoomRow(
                platformId: room.ref.platform,
                anchorName: room.anchorName.isEmpty ? room.ref.roomId : room.anchorName,
                seed: room.ref.key,
                avatar: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
                subtitle: subtitle,
                tag: tag,
                recording: recording.contains(room.ref.key),
                onTap: () => open(entry),
                onMenu: () => menu(entry),
              );
              return selected == null
                  ? row
                  : SelectableRow(selected: selected.contains(followKey(entry)), margin: margin, child: row);
            },
          ),
        );

        Widget heading(String text, {String? detail, double top = Space.s6}) => SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, top, margin, Space.s1),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: theme.textTheme.titleSmall),
                if (detail != null && detail.isNotEmpty)
                  Text(detail, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );

        final slivers = <Widget>[
          if (failedPlatforms.isNotEmpty && !setEquals(failedPlatforms, _dismissed))
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, Space.s2, margin, 0),
              sliver: SliverToBoxAdapter(
                child: PlatformAlertBanner(
                  platforms: failedPlatforms,
                  onRetry: () => ref.read(followRefreshProvider.notifier).refresh(),
                  onStatus: () => context.go(platformStatusLocation),
                  onDismiss: () => setState(() => _dismissed = failedPlatforms),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: margin, vertical: Space.s2),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: Space.s2,
                runSpacing: Space.s2,
                children: [
                  ChoiceChip(
                    label: Text(session.checking ? t.follows.filter.live : t.follows.filter.liveCount(n: live.length)),
                    selected: filter == _Filter.live,
                    onSelected: (_) => widget.onFilter(_Filter.live),
                  ),
                  ChoiceChip(
                    label: Text(t.common.all),
                    selected: filter == _Filter.all,
                    onSelected: (_) => widget.onFilter(_Filter.all),
                  ),
                  ChoiceChip(
                    label: Text(t.follows.filter.groups),
                    selected: filter == _Filter.group,
                    onSelected: (_) => widget.onFilter(_Filter.group),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(t.follows.manageGroups),
                    onPressed: () => context.push('/follows/groups'),
                  ),
                ],
              ),
            ),
          ),
          // F-FAV-03: one line while the first refresh runs; no card claims
          // a state from an earlier run.
          if (session.checking)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, Space.s1, margin, Space.s1),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: Space.s2),
                    Text(t.follows.checking),
                  ],
                ),
              ),
            ),
          ...switch (filter) {
            _Filter.live => [
              if (live.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.s8),
                    // While the first refresh runs the line above says so.
                    child: session.checking
                        ? MessageView(title: t.follows.checking)
                        : MessageView(
                            illustration: Illustration.noneLive,
                            title: t.follows.noneLive,
                            message: t.follows.noneLiveMessage,
                            actionLabel: t.follows.showAll,
                            onAction: () => widget.onFilter(_Filter.all),
                          ),
                  ),
                ),
              liveGrid(live, _focus),
            ],
            _Filter.all => [
              liveGrid(live, _focus),
              if (widget.rows.isNotEmpty)
                heading(
                  session.checking
                      ? t.follows.allCount(n: widget.rows.length)
                      : t.follows.offlineCount(n: widget.rows.length),
                ),
              rowList(widget.rows),
            ],
            _Filter.group => _groups(heading, liveGrid, rowList),
          },
          const SliverToBoxAdapter(child: SizedBox(height: Space.s8)),
        ];
        return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers);
      },
    );
  }

  /// The group view (F-FAV-05): one section per tag in the user's order, then
  /// the follows without tags; a follow in several groups shows in each.
  List<Widget> _groups(
    Widget Function(String text, {String? detail, double top}) heading,
    Widget Function(List<FollowEntry> cards, TvGridFocus focus) liveGrid,
    Widget Function(List<FollowEntry> rows) rowList,
  ) => [
    if (!widget.tagsShown)
      SliverToBoxAdapter(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(t.follows.noGroups),
          subtitle: Text(t.follows.noGroupsHint),
          onTap: () => context.push('/follows/groups'),
        ),
      ),
    for (final section in widget.sections) ...[
      heading(
        '${section.title} · ${section.cards.length + section.rows.length}',
        detail: section.description,
        top: Space.s4,
      ),
      if (section.cards.isEmpty && section.rows.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: PageMargin.rowInsets(context).left, vertical: Space.s2),
            child: Text(t.follows.groupEmpty),
          ),
        ),
      liveGrid(
        section.cards,
        _groupFocus.putIfAbsent(section.id, () => TvGridFocus(debugLabel: 'follows-group-${section.id}')),
      ),
      rowList(section.rows),
    ],
  ];
}

/// A live card while multi-selecting (F-FAV-09): a round mark in the middle
/// of the cover, filled with a check when chosen, and a ring around the
/// chosen card. The corners keep the logo, the live badge, the audience and
/// 录制中 in view. Only decoration: taps still reach the card.
class SelectableCard extends StatelessWidget {
  const new({required this.selected, required this.child, super.key});

  /// How far the ring lies outside the card: less than the smallest grid
  /// gap (8 dp) minus its 3 dp width.
  static const double _ring = 4;

  /// Whether the card is chosen.
  final bool selected;

  /// The card.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (selected) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.r2),
                  ),
                ),
              ),
            ),
            // The ring sits just outside the card, in the grid gap, so it
            // never covers the name.
            Positioned.fill(
              left: -_ring,
              top: -_ring,
              right: -_ring,
              bottom: -_ring,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(Radii.r2 + _ring),
                  ),
                ),
              ),
            ),
          ],
          // The cover is the card's width at 16:9.
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: DecoratedBox(
                      // On the cover: a white ring shows on any picture.
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.4),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: SizedBox.square(
                        dimension: Sizes.iconLg,
                        child: selected ? Icon(Icons.check, size: Sizes.iconMd, color: scheme.onPrimary) : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An offline row while multi-selecting (F-FAV-09): a checkbox before it on
/// the page margin, and a tint when chosen. The row itself takes the taps.
class SelectableRow extends StatelessWidget {
  const new({required this.selected, required this.margin, required this.child, super.key});

  /// Whether the row is chosen.
  final bool selected;

  /// The page margin the checkbox starts on.
  final double margin;

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      // A Material, not a coloured box: the row's ink draws on it.
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        child: Row(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(start: math.max(0, margin - Space.s3)),
              // The row is the one focus and tap target; the box only shows.
              child: ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: Checkbox(value: selected, onChanged: (_) {}),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Location of 关于 › 平台状态.
const platformStatusLocation = '/me/about/status';

/// principles §3.3 "平台异常": the platforms the last follow refresh could not
/// reach, what that means for the list, and the next steps: retry, look at
/// the platforms' status, or dismiss it until other platforms fail.
class PlatformAlertBanner extends StatelessWidget {
  const new({
    required this.platforms,
    required this.onRetry,
    required this.onStatus,
    required this.onDismiss,
    super.key,
  });

  /// Platform ids.
  final Set<String> platforms;

  /// Refreshes the follows again.
  final VoidCallback onRetry;

  /// Opens the platform status page.
  final VoidCallback onStatus;

  /// Hides the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = LiveTheme.of(context).warning;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(warning.withValues(alpha: 0.12), theme.colorScheme.surface),
          border: Border.all(color: warning.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(Radii.r3),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: warning, size: Sizes.iconMd),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(
                      t.follows.refreshFailed(platforms: platforms.map(platformName).join(t.common.listSeparator)),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onRetry, child: Text(t.common.retry)),
                  TextButton(onPressed: onStatus, child: Text(t.follows.viewStatus)),
                  TextButton(onPressed: onDismiss, child: Text(t.common.gotIt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
