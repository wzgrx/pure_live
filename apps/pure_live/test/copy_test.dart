import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Interface copy the design review checked: English casing, one name for
/// one thing on every page.
void main() {
  tearDown(() => applyAppLocale(AppLocale.zhHans));

  const quality = Quality(id: 'origin', label: '原画', rank: 3);
  StreamLine line(String id) => StreamLine(
    url: Uri.parse('https://cdn-$id.example.com/live.m3u8'),
    format: StreamFormat.hls,
    lineId: id,
    requested: quality,
  );
  final state = PlaybackState(
    qualities: const [quality],
    quality: quality,
    lines: [line('a'), line('b')],
    line: line('a'),
  );

  test('English: the room\'s "Line N" is capitalised like multiview\'s', () {
    applyAppLocale(AppLocale.en);
    // It was "原画 · line 1" beside multiview's "Line 1".
    expect(qualityLineLabel(state), '原画 · Line 1');
    expect(t.multiview.lineN(n: 1), 'Line 1');
  });

  test('Chinese says 线路 N in both places', () {
    applyAppLocale(AppLocale.zhHans);
    expect(qualityLineLabel(state), '原画 · 线路 1');
    expect(t.multiview.lineN(n: 1), '线路 1');
  });
}
