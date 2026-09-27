import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';

/// Multiview (spec/modules/multiview.md): several rooms, one with sound.
class MultiviewPage extends ConsumerStatefulWidget {
  const new({this.rooms = const [], super.key});

  /// Rooms to fill in order ("一键多画面" from the follows page).
  final List<RoomRef> rooms;

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  bool _leaving = false;

  /// Remote and keyboard focus of the cells (TV: the D-pad moves between them).
  final TvGridFocus _cells = TvGridFocus(debugLabel: 'multiview-cell');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final compact = WindowLayout(MediaQuery.sizeOf(context)).width == WidthClass.compact;
      // Default layout by window class (ENT-3): 1×2 on phones, 2×2 elsewhere;
      // TV is always 2×2 (principles §5.3).
      final layout = compact && !TvScope.of(context).enabled ? MultiviewLayout.two : MultiviewLayout.four;
      unawaited(ref.read(multiviewProvider.notifier).start(layout: layout, rooms: widget.rooms));
    });
  }

  @override
  void dispose() {
    _cells.dispose();
    super.dispose();
  }

  /// Unmount every video, let two frames go by, then leave (EXT-2).
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    ref.read(multiviewProvider.notifier).clearForExit();
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiviewProvider);
    final controller = ref.read(multiviewProvider.notifier);
    final capacity = multiviewCapacity();
    final window = WindowLayout(MediaQuery.sizeOf(context));
    final tv = TvScope.of(context).enabled;
    final layouts = [
      MultiviewLayout.one,
      MultiviewLayout.two,
      MultiviewLayout.four,
      if (window.width.atLeast(WidthClass.expanded)) MultiviewLayout.onePlusN,
      if (capacity >= 9 && window.width.atLeast(WidthClass.large)) MultiviewLayout.nine,
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back), onPressed: _leave),
          title: const Text('多画面'),
          actions: [
            if (state.layout == MultiviewLayout.onePlusN && state.cells.length < capacity)
              IconButton(tooltip: '添加画面', icon: const Icon(Icons.add), onPressed: controller.addCell),
            IconButton(
              tooltip: state.muteAll ? '取消全部静音' : '全部静音',
              icon: Icon(state.muteAll ? Icons.volume_off : Icons.volume_up),
              onPressed: controller.toggleMuteAll,
            ),
            // TV keeps the fixed 2×2 (principles §5.3).
            if (!tv)
              PopupMenuButton<MultiviewLayout>(
                tooltip: '布局',
                icon: const Icon(Icons.grid_view),
                onSelected: controller.setLayout,
                itemBuilder: (context) => [
                  for (final layout in layouts)
                    CheckedPopupMenuItem(value: layout, checked: layout == state.layout, child: Text(layout.label)),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: _Grid(state: state, compact: window.width == WidthClass.compact && !tv, focus: _cells, tv: tv),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const new({required this.state, required this.compact, required this.focus, required this.tv});

  final MultiviewState state;
  final bool compact;
  final TvGridFocus focus;
  final bool tv;

  /// Cells per row for D-pad moves; null where the layout is not a grid (1+N).
  int? get _columns => switch (state.layout) {
    MultiviewLayout.one => 1,
    MultiviewLayout.two => compact ? 1 : 2,
    MultiviewLayout.four => 2,
    MultiviewLayout.nine => 3,
    MultiviewLayout.onePlusN => null,
  };

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final count = state.cells.length;
    Widget cell(int index) => _CellView(
      index: index,
      focusNode: focus.node(index),
      autofocus: tv && index == 0,
      onKeyEvent: columns == null
          ? null
          : (node, event) => focus.handleKey(index, event, count: count, columns: columns),
    );
    const gap = 2.0;
    switch (state.layout) {
      case MultiviewLayout.one:
        return cell(0);
      case MultiviewLayout.two:
        final children = [Expanded(child: cell(0)), const SizedBox.square(dimension: gap), Expanded(child: cell(1))];
        return compact ? Column(children: children) : Row(children: children);
      case MultiviewLayout.four:
      case MultiviewLayout.nine:
        final side = state.layout == MultiviewLayout.four ? 2 : 3;
        return Column(
          children: [
            for (var row = 0; row < side; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var column = 0; column < side; column++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(gap / 2),
                          child: row * side + column < count ? cell(row * side + column) : const SizedBox(),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      case MultiviewLayout.onePlusN:
        // Big cell 3/4 wide; the small column scrolls and stays mounted (LYT-6).
        final small = [
          for (var i = 0; i < count; i++)
            if (i != state.big) i,
        ];
        return Row(
          children: [
            Expanded(flex: 3, child: cell(state.big)),
            const SizedBox(width: gap),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final index in small)
                      Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: AspectRatio(aspectRatio: 16 / 9, child: cell(index)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _CellView extends ConsumerWidget {
  const new({required this.index, required this.focusNode, this.autofocus = false, this.onKeyEvent});

  final int index;

  /// The cell's focus: the D-pad moves between cells, OK acts like a tap
  /// (OPS-1: sound focus on a playing cell, the picker on a free one) and a
  /// long OK opens the cell menu (OPS-2). Up and down never switch rooms.
  final FocusNode focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiviewProvider);
    if (index >= state.cells.length) return const SizedBox();
    final cell = state.cells[index];
    final controller = ref.read(multiviewProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final focused = index == state.audioFocus && cell.status == CellStatus.playing;
    final targeted = index == state.target && cell.assignable;

    void onTap() {
      switch (cell.status) {
        case CellStatus.playing:
          controller.setFocus(index);
        case CellStatus.resolving:
          break;
        case CellStatus.empty || CellStatus.offline || CellStatus.error:
          controller.setTarget(index);
          unawaited(_pickRoom(context, ref, index));
      }
    }

    final session = cell.session;
    final menu = cell.status == CellStatus.playing ? () => unawaited(_cellMenu(context, ref, index)) : null;
    // The remote's ring (3 dp, near-white, inside the cell) differs from the
    // sound focus (2 dp primary with the speaker badge; AUD-4).
    return FocusFrame(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onTap,
      onMenu: menu,
      onKeyEvent: onKeyEvent,
      grow: false,
      ringInside: true,
      radius: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: menu,
        onSecondaryTap: menu,
        child: DecoratedBox(
          // Sound focus and pick target are both visible (AUD-4).
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: focused
                ? Border.all(color: scheme.primary, width: 2)
                : targeted
                ? Border.all(color: scheme.tertiary, width: 2)
                : Border.all(color: const Color(0xFF222222)),
          ),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (session != null && cell.status == CellStatus.playing)
                  LiveVideoView(key: GlobalObjectKey(session), session: session),
                _CellOverlay(
                  cell: cell,
                  focused: focused,
                  muteAll: state.muteAll,
                  onRetry: () {
                    final room = cell.room;
                    if (room != null) {
                      unawaited(controller.assign(index, room));
                    } else {
                      unawaited(_pickRoom(context, ref, index));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cellMenu(BuildContext context, WidgetRef ref, int index) async {
    final controller = ref.read(multiviewProvider.notifier);
    final cell = ref.read(multiviewProvider).cells[index];
    final session = cell.session;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(cell.detail?.card.anchorName ?? '')),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('换房'),
              onTap: () => Navigator.pop(context, 'swap'),
            ),
            if ((session?.state.qualities.length ?? 0) > 1)
              ListTile(
                leading: const Icon(Icons.hd_outlined),
                title: const Text('画质'),
                onTap: () => Navigator.pop(context, 'quality'),
              ),
            if ((session?.state.lines.length ?? 0) > 1)
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('线路'),
                onTap: () => Navigator.pop(context, 'line'),
              ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新'),
              onTap: () => Navigator.pop(context, 'refresh'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('关闭'),
              onTap: () => Navigator.pop(context, 'close'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'swap':
        await _pickRoom(context, ref, index);
      case 'quality':
        final qualities = session!.state.qualities;
        final chosen = await showModalBottomSheet<Quality>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final q in qualities)
                  ListTile(
                    title: Text(q.label),
                    trailing: q == session.state.quality ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, q),
                  ),
              ],
            ),
          ),
        );
        if (chosen != null) await controller.selectQuality(index, chosen);
      case 'line':
        final lines = session!.state.lines;
        final chosen = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (i, line) in lines.indexed)
                  ListTile(
                    title: Text('线路 ${i + 1}'),
                    trailing: line.lineId == session.state.line?.lineId ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, line.lineId),
                  ),
              ],
            ),
          ),
        );
        if (chosen != null) await session.selectLine(chosen);
      case 'refresh':
        final room = cell.room;
        if (room != null) await controller.assign(index, room);
      case 'close':
        controller.close(index);
    }
  }
}

