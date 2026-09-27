import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  test('counts use 万 and 亿 with one decimal', () {
    expect(formatCount(9876), '9876');
    expect(formatCount(10000), '1万');
    expect(formatCount(3551234), '355.1万');
    expect(formatCount(123456789), '1.2亿');
    expect(formatCount(999999999), '10亿');
  });

  test('F-APP-06: counts follow the injected language (principles §2.3)', () {
    expect(formatCount(12000, text: english), '12K');
    expect(formatCount(987, text: english), '987');
    expect(formatCount(3551234, text: english), '3.6M');
    expect(formatCount(999999, text: english), '1M');
    expect(formatCount(1234567890, text: english), '1.2B');
    expect(formatCount(12000, text: traditional), '1.2萬');
    expect(formatCount(340000000, text: traditional), '3.4億');
    expect(formatAgo(DateTime(2026, 9, 27, 9), DateTime(2026, 9, 27, 12), text: english), '3 hours ago');
  });

  test('F-APP-06: widgets read LiveUiText.current', () {
    addTearDown(() => LiveUiText.current = LiveUiText.simplifiedChinese);
    LiveUiText.current = english;
    expect(formatCount(12000), '12K');
    expect(formatAgo(DateTime(2026, 9, 27, 11, 59, 40), DateTime(2026, 9, 27, 12)), 'just now');
  });

  test('durations and relative times', () {
    expect(formatLiveDuration(const Duration(hours: 1, minutes: 24, seconds: 7)), '01:24');
    expect(formatLiveDuration(const Duration(hours: 123)), '123:00');
    final now = DateTime(2026, 9, 27, 12);
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now), '刚刚');
    expect(formatAgo(now.subtract(const Duration(hours: 3)), now), '3 小时前');
    expect(formatAgo(DateTime(2026, 5, 2), now), '2026-05-02');
  });
}

String _liveForEn(String duration) => 'LIVE $duration';
String _minutesEn(int minutes) => '$minutes min ago';
String _hoursEn(int hours) => hours == 1 ? '1 hour ago' : '$hours hours ago';
String _daysEn(int days) => days == 1 ? '1 day ago' : '$days days ago';

const english = LiveUiText(
  live: 'LIVE',
  liveFor: _liveForEn,
  liveNow: 'live',
  offline: 'offline',
  recording: 'Recording',
  separator: ', ',
  retry: 'Retry',
  ok: 'OK',
  cancel: 'Cancel',
  justNow: 'just now',
  minutesAgo: _minutesEn,
  hoursAgo: _hoursEn,
  daysAgo: _daysEn,
  countBase: 1000,
  countUnits: ['K', 'M', 'B'],
);

final traditional = LiveUiText(
  live: '直播',
  liveFor: (duration) => '直播 $duration',
  liveNow: '直播中',
  offline: '未開播',
  recording: '錄製中',
  separator: '，',
  retry: '重試',
  ok: '確定',
  cancel: '取消',
  justNow: '剛剛',
  minutesAgo: (minutes) => '$minutes 分鐘前',
  hoursAgo: (hours) => '$hours 小時前',
  daysAgo: (days) => '$days 天前',
  countBase: 10000,
  countUnits: const ['萬', '億'],
);
