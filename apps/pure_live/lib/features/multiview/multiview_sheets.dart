import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The room picker (CEL-4): follows and history, live rooms first, filtered
/// by a keyword. Shown in the side panel (LYT-7) or a bottom sheet.
class MultiviewRoomPicker extends ConsumerStatefulWidget {
  const new({required this.onPicked, super.key});

  /// Called with the chosen room.
  final ValueChanged<RoomRef> onPicked;

  @override
  ConsumerState<MultiviewRoomPicker> createState() => _MultiviewRoomPickerState();
}

class _MultiviewRoomPickerState extends ConsumerState<MultiviewRoomPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final history = ref.watch(historyProvider);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    bool matches(StoredRoom room) =>
        _filter.isEmpty ||
        room.anchorName.toLowerCase().contains(_filter) ||
        room.title.toLowerCase().contains(_filter);
    Widget list(AsyncValue<List<StoredRoom>> rooms, String empty) {
      final all = rooms.value;
      if (all == null) {
        return rooms.hasError
            ? ErrorView(
                rooms.error!,
                title: t.common.loadFailed,
                compact: true,
                onRetry: () {
                  ref
                    ..invalidate(followsProvider)
                    ..invalidate(historyProvider);
                },
              )
            : const SkeletonList();
      }
      final shown = all.where(matches).toList()
        ..sort((a, b) => (b.lastState == LiveState.live ? 1 : 0).compareTo(a.lastState == LiveState.live ? 1 : 0));
      if (shown.isEmpty) return MessageView(title: empty);
      return ListView.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final room = shown[i];
          // principles §3.4: the streamer's avatar leads; the logo only
          // names the source, beside the title.
          return ListTile(
            leading: InitialAvatar(
              name: room.anchorName,
              seed: room.ref.key,
              image: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
            ),
            title: Text(room.anchorName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Row(
              children: [
                PlatformLogo(platformId: room.ref.platform),
                const SizedBox(width: Space.s1),
                Expanded(child: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            trailing: room.lastState == LiveState.live
                ? const LiveBadge()
                : Text(platformNames[room.ref.platform] ?? ''),
            onTap: () => widget.onPicked(room.ref),
          );
        },
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.s3),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.multiview.filterHint),
              onChanged: (value) => setState(() => _filter = value.trim().toLowerCase()),
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: t.app.tabs.follows),
              Tab(text: t.app.history),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                list(follows.whenData((rows) => [for (final f in rows) f.room]), t.follows.emptyTitle),
                list(history.whenData((rows) => [for (final h in rows) h.room]), t.me.noHistory),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The picker as a bottom sheet (compact windows, immersive and fullscreen,
/// TV, and "换房"); the room goes to cell [index].
Future<void> pickRoomForCell(BuildContext context, WidgetRef ref, int index) async {
  final controller = ref.read(multiviewProvider.notifier)..setTarget(index);
  final room = await showModalBottomSheet<RoomRef>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: MultiviewRoomPicker(onPicked: (room) => Navigator.pop(context, room)),
      ),
    ),
  );
  if (room != null) await controller.assign(index, room);
}

/// Actions of the cell menu (OPS-2).
enum MultiviewCellAction { swap, pause, resume, quality, line, volume, refresh, close }

