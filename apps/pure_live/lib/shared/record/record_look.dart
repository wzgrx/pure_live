import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// How a room's recording looks (docs/T08/T08b/T08b.3): one glyph in
/// seven states for the room bar's record button, the fullscreen bars, the
/// record panel's status card and the recording centre, chosen from the
/// task's card state — never from `RecordStatus.isActive`, which counts
/// preparing and joining as recording. Red is for [RecordCardState.recording]
/// alone.
RecordGlyphState recordGlyphState(RecordCardState state) => switch (state) {
  RecordCardState.idle || RecordCardState.saved => RecordGlyphState.idle,
  // Both start by themselves later: for the room, or for a free slot (X2).
  RecordCardState.waiting || RecordCardState.queued => RecordGlyphState.waiting,
  RecordCardState.preparing => RecordGlyphState.preparing,
  RecordCardState.recording => RecordGlyphState.recording,
  RecordCardState.reconnecting => RecordGlyphState.reconnecting,
  RecordCardState.processing => RecordGlyphState.processing,
  RecordCardState.failed => RecordGlyphState.failed,
};

/// The record button's words in [state] (its tooltip, what a screen reader
/// says).
String recordButtonLabel(RecordCardState state) => switch (state) {
  RecordCardState.idle || RecordCardState.saved => i18n('record'),
  RecordCardState.waiting => i18n('live_play_auto_record'),
  RecordCardState.queued => i18n('record_panel_queued_title'),
  RecordCardState.preparing => i18n('record_panel_preparing_title'),
  RecordCardState.recording => i18n('recording'),
  RecordCardState.reconnecting => i18n('record_badge_reconnecting'),
  RecordCardState.processing => i18n('record_badge_processing'),
  RecordCardState.failed => i18n('record_panel_failed_title'),
};

/// The mark on the picture of [task] (c7): recording, reconnecting or
/// joining; null while nothing is being written or joined (preparing shows
/// no mark).
RecordGlyphState? recordBadgeState(RecordTask? task) => switch (task?.status) {
  RecordStatus.running => RecordGlyphState.recording,
  RecordStatus.reconnecting => RecordGlyphState.reconnecting,
  RecordStatus.processing => RecordGlyphState.processing,
  _ => null,
};

/// The mark's word: "录制中", "重连中", "合成中".
String recordBadgeLabel(RecordGlyphState state) => switch (state) {
  RecordGlyphState.reconnecting => i18n('record_badge_reconnecting'),
  RecordGlyphState.processing => i18n('record_badge_processing'),
  _ => i18n('recording'),
};

/// The join's progress of [task] from 0 to 1, or null before FFmpeg
/// reports.
double? recordJoinProgress(RecordTask? task) {
  final progress = task?.mergeProgress;
  return progress == null || progress.isNaN ? null : progress.clamp(0.0, 1.0);
}
