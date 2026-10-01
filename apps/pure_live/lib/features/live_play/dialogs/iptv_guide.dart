import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The programmes of the IPTV channel playing in [controller] from [from]
/// to [to] (3.x `loadFullChannelSchedule`): the room's guide key, else the
/// selected guide's channel of the same id. Empty without a guide.
Future<List<EpgProgramme>> loadChannelGuide(
  LiveRoomController controller, {
  required String guideSourceId,
  required DateTime from,
  required DateTime to,
}) async {
  final site = controller.site;
  if (site is! IptvSite) return const [];
  final reference = controller.room.epgId?.trim() ?? '';
  if (reference.isEmpty || guideSourceId.isEmpty) return const [];
  final key =
      resolveGuideReference(guideSourceId, reference, await site.library.guideChannels(guideSourceId)) ?? reference;
  final programmes = await site.library.programmes(key, from: from, to: to);
  return [...programmes]..sort((a, b) => a.start.compareTo(b.start));
}

/// The channel's programme guide with catch-up (3.x `IptvScheduleDialog`):
/// today and the days kept, the programme on air marked; tapping an ended
/// programme replays it, the one on air returns to live.
Future<void> showIptvGuide(BuildContext context, LiveRoomController controller) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => IptvGuideSheet(controller: controller),
);

/// The guide's sheet.
class IptvGuideSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  ConsumerState<IptvGuideSheet> createState() => _IptvGuideSheetState();
}

class _IptvGuideSheetState extends ConsumerState<IptvGuideSheet> {
  late final Future<List<EpgProgramme>> _programmes;
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    final now = widget.controller.now();
    final days = widget.controller.room.catchUp.days;
    final back = days != null && days.isFinite && days > 0 ? days.ceil().clamp(1, 7) : 2;
    final midnight = DateTime(now.year, now.month, now.day);
    _programmes = loadChannelGuide(
      widget.controller,
      guideSourceId: ref.read(storeProvider).settings.get(Settings.selectedSourceId),
      from: midnight.subtract(Duration(days: back)),
      to: midnight.add(const Duration(days: 2)),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _play(EpgProgramme programme) async {
    final reason = await widget.controller.playCatchup(programme);
    if (reason != null) {
      AppNavigator.toast(i18n(reason));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppNavigator.toast(
      widget.controller.catchup == null ? i18n('returned_to_live') : '${i18n('playing_catchup')}: ${programme.title}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(i18n('view_schedule'), style: theme.textTheme.titleMedium)),
                  if (controller.catchup != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('iptv-back-to-live'),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await controller.backToLive();
                        AppNavigator.toast(i18n('returned_to_live'));
                      },
                      icon: const Icon(Icons.live_tv_rounded, size: 18),
                      label: Text(i18n('live_play_back_to_live')),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<EpgProgramme>>(
                future: _programmes,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppStatusView(
                      type: AppStatusType.error,
                      isMini: true,
                      title: i18n('live_play_guide_failed'),
                      subtitle: '',
                    );
                  }
                  final programmes = snapshot.data;
                  if (programmes == null) return const Center(child: CircularProgressIndicator());
                  if (programmes.isEmpty) {
                    return AppStatusView(
                      type: AppStatusType.empty,
                      isMini: true,
                      title: i18n('live_play_guide_empty'),
                      subtitle: i18n('live_play_guide_empty_hint'),
                    );
                  }
                  return _list(context, programmes);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<EpgProgramme> programmes) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final now = controller.now();
    final catchUp = controller.room.catchUp;
    final onAir = programmes.indexWhere(
      (p) => classifyIptvProgramme(start: p.start, stop: p.stop, now: now) == IptvProgrammePhase.live,
    );
    if (!_scrolled && onAir > 0) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo((onAir * 64.0 - 128).clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    }
    String two(int value) => value.toString().padLeft(2, '0');
    String time(DateTime value) => '${two(value.hour)}:${two(value.minute)}';
    return ListView.builder(
      controller: _scroll,
      itemExtent: 64,
      itemCount: programmes.length,
      itemBuilder: (context, index) {
        final programme = programmes[index];
        final phase = classifyIptvProgramme(start: programme.start, stop: programme.stop, now: now);
        final replayable =
            phase == IptvProgrammePhase.catchup &&
            evaluateIptvCatchupAvailability(
                  programmeStop: programme.stop,
                  now: now,
                  mode: catchUp.mode,
                  source: catchUp.source,
                  days: catchUp.days,
                ) ==
                IptvCatchupAvailability.available;
        final playing =
            controller.catchup == programme || (controller.catchup == null && phase == IptvProgrammePhase.live);
        final day = programme.start.day == now.day ? '' : '${programme.start.month}-${programme.start.day} ';
        final (String tag, Color? color) = switch (phase) {
          IptvProgrammePhase.live => (i18n('now_playing'), theme.colorScheme.primary),
          IptvProgrammePhase.catchup => (replayable ? i18n('live_play_guide_replay') : '', theme.colorScheme.tertiary),
          IptvProgrammePhase.scheduled => ('', null),
        };
        return ListTile(
          key: ValueKey('iptv-programme-$index'),
          selected: playing,
          enabled: phase != IptvProgrammePhase.scheduled,
          leading: SizedBox(width: 72, child: Text('$day${time(programme.start)}', style: theme.textTheme.labelMedium)),
          title: Text(programme.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${time(programme.start)} - ${time(programme.stop)}', style: theme.textTheme.bodySmall),
          trailing: tag.isEmpty ? null : Text(tag, style: theme.textTheme.labelSmall?.copyWith(color: color)),
          onTap: phase == IptvProgrammePhase.scheduled ? null : () => unawaited(_play(programme)),
        );
      },
    );
  }
}
