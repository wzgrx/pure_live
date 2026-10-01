import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// The record button of the room bar (3.x `RecordActionButton`): shows the
/// room's task state (not recording, records when live, recording); a tap
/// opens the record panel (docs/ui/compare/U.2f), which replaced 3.x's
/// dialog of five actions. Hidden where this build cannot record.
class RecordButton extends ConsumerStatefulWidget {
  /// Creates the button for [room].
  const new({required this.room, this.latest, this.compact = false, this.onVideo = false, super.key});

  /// The room.
  final LiveRoom room;

  /// The room as known at the tap (a new task takes its newest detail);
  /// [room] when null.
  final LiveRoom Function()? latest;

  /// The narrow bar's form: "自动录" as its timer alone.
  final bool compact;

  /// On the picture (the fullscreen bars, U.2c change 2): white, and
  /// "自动录" as its timer alone.
  final bool onVideo;

  @override
  ConsumerState<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends ConsumerState<RecordButton> {
  StreamSubscription<List<RecordTask>>? _changes;
  StreamSubscription<RecordNotice>? _notices;

  AppRecording? get _recording => ref.read(recordingProvider);

  @override
  void initState() {
    super.initState();
    final recorder = _recording?.recorder;
    _changes = recorder?.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _notices = recorder?.notices.listen((notice) {
      if (!mounted || notice.task.platform != widget.room.platform || notice.task.roomId != widget.room.roomId) return;
      if (recordNoticeText(notice) case final text?) AppNavigator.toast(text);
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_notices?.cancel());
    super.dispose();
  }

  void _pressed() => showRecordPanel(context, room: widget.latest ?? () => widget.room);

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    if (recording == null || !recording.available) return const SizedBox.shrink();
    final task = recording.taskFor(widget.room);
    final active = task?.status.isActive ?? false;
    final onPressed = _pressed;
    // docs/ui/compare/U.2a, change 13: idle is a grey ring around a red dot;
    // a room that records by itself when it goes live says "自动录" with a
    // timer; a recording room is a white dot on red (blinking unless the
    // system asks for less motion) and the picture's corner shows the time.
    // U.2f: "自动录" only while it really waits for the room (the panel's
    // "开播自动录"), not for a stopped or finished task.
    if (active) {
      return IconButton(
        key: const ValueKey('live-play-record'),
        tooltip: i18n('recording'),
        onPressed: onPressed,
        icon: const RecordGlyph(state: RecordGlyphState.recording, size: 26),
      );
    }
    if (autoRecordOn(task)) {
      final label = i18n('live_play_auto_record');
      if (widget.onVideo) {
        return IconButton(
          key: const ValueKey('live-play-record'),
          tooltip: label,
          color: OnVideoColors.foreground,
          onPressed: onPressed,
          icon: const Icon(AppIcons.autoRecord, size: 22),
        );
      }
      if (widget.compact) {
        return IconButton.filledTonal(
          key: const ValueKey('live-play-record'),
          tooltip: label,
          onPressed: onPressed,
          icon: const Icon(AppIcons.autoRecord, size: 20),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton.tonalIcon(
          key: const ValueKey('live-play-record'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
            textStyle: Theme.of(context).textTheme.labelLarge?.emphasis,
          ),
          onPressed: onPressed,
          icon: const Icon(AppIcons.autoRecord, size: 18),
          label: Text(label, maxLines: 1),
        ),
      );
    }
    return IconButton(
      key: const ValueKey('live-play-record'),
      tooltip: i18n('record'),
      onPressed: onPressed,
      icon: RecordGlyph(state: RecordGlyphState.idle, ringColor: widget.onVideo ? OnVideoColors.foreground : null),
    );
  }
}
