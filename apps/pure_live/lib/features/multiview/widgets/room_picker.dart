import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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
/// exist, a room id, the words in the name or title; 3.x's order, and the
/// rooms already in a cell ([shown]) last (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c9).
List<LiveRoom> pickerRooms(
  List<LiveRoom> rooms, {
  required String query,
  required bool Function(String platform) supported,
  bool Function(LiveRoom room)? shown,
  bool preferRealOnline = false,
  Set<String> realOnlinePlatforms = const {},
}) {
  final words = query.trim().toLowerCase();
  final list =
      [
        for (final room in rooms)
          if (supported(room.platform) &&
              room.roomId.trim().isNotEmpty &&
              (words.isEmpty || room.nick.toLowerCase().contains(words) || room.title.toLowerCase().contains(words)))
            room,
      ]..sort(
        (a, b) => compareMultiviewRooms(
          a,
          b,
          preferRealOnline: preferRealOnline,
          platformEnabled: (platform) => realOnlinePlatforms.contains(platform.trim().toLowerCase()),
        ),
      );
  if (shown == null) return list;
  return [...list.where((room) => !shown(room)), ...list.where(shown)];
}

/// The header of the picker: "为第 4 格选台 点直播间放进这一格" or "第 1 格换台
/// 点直播间换掉“晚风”", and ✕ where the picker closes.
class PickerHeader extends StatelessWidget {
  /// Creates the header.
  const new({required this.title, required this.hint, this.onClose, super.key});

  /// "为第 N 格选台" or "第 N 格换台".
  final String title;

  /// What a tap on a room does.
  final String? hint;

  /// Closes the picker (the landscape phone's column).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, onClose == null ? 10 : 4, onClose == null ? 16 : 4, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              key: const ValueKey('multiview-picker-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.emphasis.copyWith(color: scheme.onSurface),
            ),
          ),
          if (hint case final text?) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ] else
            const Spacer(),
          if (onClose case final close?)
            IconButton(
              key: const ValueKey('multiview-picker-close'),
              tooltip: i18n('close'),
              onPressed: close,
              icon: const Icon(AppIcons.close, size: 22),
            ),
        ],
      ),
    );
  }
}

/// The room picker of a cell (3.x `MultiviewRoomPicker`): search, follows or
/// history, the rooms; one already in a cell is marked "第 N 格" and selects
/// that cell instead (W4).
class MultiviewRoomPicker extends ConsumerStatefulWidget {
  /// Creates the picker.
  const new({required this.onPicked, this.shownIn, this.header, super.key});

  /// Called with the chosen room.
  final void Function(LiveRoom room) onPicked;

  /// The 1-based cell that already shows a room, or null (marks the row).
  final int? Function(LiveRoom room)? shownIn;

  /// Above the search field.
  final Widget? header;

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

  void _select(PickerSource source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _rooms = _streamFor(source);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sites = ref.watch(sitesProvider);
    final preferRealOnline = watchSetting(ref, Settings.preferRealOnlineCounts);
    final realOnline = watchSetting(ref, Settings.realOnlinePlatforms).toSet();
    Widget tab(PickerSource source, String label) => ChoiceChip(
      key: ValueKey('multiview-picker-${source.name}'),
      label: Text(label),
      showCheckmark: false,
      selected: _source == source,
      onSelected: (_) => _select(source),
    );
    final picker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: TextField(
            key: const ValueKey('multiview-picker-search'),
            onChanged: (value) => setState(() => _query = value),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: theme.textTheme.bodyLarge?.fontSize),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(AppIcons.search, size: 20),
              hintText: i18n('multiview_search_hint'),
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [tab(PickerSource.follows, i18n('favorites_title')), tab(PickerSource.history, i18n('history'))],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<LiveRoom>>(
            key: ValueKey(_source),
            stream: _rooms,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const AppStatusView(type: AppStatusType.loading, isMini: true);
              final shownIn = widget.shownIn;
              final rooms = pickerRooms(
                snapshot.requireData,
                query: _query,
                supported: (platform) => sites.maybeOf(platform) != null,
                shown: shownIn == null ? null : (room) => shownIn(room) != null,
                preferRealOnline: preferRealOnline,
                realOnlinePlatforms: realOnline,
              );
              if (rooms.isEmpty) {
                return AppStatusView(
                  type: AppStatusType.empty,
                  icon: AppIcons.changeRoom,
                  isMini: true,
                  title: i18n('multiview_no_rooms_title'),
                  subtitle: i18n('multiview_no_rooms_subtitle'),
                );
              }
              return ListView.builder(
                key: const ValueKey('multiview-picker-list'),
                padding: const EdgeInsets.only(bottom: 16),
                itemExtent: _RoomTile.extent(context),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return _RoomTile(room: room, shownIn: shownIn?.call(room), onTap: () => widget.onPicked(room));
                },
              );
            },
          ),
        ),
      ],
    );
    // Too short for the search, the sources and a few rooms (a phone's
    // split screen, large text; A04.1): the whole picker scrolls instead of
    // squeezing the list away.
    final least = MediaQuery.textScalerOf(context).scale(140) + 3 * _RoomTile.extent(context);
    return LayoutBuilder(
      builder: (context, constraints) => !constraints.hasBoundedHeight || constraints.maxHeight >= least
          ? picker
          : SingleChildScrollView(
              key: const ValueKey('multiview-picker-scroll'),
              physics: const PureLiveScrollPhysics(),
              child: SizedBox(height: least, child: picker),
            ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const new({required this.room, required this.shownIn, required this.onTap});

  /// 56 high, or as high as its two lines and padding when larger font
  /// settings or system text make them taller (A01.2).
  static double extent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.2);
    }

    return math.max(56, (12 + line(text.bodyLarge) + line(text.bodySmall)).ceilToDouble());
  }

  final LiveRoom room;
  final int? shownIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = platformName(room.platform);
    return InkWell(
      key: ValueKey('multiview-pick-${room.identityKey}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          spacing: 12,
          children: [
            SizedBox.square(
              dimension: 36,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, radius: 18),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                      child: PlatformLogo(room.platform, size: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.displayNick(platform),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.emphasis.copyWith(color: scheme.onSurface),
                  ),
                  Text(
                    room.title.trim().isEmpty ? platform : room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (shownIn case final index?)
              Container(
                key: ValueKey('multiview-shown-${room.identityKey}'),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(11)),
                child: Text(
                  i18n('multiview_shown_in', args: {'index': '$index'}),
                  style: theme.textTheme.bodySmall?.emphasis.copyWith(color: scheme.onPrimaryContainer),
                ),
              )
            else
              _LiveStatus(room: room),
          ],
        ),
      ),
    );
  }
}

/// Live dot and words (3.x `_LiveStatusBadge`; green while live).
class _LiveStatus extends StatelessWidget {
  const new({required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (color, key) = switch (room.effectiveLiveStatus) {
      LiveStatus.live => (LiveSemanticColors.success(theme.brightness), 'live_now'),
      LiveStatus.replay => (scheme.tertiary, 'replay'),
      LiveStatus.unknown => (scheme.onSurfaceVariant, 'favorite_status_unknown'),
      _ => (scheme.onSurfaceVariant.withValues(alpha: 0.6), 'offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: const SizedBox.square(dimension: 7),
        ),
        Text(i18n(key), style: theme.textTheme.bodySmall?.emphasis.copyWith(color: color)),
      ],
    );
  }
}
