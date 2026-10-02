import 'package:pure_live/i18n/i18n.dart';

// The words of the recording settings (docs/A-界面设计/A10-录制界面/A10.2-录制设置 c5, c6): units
// in words ("15 秒", "5 分钟", "3.5 GB") where 3.x wrote "15s", "5m",
// "3584.25 MB", and what a value means next to it.

String _number(double value) => value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);

/// [seconds] as "30 秒", "5 分钟", "5.5 分钟", "1 小时" (3.x `_formatDuration`
/// with the units written out; a stored value that is not a whole minute
/// keeps its half, U.7b c11).
String recordDurationLabel(int seconds) {
  if (seconds < 60) return i18n('record_unit_seconds', args: {'n': '$seconds'});
  if (seconds < 3600) return i18n('record_unit_minutes', args: {'n': _number(seconds / 60)});
  return i18n('record_unit_hours', args: {'n': _number(seconds / 3600)});
}

/// [seconds] always in seconds: "60 秒", "120 秒" (the timeout and the
/// intervals, which 3.x wrote as "60s", "120s").
String recordSecondsLabel(int seconds) => i18n('record_unit_seconds', args: {'n': '$seconds'});

/// A count of retries: "5 次".
String recordTimesLabel(int count) => i18n('record_unit_times', args: {'n': '$count'});

/// A size: "3.5 GB", "512.3 MB", "12 KB", "0 B".
String recordSpaceLabel(num bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes <= 0) return '0 ${i18n('unit_b')}';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} ${i18n('unit_gb')}';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} ${i18n('unit_mb')}';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} ${i18n('unit_kb')}';
  return '${bytes.round()} ${i18n('unit_b')}';
}

/// The name of a stored quality preference (3.x keeps the Chinese names).
String recordQualityLabel(String value) => i18nOr(switch (value) {
  '原画' => 'prefer_resolution_option_original',
  '蓝光8M' => 'prefer_resolution_option_blu_ray_8m',
  '蓝光4M' => 'prefer_resolution_option_blu_ray_4m',
  '超清' => 'prefer_resolution_option_super_hd',
  '流畅' => 'prefer_resolution_option_smooth',
  _ => value,
}, value);

/// What a read and write timeout means (3.x's dialog, `:329-344`).
String recordTimeoutMeaning(int seconds) => i18n(switch (seconds) {
  <= 15 => 'timeout_fast',
  <= 30 => 'timeout_balanced',
  _ => 'timeout_safe',
});

/// What an input queue size means (3.x's dialog, `:346-368`).
String recordQueueMeaning(int size) => i18n(switch (size) {
  <= 512 => 'power_saving_mode',
  1024 => 'hd_recommend',
  2048 => 'fhd_recommend',
  _ => 'extreme_performance',
});
