import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/record/record_look.dart';

/// The mark of a room whose recording is busy (U.2a change 13, by state since
/// U.2a2 c7): "● 录制中 12:34" on red while it records, "重连中 12:34" and
/// "合成中 45%" on a dark pill while it reconnects or joins; nothing while it
/// prepares or does not record. In the picture's corner in every layout,
/// [compact] (mark and figure) while the controls are hidden and in
/// picture-in-picture. The clock ticks only while it records or reconnects,
/// and only this mark redraws.
class RoomRecordingBadge extends ConsumerStatefulWidget {
  /// Creates the mark for [room].
  const new({required this.room, this.compact = false, this.gap = 0, this.showsRecording = true, this.now, super.key});

  /// The room.
  final LiveRoom room;

  /// Only the mark and the figure.
  final bool compact;

  /// Space after the mark when it shows.
  final double gap;

  /// Whether a recording (not reconnecting or joining) shows the mark: not
  /// under the landscape fullscreen bar, whose record button carries the
  /// time (U.2a2 c8).
  final bool showsRecording;

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

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    final task = recording == null || !recording.available ? null : recording.taskFor(widget.room);
    var state = recordBadgeState(task);
    if (state == RecordGlyphState.recording && !widget.showsRecording) state = null;
    if (task == null || state == null) {
      _stopTicking();
      return const SizedBox.shrink();
    }
    // A join shows its progress, which arrives with the recorder's changes;
    // a fixed clock (tests) has nothing to tick for.
    final timed = state != RecordGlyphState.processing;
    if (timed && widget.now == null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _stopTicking();
    }
    final now = (widget.now ?? DateTime.now)();
    return Padding(
      padding: EdgeInsetsDirectional.only(end: widget.gap),
      child: RepaintBoundary(
        child: RecordingBadge(
          key: const ValueKey('live-play-recording-badge'),
          state: state,
          label: recordBadgeLabel(state),
          elapsed: timed ? now.difference(task.displayStartTime) : null,
          progress: timed ? null : recordJoinProgress(task),
          compact: widget.compact,
        ),
      ),
    );
  }
}
