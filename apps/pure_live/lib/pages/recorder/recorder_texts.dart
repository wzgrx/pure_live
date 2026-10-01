import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The recording centre's filters (3.x `RecorderPage.tabs`, same order).
const List<({String label, RecordStatus? status})> recorderFilters = [
  (label: 'recorder_tab_all', status: null),
  (label: 'recorder_tab_recording', status: RecordStatus.running),
  (label: 'recorder_tab_waiting', status: RecordStatus.waitingLive),
  (label: 'recorder_tab_queue', status: RecordStatus.queued),
  (label: 'recorder_tab_reconnecting', status: RecordStatus.reconnecting),
  (label: 'recorder_tab_processing', status: RecordStatus.processing),
  (label: 'recorder_tab_completed', status: RecordStatus.completed),
  (label: 'recorder_tab_failed', status: RecordStatus.failed),
  (label: 'recorder_tab_stopped', status: RecordStatus.stopped),
];

/// The status label (3.x `_statusText`).
String recordStatusText(RecordStatus status) => i18n(switch (status) {
  RecordStatus.running => 'recorder_status_recording',
  RecordStatus.preparing => 'recorder_status_preparing',
  RecordStatus.queued => 'recorder_status_queue',
  RecordStatus.waitingLive => 'recorder_status_waiting',
  RecordStatus.reconnecting => 'recorder_status_reconnecting',
  RecordStatus.processing => 'recorder_status_processing',
  RecordStatus.completed => 'recorder_status_completed',
  RecordStatus.failed => 'recorder_status_failed',
  RecordStatus.stopped => 'recorder_status_stopped',
});

/// The status colour (3.x `_statusColor`).
Color recordStatusColor(RecordStatus status) => switch (status) {
  RecordStatus.running => Colors.green,
  RecordStatus.preparing => Colors.amber,
  RecordStatus.queued => Colors.deepPurple,
  RecordStatus.waitingLive => Colors.orangeAccent,
  RecordStatus.reconnecting => Colors.orange,
  RecordStatus.processing => Colors.cyan,
  RecordStatus.completed => Colors.blue,
  RecordStatus.failed => Colors.red,
  RecordStatus.stopped => Colors.grey,
};

/// The platform's name (`site_<id>`), else its id.
String recordPlatformName(String platform) => i18nOr('site_$platform', platform.toUpperCase());

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

/// The restriction's explanation (the live room's words, upgrade 22-1).
String? recordRestrictionText(LiveRestriction? restriction) {
  if (restriction == null || restriction == LiveRestriction.none) return null;
  final snake = restriction.name.replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}');
  final key = 'live_play_restriction_${snake}_hint';
  return i18nExists(key) ? i18n(key) : null;
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

/// `hh:mm:ss` (3.x `_formatDuration`).
String recordDurationText(int seconds) {
  final duration = Duration(seconds: seconds < 0 ? 0 : seconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(duration.inHours)}:${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
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

/// Bitrate (3.x `_formatBitrate`).
String recordBitrateText(double kilobitsPerSecond) {
  if (!kilobitsPerSecond.isFinite || kilobitsPerSecond <= 0) return '--';
  if (kilobitsPerSecond >= 1000) return '${(kilobitsPerSecond / 1000).toStringAsFixed(1)} Mbps';
  return '${kilobitsPerSecond.toStringAsFixed(0)} kbps';
}

/// `MM-dd HH:mm` of [time] in local time (3.x showed the same part of
/// `DateTime.toString()`).
String recordTimeText(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
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
