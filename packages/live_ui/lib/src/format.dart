/// Chinese short form of a count: `9876`, `355.1万`, `1.2亿`.
String formatCount(int value) {
  if (value < 10000) return '$value';
  if (value < 100000000) return '${_oneDecimal(value / 10000)}万';
  return '${_oneDecimal(value / 100000000)}亿';
}

String _oneDecimal(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// `HH:MM` for a live duration; `HHH:MM` past 99 hours.
String formatLiveDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 0) return '00:00';
  final hours = minutes ~/ 60;
  return '${hours.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// "3 小时前" style relative time from [now].
String formatAgo(DateTime time, DateTime now) {
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 30) return '${difference.inDays} 天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
