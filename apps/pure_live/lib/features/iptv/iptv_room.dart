import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';
import 'package:pure_live_app/features/room/playback.dart';

/// A channel with its sources and guide match.
final FutureProviderFamily<IptvChannel, RoomRef> iptvChannelProvider = FutureProvider.autoDispose
    .family<IptvChannel, RoomRef>((ref, room) => ref.watch(iptvSiteProvider).channel(room));

/// The channel's programmes, two days back to one ahead (F-IPTV-06).
final FutureProviderFamily<List<IptvProgramme>, RoomRef> iptvGuideProvider = FutureProvider.autoDispose
    .family<List<IptvProgramme>, RoomRef>((ref, room) async {
      final channel = await ref.watch(iptvChannelProvider(room).future);
      return await ref.read(iptvSiteProvider).guide(channel);
    });

/// The session room key of a catch-up of [programme] on [room]: the live
/// key plus the programme start, so the session itself says what it plays.
String catchupRoomKey(RoomRef room, IptvProgramme programme) =>
    '${room.key}#catchup@${programme.start.millisecondsSinceEpoch}';

/// The programme start a session room key replays on [room], or null when it
/// plays live (or another room).
DateTime? catchupStartOf(String? roomKey, RoomRef room) {
  final prefix = '${room.key}#catchup@';
  if (roomKey == null || !roomKey.startsWith(prefix)) return null;
  final ms = int.tryParse(roomKey.substring(prefix.length));
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// Replays [programme] on [session] (F-IPTV-06): every source that can replay
/// it is a line, opened as a non-continuous stream (playback SES-11). Throws
/// `StreamUnavailable` when no source can.
Future<void> replayProgramme(
  IptvSite site,
  PlaybackSession session,
  IptvChannel channel,
  IptvProgramme programme,
) async {
  final set = site.catchupStreams(channel, programme);
  await session.open(
    PlaybackRequest(
      site: IptvSite.platformId,
      roomKey: catchupRoomKey(channel.ref, programme),
      resolve: (_) async => set,
      initial: set,
      continuousLive: false,
    ),
  );
}

/// The programme covering [now], or null.
IptvProgramme? programmeAt(List<IptvProgramme> programmes, DateTime now) =>
    programmes.where((programme) => programme.covers(now)).firstOrNull;

/// The IPTV part of the room info (spec/modules/iptv.md §5): the programme on
/// air (or being replayed) with its progress and description, what comes
/// next, the programme guide and "回到直播".
class IptvRoomPanel extends ConsumerStatefulWidget {
  const new({required this.detail, this.now, super.key});

  final RoomDetail detail;

  /// Clock for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<IptvRoomPanel> createState() => _IptvRoomPanelState();
}

class _IptvRoomPanelState extends ConsumerState<IptvRoomPanel> {
  Timer? _tick;
  bool _switching = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // The programme on air changes by the minute.
    if (widget.now == null) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// One switch at a time; the session's room key then tells what plays.
  Future<void> _switch(Future<void> Function() action, {required String done, required String failed}) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await action();
      _toast(done);
    } on Object {
      _toast(failed);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _backToLive(PlaybackSession session) => _switch(
    () => openRoom(
      site: ref.read(sitesProvider)[IptvSite.platformId]!,
      settings: ref.read(storeProvider).settings,
      session: session,
      detail: widget.detail,
    ),
    done: '已回到直播',
    failed: '回到直播失败，可以点画面上的重试',
  );

  Future<void> _openGuide(PlaybackSession session, DateTime? replaying) async {
    final room = widget.detail.ref;
    final chosen = await showModalBottomSheet<IptvProgramme>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => IptvGuideSheet(room: room, now: _now(), replaying: replaying),
    );
    if (chosen == null || !mounted) return;
    final now = _now();
    switch (programmePhase(chosen, now)) {
      case ProgrammePhase.upcoming:
        _toast('节目还没开始');
      case ProgrammePhase.live:
        if (replaying != null) await _backToLive(session);
      case ProgrammePhase.past:
        final site = ref.read(iptvSiteProvider);
        final channel = await ref.read(iptvChannelProvider(room).future);
        switch (site.availability(channel, chosen)) {
          case CatchupAvailability.available:
            await _switch(
              () => replayProgramme(site, session, channel, chosen),
              done: '正在回看：${chosen.title}',
              failed: '这个节目不能回看',
            );
          case CatchupAvailability.disabled:
            _toast('这个频道没有开放回看');
          case CatchupAvailability.expired:
            _toast('超出了回看的时间范围');
          case CatchupAvailability.unsupported:
            _toast('这个节目不能回看');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.detail.ref;
    // The session PlayerView holds; its room key says live or catch-up.
    final session = ref.watch(playbackSessionProvider);
    return StreamBuilder<PlaybackState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snapshot) => _panel(context, session, catchupStartOf(snapshot.data?.roomKey, room)),
    );
  }

  Widget _panel(BuildContext context, PlaybackSession session, DateTime? replaying) {
    final room = widget.detail.ref;
    final switching = _switching;
    final guide = ref.watch(iptvGuideProvider(room));
    final channel = ref.watch(iptvChannelProvider(room)).value;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final now = _now();
    final programmes = guide.value ?? const <IptvProgramme>[];
    final replay = replaying == null ? null : programmes.where((p) => p.start == replaying).firstOrNull;
    final shown = replay ?? programmeAt(programmes, now);
    final next = shown == null ? null : programmes.where((p) => !p.start.isBefore(shown.stop)).firstOrNull;
    final matched = channel?.guideChannelId != null;

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(replaying == null ? Icons.live_tv : Icons.history, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: Space.s2),
                Text(replaying == null ? '正在播出' : '回看中', style: theme.textTheme.labelLarge),
                if ((channel?.sources.length ?? 0) > 1) ...[
                  const SizedBox(width: Space.s2),
                  Text('${channel!.sources.length} 条线路', style: muted),
                ],
              ],
            ),
            const SizedBox(height: Space.s2),
            if (shown != null) ...[
              Text(shown.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.s1),
              Text('${clockText(shown.start)}–${clockText(shown.stop)}', style: muted),
              if (replay == null) ...[
                const SizedBox(height: Space.s1),
                LinearProgressIndicator(
                  value: (now.difference(shown.start).inSeconds / max(1, shown.stop.difference(shown.start).inSeconds))
                      .clamp(0.0, 1.0),
                ),
              ],
              if (shown.description case final text? when text.trim().isNotEmpty) ...[
                const SizedBox(height: Space.s2),
                Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: muted),
              ],
              if (next != null && replay == null) ...[
                const SizedBox(height: Space.s2),
                Text('接下来 ${clockText(next.start)} ${next.title}', style: muted),
              ],
            ] else if (guide.isLoading || channel == null)
              Text('正在读取节目单…', style: muted)
            else if (!matched)
              Text('没有匹配到节目单：添加或更换节目单源后会自动匹配', style: muted)
            else
              Text('节目单里暂时没有这个时段的节目', style: muted),
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                if (matched)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.event_note, size: 18),
                    label: const Text('节目单'),
                    onPressed: switching ? null : () => _openGuide(session, replaying),
                  )
                else if (channel != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_note_outlined, size: 18),
                    label: const Text('节目单源'),
                    onPressed: () => context.push(iptvGuideLocation),
                  ),
                if (replaying != null)
                  FilledButton.icon(
                    icon: switching
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.live_tv, size: 18),
                    label: const Text('回到直播'),
                    onPressed: switching ? null : () => _backToLive(session),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The programme guide sheet: days as headings, the programme on air marked
