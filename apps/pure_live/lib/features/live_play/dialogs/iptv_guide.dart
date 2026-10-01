import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/iptv_guide_rows.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

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

/// Where the room keeps its guide (docs/ui/compare/U.2g c16): under the
/// picture in portrait, on the right in landscape fullscreen, in the right
/// column of a wide window. The picture's guide button and the replay mark
/// call [reveal]; the page decides what that means in its layout (scroll to
/// the programme on air, open the panel, unfold the column).
class IptvGuideScope extends InheritedWidget {
  /// Creates the scope.
  const new({required this.reveal, required super.child, super.key});

  /// Shows the guide at the programme being watched.
  final VoidCallback reveal;

  /// The page's scope, or null outside a live room.
  static IptvGuideScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<IptvGuideScope>();

  @override
  bool updateShouldNotify(IptvGuideScope oldWidget) => false;
}

/// The guide button (the picture's top bar, 3.x `IptvScheduleDialog`'s
/// button): shows the room's guide where the layout keeps it; without a
/// room page around [context], in a sheet.
Future<void> showIptvGuide(BuildContext context, LiveRoomController controller) async {
  final scope = IptvGuideScope.maybeOf(context);
  if (scope != null) {
    scope.reveal();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.7,
      child: IptvGuideView(controller: controller, onClose: () => Navigator.of(sheetContext).pop()),
    ),
  );
}

/// The channel's programme guide with catch-up (docs/ui/compare/U.2g c16–c19,
/// 3.x `IptvScheduleDialog`): one component wherever it is placed. The head
/// says "节目单" and how long the channel keeps programmes; while a programme
/// is replayed, a bar says which and offers "返回直播"; the programmes are
/// grouped by day, the one being watched on the third line. A tap on an
/// ended programme replays it, on the one on air goes back to live; the
/// others say why not. [onClose] adds ✕ (the landscape panel).
class IptvGuideView extends ConsumerStatefulWidget {
  /// Creates the guide.
  const new({required this.controller, this.onClose, this.reveal, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the guide (a panel); null for a guide that stays.
  final VoidCallback? onClose;

  /// Ticks when the guide should scroll back to the programme being watched.
  final Listenable? reveal;

  @override
  ConsumerState<IptvGuideView> createState() => _IptvGuideViewState();
}

enum _Load { loading, failed, unconfigured, ready }

class _IptvGuideViewState extends ConsumerState<IptvGuideView> {
  final ScrollController _scroll = ScrollController();
  _Load _load = _Load.loading;
  List<EpgProgramme> _programmes = const [];
  Timer? _clock;
  bool _anchored = false;
  int _loads = 0;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    // 3.x redrew the whole dialog every 30 s; the marks of the lines move on
    // as programmes start and end.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    widget.reveal?.addListener(_jump);
  }

  @override
  void didUpdateWidget(IptvGuideView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reveal != widget.reveal) {
      oldWidget.reveal?.removeListener(_jump);
      widget.reveal?.addListener(_jump);
    }
  }

