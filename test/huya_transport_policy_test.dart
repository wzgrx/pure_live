import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/huya/huya_transport_policy.dart';

void main() {
  test('native WUP FLV credential expiry is not a short transport lease', () {
    expect(
      HuyaTransportPolicy.hasShortTransportLease('https://al.flv.huya.com/live.flv?ctype=huya_pc_exe&t=100'),
      isFalse,
    );
  });

  test('web and legacy transports retain their existing short lease protection', () {
    for (final url in [
      'https://al.flv.huya.com/live.flv?ctype=huya_live&t=100',
      'https://al.flv.huya.com/live.flv?ctype=huya_webh5&t=100',
      'https://al.flv.huya.com/live.flv',
      'https://al.hls.huya.com/live.m3u8?ctype=huya_pc_exe&t=100',
    ]) {
      expect(HuyaTransportPolicy.hasShortTransportLease(url), isTrue, reason: url);
    }
  });

  test('matching a query alone does not apply Huya transport policy', () {
    for (final url in ['https://huya.com.example/live.flv', 'https://example.com/live.flv', 'not a URL']) {
      expect(HuyaTransportPolicy.hasShortTransportLease(url), isFalse);
    }
  });
}
