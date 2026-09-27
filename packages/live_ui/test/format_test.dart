import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  test('counts use 万 and 亿 with one decimal', () {
    expect(formatCount(9876), '9876');
    expect(formatCount(10000), '1万');
    expect(formatCount(3551234), '355.1万');
    expect(formatCount(123456789), '1.2亿');
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