  @override
  void dispose() {
    widget.reveal?.removeListener(_jump);
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _set(_Load load) {
    if (_load != load && mounted) setState(() => _load = load);
  }

  Future<void> _read() async {
    final load = ++_loads;
    final source = ref.read(storeProvider).settings.get(Settings.selectedSourceId);
    if (source.trim().isEmpty) {
      // c19: no guide imported, which 3.x showed as "no programmes".
      _set(_Load.unconfigured);
      return;
    }
    _set(_Load.loading);
    final now = _room.now();
    final days = _room.room.catchUp.days;
    final back = days != null && days.isFinite && days > 0 ? days.ceil().clamp(1, 7) : 2;
    final midnight = DateTime(now.year, now.month, now.day);
    try {
      final programmes = await loadChannelGuide(
        _room,
        guideSourceId: source,
        from: midnight.subtract(Duration(days: back)),
        to: midnight.add(const Duration(days: 2)),
      );
      if (!mounted || load != _loads) return;
      setState(() {
        _programmes = programmes;
        _load = _Load.ready;
        _anchored = false;
      });
    } on Object {
      if (!mounted || load != _loads) return;
      setState(() => _load = _Load.failed);
    }
  }

  void _jump() {
    if (!_scroll.hasClients) return;
    final entries = _entries();
    _scroll.jumpTo(guideAnchorOffset(entries).clamp(0, _scroll.position.maxScrollExtent));
  }

  List<GuideEntry> _entries() =>
      guideEntries(_programmes, now: _room.now(), catchUp: _room.room.catchUp, replaying: _room.catchup);

  Future<void> _tap(GuideProgramme entry) async {
    switch (entry.kind) {
      case GuideProgrammeKind.scheduled:
        AppNavigator.toast(i18n('program_scheduled_hint'));
      case GuideProgrammeKind.gone:
        AppNavigator.toast(i18n('catchup_unavailable'));
      case GuideProgrammeKind.replaying:
        return;
      case GuideProgrammeKind.live:
        await _room.backToLive();
      case GuideProgrammeKind.replayable:
        final reason = await _room.playCatchup(entry.programme);
        // A replay that does not open shows as the picture's playback
        // failure (U.2g 提示条), not as a message.
        if (reason != null && reason != 'play_video_failed') AppNavigator.toast(i18n(reason));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('iptv-guide'),
      color: scheme.surface,
      child: ListenableBuilder(
        listenable: _room,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Head(
              note: _load == _Load.ready ? guideCatchupNote(_room.room.catchUp, _room.now()) : '',
              onClose: widget.onClose,
            ),
            if (_room.catchup case final programme?) _CatchupBar(controller: _room, programme: programme),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_load) {
      case _Load.loading:
        return _GuideState(
          key: const ValueKey('iptv-guide-loading'),
          leading: const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          text: i18n('live_play_guide_loading'),
        );
      case _Load.failed:
        return _GuideState(
          key: const ValueKey('iptv-guide-failed'),
          icon: AppIcons.guideFailed,
          title: i18n('live_play_guide_failed'),
          text: i18n('load_failed'),
          action: i18n('retry'),
          actionIcon: AppIcons.refresh,
          onAction: () => unawaited(_read()),
        );
      case _Load.unconfigured:
        return _GuideState(
          key: const ValueKey('iptv-guide-unconfigured'),
          icon: AppIcons.guideTitle,
          title: i18n('iptv_no_guides'),
          text: i18n('iptv_no_guides_desc'),
          action: i18n('live_play_guide_import'),
          actionIcon: AppIcons.add,
          onAction: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kIptv)),
        );
      case _Load.ready:
        break;
    }
    if (_programmes.isEmpty) {
      return _GuideState(
        key: const ValueKey('iptv-guide-empty'),
        icon: AppIcons.guideEmpty,
        title: i18n('no_upcoming_programs'),
        text: i18n('live_play_guide_channel_empty'),
      );
    }
    final entries = _entries();
    if (!_anchored) {
      _anchored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump());
    }
    final now = _room.now();
    return ListView.builder(
      key: const ValueKey('iptv-guide-list'),
      controller: _scroll,
      itemCount: entries.length,
      itemExtentBuilder: (index, _) => entries[index] is GuideDay ? guideDayHeight : guideRowHeight,
      itemBuilder: (context, index) => switch (entries[index]) {
        GuideDay(:final day) => _DayHeading(text: guideDayLabel(day, now)),
        final GuideProgramme entry => _ProgrammeRow(
          key: ValueKey('iptv-programme-$index'),
          entry: entry,
          replaying: _room.catchup != null,
          onTap: () => unawaited(_tap(entry)),
        ),
      },
    );
  }
}

class _Head extends StatelessWidget {
  const new({required this.note, this.onClose});

  final String note;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: onClose == null ? 12 : 4),
        child: Row(
          children: [
            Icon(AppIcons.guideTitle, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(i18n('live_play_guide_title'), style: theme.textTheme.titleMedium?.emphasis),
            if (note.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  note,
                  key: const ValueKey('iptv-guide-catchup-note'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            const Spacer(),
            if (onClose case final close?)
              IconButton(
                key: const ValueKey('iptv-guide-close'),
                tooltip: i18n('close'),
                onPressed: close,
                icon: const Icon(AppIcons.close),
              ),
          ],
        ),
      ),
    );
  }
}