/// The cell menu of a playing cell (OPS-2, F-MV-04): change room, pause or
/// resume, quality, line, volume, refresh, close.
Future<void> showMultiviewCellMenu(BuildContext context, WidgetRef ref, int index) async {
  final controller = ref.read(multiviewProvider.notifier);
  final cells = ref.read(multiviewProvider).cells;
  if (index >= cells.length) return;
  final cell = cells[index];
  final session = cell.session;
  final action = await showModalBottomSheet<MultiviewCellAction>(
    context: context,
    builder: (context) {
      Widget item(MultiviewCellAction action, IconData icon, String label) =>
          ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(context, action));
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(cell.detail?.card.anchorName ?? t.multiview.cell(n: index + 1))),
              item(MultiviewCellAction.swap, Icons.swap_horiz, t.multiview.switchRoom),
              if (cell.paused)
                item(MultiviewCellAction.resume, Icons.play_arrow, t.common.resume)
              else
                item(MultiviewCellAction.pause, Icons.pause, t.common.pause),
              if ((session?.state.qualities.length ?? 0) > 1)
                item(MultiviewCellAction.quality, Icons.hd_outlined, t.multiview.quality),
              if ((session?.state.lines.length ?? 0) > 1)
                item(MultiviewCellAction.line, Icons.alt_route, t.multiview.line),
              item(MultiviewCellAction.volume, Icons.volume_up_outlined, t.multiview.volume),
              item(MultiviewCellAction.refresh, Icons.refresh, t.common.refresh),
              item(MultiviewCellAction.close, Icons.close, t.common.close),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case MultiviewCellAction.swap:
      await pickRoomForCell(context, ref, index);
    case MultiviewCellAction.pause:
      controller.setPaused(index, paused: true);
    case MultiviewCellAction.resume:
      controller.setPaused(index, paused: false);
    case MultiviewCellAction.quality:
      await showMultiviewQualitySheet(context, ref, index);
    case MultiviewCellAction.line:
      await showMultiviewLineSheet(context, ref, index);
    case MultiviewCellAction.volume:
      await showMultiviewVolumeSheet(context, index);
    case MultiviewCellAction.refresh:
      await controller.refresh(index);
    case MultiviewCellAction.close:
      controller.close(index);
  }
}

/// Qualities of cell [index]; the choice is the user's and automatic
/// downgrades leave it alone (RS-2).
Future<void> showMultiviewQualitySheet(BuildContext context, WidgetRef ref, int index) async {
  final controller = ref.read(multiviewProvider.notifier);
  final session = ref.read(multiviewProvider).cells.elementAtOrNull(index)?.session;
  if (session == null) return;
  final qualities = session.state.qualities;
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
}

/// Lines of cell [index] at its quality (CEL-8).
Future<void> showMultiviewLineSheet(BuildContext context, WidgetRef ref, int index) async {
  final controller = ref.read(multiviewProvider.notifier);
  final session = ref.read(multiviewProvider).cells.elementAtOrNull(index)?.session;
  if (session == null) return;
  final lines = session.state.lines;
  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (i, line) in lines.indexed)
            ListTile(
              title: Text(t.multiview.lineN(n: i + 1)),
              trailing: line.lineId == session.state.line?.lineId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, line.lineId),
            ),
        ],
      ),
    ),
  );
  if (chosen != null) await controller.selectLine(index, chosen);
}

/// The volume of cell [index] (CEL-9): heard while dragging, stored for the
/// room when the drag ends.
Future<void> showMultiviewVolumeSheet(BuildContext context, int index) => showModalBottomSheet<void>(
  context: context,
  builder: (context) => SafeArea(child: MultiviewVolumePanel(index: index)),
);

/// The volume slider of one cell.
class MultiviewVolumePanel extends ConsumerWidget {
  const new({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiviewProvider);
    final cell = state.cells.elementAtOrNull(index);
    if (cell == null || cell.status != CellStatus.playing) {
      return Padding(padding: const EdgeInsets.all(Space.s6), child: Text(t.multiview.cellIdle));
    }
    final controller = ref.read(multiviewProvider.notifier);
    final theme = Theme.of(context);
    final percent = (cell.volume * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s6, Space.s3, Space.s6, Space.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cell.detail?.card.anchorName ?? t.multiview.cell(n: index + 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text('$percent%'),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  value: cell.volume,
                  label: '$percent%',
                  onChanged: (value) => controller.setVolume(index, value, persist: false),
                  onChangeEnd: (value) => controller.setVolume(index, value),
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
          Text(
            state.muteAll
                ? t.multiview.allMutedHint
                : index == state.audioFocus
                ? t.multiview.volumePerRoom
                : t.multiview.volumeNotSource,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