class _CellOverlay extends StatelessWidget {
  const new({required this.cell, required this.focused, required this.muteAll, required this.onRetry});

  final MultiviewCell cell;
  final bool focused;
  final bool muteAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final name = cell.detail?.card.anchorName;
    switch (cell.status) {
      case CellStatus.empty:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, color: Colors.white54, size: 36),
              SizedBox(height: Space.s1),
              Text('添加直播间', style: TextStyle(color: Colors.white54)),
            ],
          ),
        );
      case CellStatus.resolving:
        return const Center(child: CircularProgressIndicator(color: ink));
      case CellStatus.offline:
        return Center(
          child: Text(
            '${name ?? ''} 未开播\n点这里换一个',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        );
      case CellStatus.error:
        final text = describeError(cell.error ?? 'error');
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.title, style: const TextStyle(color: ink)),
              const SizedBox(height: Space.s2),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        );
      case CellStatus.playing:
        final phase = cell.session?.state;
        return Stack(
          children: [
            if (phase?.showsBuffering ?? false)
              const Center(
                child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(color: ink, strokeWidth: 2)),
              ),
            Positioned(
              left: Space.s1,
              bottom: Space.s1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(Radii.r1),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s1, vertical: 1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (focused) Icon(muteAll ? Icons.volume_off : Icons.volume_up, size: 14, color: ink),
                      if (focused) const SizedBox(width: 2),
                      Text(name ?? '', style: const TextStyle(color: ink, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// Room picker (CEL-4): follows and history, filtered by a keyword; after a
/// pick the target moves to the next free cell.
Future<void> _pickRoom(BuildContext context, WidgetRef ref, int index) async {
  final store = ref.read(storeProvider);
  final follows = await store.follows.all();
  final history = await store.history.all();
  if (!context.mounted) return;
  final room = await showModalBottomSheet<RoomRef>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _RoomPicker(follows: [for (final f in follows) f.room], history: [for (final h in history) h.room]),
  );
  if (room != null) await ref.read(multiviewProvider.notifier).assign(index, room);
}

class _RoomPicker extends StatefulWidget {
  const new({required this.follows, required this.history});

  final List<StoredRoom> follows;
  final List<StoredRoom> history;

  @override
  State<_RoomPicker> createState() => _RoomPickerState();
}

class _RoomPickerState extends State<_RoomPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    bool matches(StoredRoom room) =>
        _filter.isEmpty ||
        room.anchorName.toLowerCase().contains(_filter) ||
        room.title.toLowerCase().contains(_filter);
    Widget list(List<StoredRoom> rooms, String empty) {
      final shown = rooms.where(matches).toList()
        ..sort((a, b) => (b.lastState == LiveState.live ? 1 : 0).compareTo(a.lastState == LiveState.live ? 1 : 0));
      if (shown.isEmpty) return MessageView(title: empty);
      return ListView.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final room = shown[i];
          return ListTile(
            leading: PlatformLogo(platformId: room.ref.platform, size: Sizes.iconMd),
            title: Text(room.anchorName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: room.lastState == LiveState.live
                ? const LiveBadge()
                : Text(platformNames[room.ref.platform] ?? ''),
            onTap: () => Navigator.pop(context, room.ref),
          );
        },
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.s3),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '按主播名或标题筛选'),
                onChanged: (value) => setState(() => _filter = value.trim().toLowerCase()),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: '关注'),
                Tab(text: '观看历史'),
              ],
            ),
            Expanded(child: TabBarView(children: [list(widget.follows, '还没有关注的主播'), list(widget.history, '还没有观看记录')])),
          ],
        ),
      ),
    );
  }
}