/// and scrolled to; returns the programme the user tapped.
class IptvGuideSheet extends ConsumerStatefulWidget {
  const new({required this.room, required this.now, this.replaying, super.key});

  final RoomRef room;

  /// The moment the sheet opened.
  final DateTime now;

  /// Start of the programme being replayed, if any.
  final DateTime? replaying;

  @override
  ConsumerState<IptvGuideSheet> createState() => _IptvGuideSheetState();
}

class _IptvGuideSheetState extends ConsumerState<IptvGuideSheet> {
  static const double _headerHeight = 36;
  static const double _rowHeight = 64;
  bool _scrolled = false;

  String _day(DateTime at) {
    final local = at.toLocal();
    final today = widget.now.toLocal();
    final days = DateTime(local.year, local.month, local.day).difference(DateTime(today.year, today.month, today.day));
    final label = switch (days.inDays) {
      0 => '今天',
      -1 => '昨天',
      -2 => '前天',
      1 => '明天',
      _ => '',
    };
    return '$label ${local.month}月${local.day}日'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final guide = ref.watch(iptvGuideProvider(widget.room));
    final channel = ref.watch(iptvChannelProvider(widget.room)).value;
    final site = ref.watch(iptvSiteProvider);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => guide.when(
        loading: () => const LoadingView(),
        error: (error, _) =>
            MessageView.error(title: '读取节目单失败', onAction: () => ref.invalidate(iptvGuideProvider(widget.room))),
        data: (programmes) {
          if (programmes.isEmpty) {
            return const MessageView(icon: Icons.event_busy, title: '没有节目', message: '节目单里没有这个频道前后两天的节目。');
          }
          final rows = <Object>[];
          String? day;
          for (final programme in programmes) {
            final label = _day(programme.start);
            if (label != day) rows.add(day = label);
            rows.add(programme);
          }
          final liveIndex = rows.indexWhere((row) => row is IptvProgramme && row.covers(widget.now));
          if (!_scrolled && liveIndex > 0) {
            _scrolled = true;
            var offset = 0.0;
            for (final row in rows.take(liveIndex)) {
              offset += row is String ? _headerHeight : _rowHeight;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.hasClients) {
                controller.jumpTo((offset - _rowHeight).clamp(0, controller.position.maxScrollExtent));
              }
            });
          }
          return ListView.builder(
            controller: controller,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row is String) {
                return SizedBox(
                  height: _headerHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(row, style: theme.textTheme.titleSmall),
                    ),
                  ),
                );
              }
              final programme = row as IptvProgramme;
              final phase = programmePhase(programme, widget.now);
              final replaying = widget.replaying == programme.start;
              final available =
                  phase == ProgrammePhase.past &&
                  channel != null &&
                  site.availability(channel, programme) == CatchupAvailability.available;
              final Widget? trailing = switch (phase) {
                _ when replaying => const Text('回看中'),
                ProgrammePhase.live => const LiveBadge(),
                ProgrammePhase.past when available => const Icon(Icons.replay, size: 20),
                ProgrammePhase.past => Text('不可回看', style: theme.textTheme.bodySmall),
                ProgrammePhase.upcoming => null,
              };
              return SizedBox(
                height: _rowHeight,
                child: ListTile(
                  selected: phase == ProgrammePhase.live || replaying,
                  leading: Text(clockText(programme.start), style: LiveTheme.of(context).numeric),
                  title: Text(programme.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: programme.subtitle == null
                      ? null
                      : Text(programme.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: trailing,
                  enabled: phase != ProgrammePhase.upcoming,
                  onTap: () => Navigator.pop(context, programme),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
