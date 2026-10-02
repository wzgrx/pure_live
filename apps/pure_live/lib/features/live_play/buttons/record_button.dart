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
import 'package:pure_live/shared/record/record_look.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// The record button of the room bar (3.x `RecordActionButton`): its glyph
/// is the room's recording state (docs/T08/T08b/T08b.3: not recording,
/// waiting, preparing, recording, reconnecting, joining, failed; red only
/// while a file is written); a tap opens the record panel
/// (docs/T05/T05g/T05g.1), which replaced 3.x's dialog of five actions.
/// Hidden where this build cannot record.
class RecordButton extends ConsumerStatefulWidget {
  /// Creates the button for [room].
  const new({
    required this.room,
    this.latest,
    this.compact = false,
    this.onVideo = false,
    this.showTime = false,
    this.now,
    super.key,
  });

  /// The room.
  final LiveRoom room;

  /// The room as known at the tap (a new task takes its newest detail);
  /// [room] when null.
  final LiveRoom Function()? latest;

  /// The narrow bar's form: "自动录" as its glyph alone.
  final bool compact;

  /// On the picture (the fullscreen bars, U.2c change 2): white, and
  /// "自动录" as its glyph alone.
  final bool onVideo;

  /// The recording's time beside the glyph while it records (the landscape
  /// fullscreen bar, U.2a2 c8).
  final bool showTime;

  /// The clock of [showTime]; a fixed one (tests) does not tick.
  final DateTime Function()? now;

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
    // The status card's state: only a queued task asks whether a slot is
    // free (the recorder's start gap reads as preparing, U.2f).
    final queued = task?.status == RecordStatus.queued;
    final card = recordCardState(
      task,
      running: queued ? recordSlotsInUse(recording.recorder?.tasks ?? const []) : 0,
      capacity: queued ? recording.settings.current.maxTaskCount : 1,
    );
    final state = recordGlyphState(card);
    final label = recordButtonLabel(card);
    final video = widget.onVideo;
    final onPressed = _pressed;
    Widget glyph({double size = 24}) => RecordGlyph(
      state: state,
      size: size,
      onVideo: video,
      progress: state == RecordGlyphState.processing ? recordJoinProgress(task) : null,
    );
    // U.2a change 13, kept: a room that records by itself when it goes live
    // says "自动录" (U.2f: only while it really waits, not for a stopped or
    // finished task); its glyph is the ring with a clock now (U.2a2 c3).
    if (state == RecordGlyphState.waiting && autoRecordOn(task) && !video) {
      if (widget.compact) {
        return IconButton.filledTonal(
          key: const ValueKey('live-play-record'),
          tooltip: label,
          onPressed: onPressed,
          icon: glyph(size: 20),
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
          icon: glyph(size: 18),
          label: Text(i18n('live_play_auto_record'), maxLines: 1),
        ),
      );
    }
    // c8: the landscape fullscreen bar has room for the time.
    if (state == RecordGlyphState.recording && widget.showTime && task != null) {
      final style = Theme.of(context).textTheme.labelLarge?.emphasis.tabular
          .copyWith(color: video ? OnVideoColors.foreground : null, shadows: video ? OnVideoColors.shadows : null);
      return Tooltip(
        message: label,
        child: TextButton(
          key: const ValueKey('live-play-record'),
          style: TextButton.styleFrom(
            foregroundColor: video ? OnVideoColors.foreground : null,
            minimumSize: const Size.square(kMinInteractiveDimension),
            padding: const EdgeInsetsDirectional.only(start: 12, end: 10),
            shape: const StadiumBorder(),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph(),
              const SizedBox(width: 6),
              _RecordTime(start: task.displayStartTime, now: widget.now, style: style),
            ],
          ),
        ),
      );
    }
    return IconButton(
      key: const ValueKey('live-play-record'),
      tooltip: label,
      color: video ? OnVideoColors.foreground : null,
      onPressed: onPressed,
      icon: glyph(),
    );
  }
}

/// The recording's `12:34` beside the glyph; only this text redraws every
/// second (a fixed clock does not tick).
class _RecordTime extends StatefulWidget {
  const new({required this.start, required this.now, required this.style});

  final DateTime start;
  final DateTime Function()? now;
  final TextStyle? style;

  @override
  State<_RecordTime> createState() => _RecordTimeState();
}

class _RecordTimeState extends State<_RecordTime> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Text(
      formatRecordingTime((widget.now ?? DateTime.now)().difference(widget.start)),
      key: const ValueKey('live-play-record-time'),
      style: widget.style,
      maxLines: 1,
    ),
  );
}
