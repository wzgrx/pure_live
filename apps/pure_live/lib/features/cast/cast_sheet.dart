import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/cast/cast_controller.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// F-CAST-01: the cast sheet of the room ⋮ menu ("投屏"). It searches the
/// local network on open, lists renderers, casts the upstream URL of the
/// current line to the one tapped and offers "停止投屏". The cast outlives the
/// sheet and the room ([castProvider]).
Future<void> showCastSheet(
  BuildContext context,
  WidgetRef ref, {
  required RoomDetail detail,
  required PlaybackState state,
}) {
  unawaited(ref.read(castProvider.notifier).refreshStatus());
  final card = detail.card;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
    builder: (context) => CastPanel(
      source: castSourceOf(detail, state),
      room: detail.ref,
      roomTitle: card.anchorName.trim().isEmpty ? card.title : card.anchorName,
    ),
  );
}

/// The content of the cast sheet.
class CastPanel extends ConsumerStatefulWidget {
  const new({required this.source, required this.room, required this.roomTitle, super.key});

  /// What to cast, or why not.
  final CastSource source;

  /// The open room.
  final RoomRef room;

  /// Its streamer.
  final String roomTitle;

  @override
  ConsumerState<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends ConsumerState<CastPanel> {
  StreamSubscription<CastDevice>? _search;
  List<CastDevice> _devices = const [];
  bool _searching = false;
  Object? _searchError;
  bool _attempted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    // Nothing to search for when the address cannot be cast.
    if (widget.source.media != null) _startSearch();
  }

  @override
  void dispose() {
    // Cancelling ends the search and releases the multicast lock.
    unawaited(_search?.cancel());
    super.dispose();
  }

  void _startSearch() {
    unawaited(_search?.cancel());
    _devices = const [];
    _searching = true;
    _searchError = null;
    _search = ref
        .read(castSearchProvider)()
        .listen(
          (device) {
            if (!mounted) return;
            setState(() => _devices = [..._devices.where((known) => known.id != device.id), device]);
          },
          onError: (Object error) {
            if (mounted) setState(() => _searchError = error);
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  void _restart() => setState(_startSearch);

  Future<void> _cast(CastDevice device) async {
    final media = widget.source.media;
    if (media == null) return;
    setState(() {
      _attempted = true;
      _notice = null;
    });
    await ref.read(castProvider.notifier).cast(device, media, room: widget.room, roomTitle: widget.roomTitle);
  }

  Future<void> _stop() async {
    final confirmed = await ref.read(castProvider.notifier).stop();
    if (!mounted) return;
    setState(() => _notice = confirmed ? null : t.cast.stopNotDelivered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cast = ref.watch(castProvider);
    final source = widget.source;
    final connecting = cast.phase == CastPhase.connecting;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.cast.title, style: theme.textTheme.titleMedium)),
                if (source.media != null)
                  IconButton(
                    tooltip: t.cast.searchAgain,
                    icon: const LiveIcon(LiveIcons.refresh),
                    onPressed: _searching || connecting ? null : _restart,
                  ),
              ],
            ),
            if (cast.casting) _CastingCard(cast: cast, room: widget.room, onStop: _stop),
            if (_notice case final notice?) _Hint(icon: LiveIcons.info, text: notice),
            if (source.media == null)
              MessageView(icon: LiveIcons.linkOff, title: t.cast.cannotCast, message: source.problem)
            else ...[
              if (source.needsHeaders) _Hint(icon: LiveIcons.warning, text: t.cast.headersHint),
              if (source.expires) _Hint(icon: LiveIcons.schedule, text: t.cast.expiresHint),
              if (_attempted && cast.phase == CastPhase.failed && cast.failure != null)
                _Hint(
                  icon: LiveIcons.error,
                  text: t.cast.failedWith(reason: castFailureText(cast.failure!)),
                  color: theme.colorScheme.error,
                ),
              if (_searching) ...[
                const SizedBox(height: Space.s2),
                const LinearProgressIndicator(),
                const SizedBox(height: Space.s2),
                Text(t.cast.searching, style: theme.textTheme.bodySmall),
              ],
              if (_devices.isNotEmpty) ...[
                if (_searchError != null) _Hint(icon: LiveIcons.info, text: t.cast.searchInterrupted),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final device in _devices)
                        _DeviceTile(
                          device: device,
                          connecting: connecting && cast.device?.id == device.id,
                          active: cast.casting && cast.device?.id == device.id,
                          enabled: !connecting,
                          onTap: () => unawaited(_cast(device)),
                        ),
                    ],
                  ),
                ),
              ] else if (!_searching && _searchError != null)
                MessageView.error(title: t.cast.searchFailed, message: t.cast.searchFailedHint, onAction: _restart)
              else if (!_searching)
                MessageView(
                  icon: LiveIcons.noPicture,
                  title: t.cast.noDevices,
                  message: t.cast.noDevicesHint,
                  actionLabel: t.cast.searchAgain,
                  onAction: _restart,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CastingCard extends StatelessWidget {
  const new({required this.cast, required this.room, required this.onStop});

  final CastState cast;
  final RoomRef room;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final what = cast.room == room ? t.cast.castingThisRoom : t.cast.castingOther(title: cast.roomTitle ?? '');
    final status = tvStateText(cast.tvState);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Space.s2),
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Row(
          children: [
            LiveIcon(LiveIcons.casting, color: theme.colorScheme.primary),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.cast.castTo(device: cast.device?.name ?? ''), style: theme.textTheme.titleSmall),
                  Text(status == null ? what : '$what · $status', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Space.s2),
            FilledButton.tonal(onPressed: onStop, child: Text(t.cast.stop)),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const new({
    required this.device,
    required this.connecting,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final CastDevice device;
  final bool connecting;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maker = device.manufacturer ?? device.modelName;
    return ListTile(
      key: ValueKey('cast-device-${device.id}'),
      contentPadding: EdgeInsets.zero,
      leading: LiveIcon(active ? LiveIcons.casting : LiveIcons.cast),
      title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(maker == null ? device.host : '$maker · ${device.host}', maxLines: 1),
      trailing: connecting
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : active
          ? LiveIcon(LiveIcons.success, filled: true, color: Theme.of(context).colorScheme.primary)
          : null,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _Hint extends StatelessWidget {
  const new({required this.icon, required this.text, this.color});

  final LiveIcons icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shade = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiveIcon(icon, size: Sizes.iconDense, color: shade),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall!.copyWith(color: shade)),
          ),
        ],
      ),
    );
  }
}