/// "正在回看 · 今天 19:30 节目名" and "返回直播" (c18).
class _CatchupBar extends StatelessWidget {
  const new({required this.controller, required this.programme});

  final LiveRoomController controller;
  final EpgProgramme programme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = controller.now();
    final start = programme.start.toLocal();
    final day = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    final when = switch (today.difference(day).inHours) {
      0 => i18n('history_section_today'),
      24 => i18n('history_section_yesterday'),
      _ => '${start.month}/${start.day}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: DecoratedBox(
        key: const ValueKey('iptv-guide-catchup'),
        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n('live_play_guide_replaying_at', args: {'when': when, 'time': guideTime(start)}),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    Text(
                      programme.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.emphasis.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('iptv-back-to-live'),
                onPressed: () => unawaited(controller.backToLive()),
                icon: const Icon(AppIcons.liveNow, size: 18),
                label: Text(i18n('return_to_live')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.emphasis.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _ProgrammeRow extends StatelessWidget {
  const new({required this.entry, required this.onTap, this.replaying = false, super.key});

  final GuideProgramme entry;
  final VoidCallback onTap;

  /// A programme is being replayed: the one on air is not the one watched.
  final bool replaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = entry.kind;
    final watched = kind == GuideProgrammeKind.replaying || (kind == GuideProgrammeKind.live && !replaying);
    final faded = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    final timeStyle = theme.textTheme.bodyMedium?.regular.tabular.copyWith(
      color: kind == GuideProgrammeKind.gone ? faded : scheme.onSurfaceVariant,
    );
    final titleStyle = theme.textTheme.bodyLarge
        ?.copyWith(fontSize: 15, fontWeight: watched ? FontWeight.w600 : FontWeight.w400)
        .copyWith(color: kind == GuideProgrammeKind.gone ? faded : scheme.onSurface);
    final trailing = switch (kind) {
      GuideProgrammeKind.replayable => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.catchup, size: 16, color: scheme.primary),
          const SizedBox(width: 3),
          Text(
            i18n('live_play_guide_replay_short'),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
          ),
        ],
      ),
      GuideProgrammeKind.live => DecoratedBox(
        key: const ValueKey('iptv-live-mark'),
        decoration: BoxDecoration(color: LiveSemanticColors.live, borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.liveNow, size: 13, color: LiveSemanticColors.onLive),
              const SizedBox(width: 3),
              Text(
                i18n('live_tag'),
                style: theme.textTheme.labelMedium?.emphasis.copyWith(color: LiveSemanticColors.onLive),
              ),
            ],
          ),
        ),
      ),
      GuideProgrammeKind.replaying => Text(
        i18n('live_play_guide_replaying'),
        style: theme.textTheme.bodyMedium?.emphasis.copyWith(color: scheme.primary),
      ),
      GuideProgrammeKind.gone || GuideProgrammeKind.scheduled => null,
    };
    final highlighted = watched;
    return Tooltip(
      message: kind == GuideProgrammeKind.gone ? i18n('catchup_unavailable') : '',
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted ? scheme.primary.withValues(alpha: 0.07) : null,
            border: highlighted ? Border(left: BorderSide(color: scheme.primary, width: 3)) : null,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(highlighted ? 13 : 16, 0, 12, 0),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text(guideTime(entry.programme.start), style: timeStyle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(entry.programme.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading, failed, no guide, no programmes (3.x's three states and c19).
class _GuideState extends StatelessWidget {
  const new({
    required this.text,
    this.icon,
    this.leading,
    this.title,
    this.action,
    this.actionIcon,
    this.onAction,
    super.key,
  });

  final IconData? icon;
  final Widget? leading;
  final String? title;
  final String text;
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?leading,
            if (icon != null) Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            if (title case final words?) ...[
              const SizedBox(height: 6),
              Text(
                words,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.emphasis.copyWith(color: scheme.onSurface),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('iptv-guide-action'),
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
