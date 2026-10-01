import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The "● 录制中 12:34" mark of a room that records (U.2a change 13): in the
/// picture's corner in every layout, [compact] (dot and time) while the
/// controls are hidden and in picture-in-picture. Nothing when the room does
/// not record; the clock ticks only while it does, and only this mark
/// redraws.
class RoomRecordingBadge extends ConsumerStatefulWidget {
  /// Creates the mark for [room].
  const new({required this.room, this.compact = false, this.gap = 0, this.now, super.key});

  /// The room.
  final LiveRoom room;

  /// Only the dot and the time.
  final bool compact;

  /// Space after the mark when it shows.
  final double gap;

  /// The clock; a fixed one (tests) does not tick.
  final DateTime Function()? now;

  @override
  ConsumerState<RoomRecordingBadge> createState() => _RoomRecordingBadgeState();
}

class _RoomRecordingBadgeState extends ConsumerState<RoomRecordingBadge> {
  StreamSubscription<List<RecordTask>>? _changes;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _changes = ref.read(recordingProvider)?.recorder?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _tick?.cancel();
    super.dispose();
  }

  RecordTask? _active() {
    final recording = ref.watch(recordingProvider);
    if (recording == null || !recording.available) return null;
    final task = recording.taskFor(widget.room);
    return task != null && task.status.isActive ? task : null;
  }

  @override
  Widget build(BuildContext context) {
    final task = _active();
    if (task == null) {
      _tick?.cancel();
      _tick = null;
      return const SizedBox.shrink();
    }
    // A fixed clock (tests) has nothing to tick for.
    if (widget.now == null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    final now = (widget.now ?? DateTime.now)();
    return Padding(
      padding: EdgeInsetsDirectional.only(end: widget.gap),
      child: RepaintBoundary(
        child: RecordingBadge(
          key: const ValueKey('live-play-recording-badge'),
          elapsed: now.difference(task.displayStartTime),
          label: i18n('recording'),
          compact: widget.compact,
        ),
      ),
    );
  }
}
