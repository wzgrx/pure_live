import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/features/recorder/logic/recorder_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The label of a recording centre filter (U.7a c6).
String recorderFilterLabel(RecorderFilter filter) => i18n(switch (filter) {
  RecorderFilter.all => 'recorder_tab_all',
  RecorderFilter.active => 'recorder_filter_active',
  RecorderFilter.waiting => 'recorder_tab_waiting',
  RecorderFilter.saved => 'recorder_filter_saved',
  RecorderFilter.failed => 'recorder_tab_failed',
});

/// The stage of [stage] (3.x `_failureStageText`).
String recordStageText(String? stage) {
  if (stage == 'ffmpeg' || (stage?.startsWith('ffmpeg.') ?? false)) return i18n('recorder_stage_ffmpeg');
  return i18n(switch (stage) {
    'room' => 'recorder_stage_room',
    'quality' => 'recorder_stage_quality',
    'stream' => 'recorder_stage_stream',
    'network' => 'recorder_stage_network',
    'merge' => 'recorder_stage_merge',
    'scheduler' => 'recorder_stage_scheduler',
    'status' => 'recorder_stage_status',
    'background' => 'recorder_stage_background',
    _ => 'recorder_stage_unknown',
  });
}

/// The words for an FFmpeg failure (3.x `_friendlyError`); null when the
/// diagnostic itself says more.
String? recordFailureKindText(FfmpegFailureKind? kind) => switch (kind) {
  FfmpegFailureKind.storageFull => i18n('recorder_storage_full'),
  FfmpegFailureKind.outputPath => i18n('path_or_permission_error'),
  FfmpegFailureKind.httpAccess ||
  FfmpegFailureKind.transport ||
  FfmpegFailureKind.unexpectedEof ||
  FfmpegFailureKind.leaseRefresh => i18n('recorder_transport_failed'),
  FfmpegFailureKind.inputOpen => i18n('recorder_input_open_failed'),
  FfmpegFailureKind.inputFormat => i18n('recorder_input_format_failed'),
  FfmpegFailureKind.decoder => i18n('recorder_decoder_failed'),
  FfmpegFailureKind.outputIntegrity => i18n('recorder_input_integrity_failed'),
  FfmpegFailureKind.command || FfmpegFailureKind.native || null => null,
};

/// The restriction's explanation (the shared room words, upgrade 22-1).
String? recordRestrictionText(LiveRestriction? restriction) {
  if (restriction == null || restriction == LiveRestriction.none) return null;
  final reason = restrictionReason(restriction);
  return reason.isEmpty ? null : reason;
}

/// The words for a resolution failure.
String recordStreamErrorText(RecordStreamException error) =>
    recordRestrictionText(error.restriction) ??
    i18n(switch (error.type) {
      RecordStreamErrorType.roomNotFound => 'recorder_stream_room_not_found',
      RecordStreamErrorType.notLive => 'recorder_status_waiting',
      RecordStreamErrorType.noQuality => 'recorder_stream_no_quality',
      RecordStreamErrorType.cdnFailed => 'recorder_stream_cdn_failed',
      RecordStreamErrorType.networkError || RecordStreamErrorType.unknown => 'recorder_stream_network',
      RecordStreamErrorType.loginExpired => 'recorder_stream_login',
      RecordStreamErrorType.banned => 'recorder_stream_banned',
      RecordStreamErrorType.restricted => 'recorder_stream_restricted',
    });

/// What the card says about the last failure of [task]: the localized
/// meaning when there is one ([restriction] from this session's notice),
/// else the diagnostic.
({String summary, String? detail}) recordFailureText(RecordTask task, {LiveRestriction? restriction}) {
  final stage = task.lastErrorStage ?? '';
  final error = task.lastError ?? '';
  String? meaning;
  if (stage.startsWith('ffmpeg.')) {
    // Stages are stored in lower case (`ffmpeg.storagefull`).
    final kind = FfmpegFailureKind.values.where((value) => 'ffmpeg.${value.name.toLowerCase()}' == stage).firstOrNull;
    meaning = recordFailureKindText(kind);
  } else if (stage == 'background') {
    meaning = i18n(error == 'timeout' ? 'recorder_background_time_limit' : 'recorder_background_unavailable');
  } else if (stage == 'room') {
    meaning = recordRestrictionText(restriction);
  }
  final summary = i18n(
    'recorder_last_error',
    args: {'stage': recordStageText(task.lastErrorStage), 'error': meaning ?? error},
  );
  return (summary: summary, detail: meaning != null && error.isNotEmpty && error != meaning ? error : null);
}

/// The toast of a recorder notice (3.x's toasts), or null.
String? recordNoticeText(RecordNotice notice) {
  final name = notice.task.nick.trim().isNotEmpty ? notice.task.nick.trim() : notice.task.roomId;
  return switch (notice.kind) {
    RecordNoticeKind.starting => i18n('recorder_task_starting'),
    RecordNoticeKind.captureFailed => i18n(
      'recorder_exception',
      args: {
        'name': name,
        'error': recordFailureKindText(notice.failure) ?? notice.task.lastError ?? i18n('recorder_stage_ffmpeg'),
      },
    ),
    RecordNoticeKind.resolveFailed => i18n(
      'recorder_resolve_failed',
      args: {
        'name': name,
        'error': switch (notice.streamError) {
          final RecordStreamException error => recordStreamErrorText(error),
          null => notice.task.lastError ?? '',
        },
      },
    ),
  };
}

/// File size (3.x `_formatFileSize`).
String recordSizeText(num bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes <= 0) return '0 ${i18n('unit_b')}';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} ${i18n('unit_gb')}';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} ${i18n('unit_mb')}';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} ${i18n('unit_kb')}';
  return '${bytes.round()} ${i18n('unit_b')}';
}

/// Seconds as `30s`, `5m`, `1.5h` (3.x settings `_formatDuration`).
String recordSecondsText(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) {
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(minutes.truncateToDouble() == minutes ? 0 : 1)}m';
  }
  final hours = seconds / 3600;
  return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)}h';
}
