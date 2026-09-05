import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/huya/huya_transport_policy.dart';

void main() {
  const al = 'https://al.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100';
  const tx = 'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100';
  const web = 'https://tx.flv.huya.com/src/room.flv?ctype=huya_live';
  const hls = 'https://tx.hls.huya.com/src/room.m3u8?ctype=huya_live';
  for (final scenario in [
    (name: 'query renewal keeps the same CDN', current: '$tx&seqid=old', urls: [tx, al], advance: false, expected: 0),
    (
      name: 'rotated stream name keeps the CDN',
      current: tx.replaceFirst('room.flv', 'old.flv'),
      urls: [tx, al],
      advance: false,
      expected: 0,
    ),
    (
      name: 'missing current CDN takes the first native fallback',
      current: tx,
      urls: [al, hls],
      advance: true,
      expected: 0,
    ),
    (
      name: 'a sole failed native line may fall back to web FLV',
      current: tx,
      urls: [tx, web, hls],
      advance: true,
      expected: 1,
    ),
    (name: 'a sole failed FLV line may fall back to HLS', current: tx, urls: [tx, hls], advance: true, expected: 1),
    (
      name: 'HLS choice stays HLS instead of silently forcing FLV',
      current: hls,
      urls: [hls, tx],
      advance: false,
      expected: 0,
    ),
    (name: 'a failed HLS line may fall back to native FLV', current: hls, urls: [hls, tx], advance: true, expected: 1),
    (name: 'native CDN wraps within native choices', current: tx, urls: [al, tx, hls], advance: true, expected: 0),
    (
      name: 'same CDN native failure avoids web while another native CDN exists',
      current: tx,
      urls: [tx, web, al],
      advance: true,
      expected: 2,
    ),
    (
      name: 'single remaining source can still reopen after real EOF',
      current: tx,
      urls: [tx],
      advance: true,
      expected: 0,
    ),
    (
      name: 'foreign host never supplies Huya identity',
      current: 'https://huya.com.example/room.flv',
      urls: [tx, al],
      advance: false,
      expected: 1,
    ),
  ]) {
    test('refreshed line: ${scenario.name}', () {
      expect(
        HuyaTransportPolicy.selectRefreshedLine(
          urls: scenario.urls,
          currentUrl: scenario.current,
          currentLineIndex: 1,
          advanceLine: scenario.advance,
        ),
        scenario.expected,
      );
    });
  }

  test('absent identity and empty manifests preserve bounded legacy behavior', () {
    expect(
      HuyaTransportPolicy.selectRefreshedLine(urls: [], currentUrl: tx, currentLineIndex: 9, advanceLine: true),
      0,
    );
    expect(
      HuyaTransportPolicy.selectRefreshedLine(
        urls: [al, tx],
        currentUrl: null,
        currentLineIndex: 9,
        advanceLine: false,
      ),
      1,
    );
    expect(
      HuyaTransportPolicy.selectRefreshedLine(
        urls: [al, tx],
        currentUrl: null,
        currentLineIndex: -1,
        advanceLine: true,
      ),
      1,
    );
  });

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
