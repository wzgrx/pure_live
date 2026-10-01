import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';

/// Where the picker takes rooms from.
enum PickerSource {
  /// Followed rooms.
  follows,

  /// Watch history.
  history,
}

/// Orders picker rooms: playable first, then by audience (3.x
/// `compareMultiviewRooms`).
int compareMultiviewRooms(
  LiveRoom a,
  LiveRoom b, {
  bool preferRealOnline = false,
  bool Function(String platform)? platformEnabled,
}) {
  final result = (b.isPlayableNow ? 1 : 0).compareTo(a.isPlayableNow ? 1 : 0);
  if (result != 0) return result;
  return LiveRoom.compareAudienceRanking(
    a,
    b,
    preferRealOnline: preferRealOnline,
    platformEnabled: platformEnabled ?? (_) => false,
  );
}

/// The rooms of [rooms] the picker lists for [query]: platforms that still
/// exist, a room id, the words in the name or title.
List<LiveRoom> pickerRooms(
  List<LiveRoom> rooms, {
  required String query,
  required bool Function(String platform) supported,
  bool preferRealOnline = false,
  Set<String> realOnlinePlatforms = const {},
}) {
  final words = query.trim().toLowerCase();
  final list = [
    for (final room in rooms)
      if (supported(room.platform) &&
          room.roomId.trim().isNotEmpty &&
          (words.isEmpty || room.nick.toLowerCase().contains(words) || room.title.toLowerCase().contains(words)))
        room,
  ];
  return list..sort(
    (a, b) => compareMultiviewRooms(
      a,
      b,
      preferRealOnline: preferRealOnline,
      platformEnabled: (platform) => realOnlinePlatforms.contains(platform.trim().toLowerCase()),
    ),
  );
}

/// The room picker of a cell (3.x `MultiviewRoomPicker`): follows or
/// history, searchable; the side panel on desktop and the bottom sheet
/// elsewhere share it.
class MultiviewRoomPicker extends ConsumerStatefulWidget {
  /// Creates the picker.
  const new({required this.onPicked, this.shownIn, super.key});

  /// Called with the chosen room.
  final void Function(LiveRoom room) onPicked;

  /// The 1-based cell that already shows a room, or null (marks the row).
  final int? Function(LiveRoom room)? shownIn;

  @override
  ConsumerState<MultiviewRoomPicker> createState() => _MultiviewRoomPickerState();
}

class _MultiviewRoomPickerState extends ConsumerState<MultiviewRoomPicker> {
  PickerSource _source = PickerSource.follows;
  String _query = '';
  late Stream<List<LiveRoom>> _rooms = _streamFor(_source);

  Stream<List<LiveRoom>> _streamFor(PickerSource source) {
    final store = ref.read(storeProvider);
    return switch (source) {
      PickerSource.follows => store.follows.watchAll(),
      PickerSource.history => store.history.watchAll(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(sitesProvider);
    final preferRealOnline = watchSetting(ref, Settings.preferRealOnlineCounts);
    final realOnline = watchSetting(ref, Settings.realOnlinePlatforms).toSet();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const ValueKey('multiview-picker-search'),
            onChanged: (value) => setState(() => _query = value),
            style: context.textStyles.t13,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Remix.search_line, size: 20),
              hintText: i18n('multiview_search_hint'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<PickerSource>(
            showSelectedIcon: false,
            selected: {_source},
            onSelectionChanged: (selection) => setState(() {
              _source = selection.first;
              _rooms = _streamFor(_source);
            }),
            segments: [
              ButtonSegment(value: PickerSource.follows, label: Text(i18n('favorites_title'))),
              ButtonSegment(value: PickerSource.history, label: Text(i18n('history'))),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<LiveRoom>>(
            key: ValueKey(_source),
            stream: _rooms,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const AppStatusView(type: AppStatusType.loading, isMini: true);
              final rooms = pickerRooms(
                snapshot.requireData,
                query: _query,
                supported: (platform) => sites.maybeOf(platform) != null,
                preferRealOnline: preferRealOnline,
                realOnlinePlatforms: realOnline,
              );
              if (rooms.isEmpty) {
                return AppStatusView(
                  type: AppStatusType.empty,
                  icon: Remix.tv_2_line,
                  title: i18n('multiview_no_rooms_title'),
                  subtitle: i18n('multiview_no_rooms_subtitle'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return _RoomTile(room: room, shownIn: widget.shownIn?.call(room), onTap: () => widget.onPicked(room));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoomTile extends StatelessWidget {
  const new({required this.room, required this.shownIn, required this.onTap});

  final LiveRoom room;
  final int? shownIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    final platform = platformName(room.platform);
    return ListTile(
      key: ValueKey('multiview-pick-${room.identityKey}'),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, radius: 19),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                shape: BoxShape.circle,
              ),
              child: PlatformLogo(room.platform, size: 14),
            ),
          ),
        ],
      ),
      title: Text(room.displayNick(platform), maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t14Medium),
      subtitle: Text(
        room.title.trim().isEmpty ? platform : room.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: styles.t12Muted,
      ),
      trailing: shownIn != null
          ? Text(i18n('multiview_shown_in', args: {'index': '$shownIn'}), style: styles.t11Primary)
          : _LiveStatusBadge(room: room),
      onTap: onTap,
    );
  }
}

/// Live dot and words (3.x `_LiveStatusBadge`).
class _LiveStatusBadge extends StatelessWidget {
  const new({required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = room.effectiveLiveStatus;
    final (color, key) = switch (status) {
      LiveStatus.live => (const Color(0xFF31C24C), 'live_now'),
      LiveStatus.replay => (theme.colorScheme.tertiary, 'replay'),
      LiveStatus.unknown => (theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), 'favorite_status_unknown'),
      _ => (theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35), 'offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          i18n(key),
          style: context.textStyles.t11.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Opens the picker as a bottom sheet; the chosen room or null.
Future<LiveRoom?> showRoomPickerSheet(BuildContext context, {int? Function(LiveRoom room)? shownIn}) =>
    showModalBottomSheet<LiveRoom>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: MultiviewRoomPicker(shownIn: shownIn, onPicked: (room) => Navigator.of(sheetContext).pop(room)),
        ),
      ),
    );
