import 'package:live_ui/src/ui_text.dart';

/// Short form of a count in the interface language ([LiveUiText.current]):
/// `9876`, `35.5万`, `355万`, `1.2亿` in Chinese; `987`, `9.9K`, `355K`,
/// `3.6M` in English (principles §2.3: “1.2万”, “12K”). One decimal below
/// 100 of a unit, dropped when it is zero, none from 100 on, so an English
/// figure has at most three significant digits and every figure at most
/// four characters before its unit; a value that rounds up to the next unit
/// moves to it (`9999.99万` is `1亿`, `999.6K` is `1M`).
String formatCount(int value, {LiveUiText? text}) {
  final style = text ?? LiveUiText.current;
  final base = style.countBase;
  if (value < base) return '$value';
  var scale = base.toDouble();
  for (var i = 0; i < style.countUnits.length; i++) {
    final shown = _short(value / scale);
    final last = i == style.countUnits.length - 1;
    if (last || double.parse(shown) < base) return '$shown${style.countUnits[i]}';
    scale *= base;
  }
  return '$value';
}

String _short(double value) {
  if (value >= 99.95) return value.round().toString();
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

/// "3 小时前" style relative time from [now], in the interface language
/// ([LiveUiText.current]); a date past 30 days.
String formatAgo(DateTime time, DateTime now, {LiveUiText? text}) {
  final words = text ?? LiveUiText.current;
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return words.justNow;
  if (difference.inHours < 1) return words.minutesAgo(difference.inMinutes);
  if (difference.inDays < 1) return words.hoursAgo(difference.inHours);
  if (difference.inDays < 30) return words.daysAgo(difference.inDays);
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
