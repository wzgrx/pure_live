// KilaKila share links (spec/sites/kilakila.md §1): the public AES-CBC codec
// and its MD5 signature, over the share vectors in
// fixtures/kilakila/S09-share-vectors (independent .NET vectors from the
// legacy suite plus a link the website issued on 2026-09-27).
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16),
];

void main() {
  test('AES-128-CBC matches SP 800-38A F.2.2', () {
    final plain = Aes128Cbc.decryptBlocks(
      _hex('7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2'),
      key: _hex('2b7e151628aed2a6abf7158809cf4f3c'),
      iv: _hex('000102030405060708090a0b0c0d0e0f'),
    );
    expect(plain, _hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'));
    expect(
      () =>
          Aes128Cbc.decrypt(_hex('7649abac8119b246cee98e9b12e9197d'), key: List.filled(16, 0), iv: List.filled(16, 0)),
      throwsFormatException,
      reason: 'garbage padding',
    );
    expect(() => Aes128Cbc.decrypt([1, 2, 3], key: List.filled(16, 0), iv: List.filled(16, 0)), throwsFormatException);
  });

  final vectors = (jsonDecode(
    File('../../fixtures/kilakila/S09-share-vectors/vectors.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  for (final vector in vectors) {
    test('share vector ${vector['name']}', () {
      final link = KilakilaLink.parse(vector['url'] as String);
      if (vector['valid'] == true) {
        final kind = vector['kind'] == 'owner' ? KilakilaLinkKind.anchor : KilakilaLinkKind.broadcast;
        expect(link, KilakilaLink(kind, vector['id'] as String));
      } else {
        expect(link, isNull);
      }
    });
  }

  test('plain links and share text', () {
    for (final host in ['live.kilakila.cn', 'www.hongdoufm.com']) {
      expect(KilakilaLink.parse('https://$host/room/123'), const KilakilaLink(KilakilaLinkKind.broadcast, '123'));
      expect(
        KilakilaLink.parse('http://$host/PcLive/index/detail?id=123'),
        const KilakilaLink(KilakilaLinkKind.broadcast, '123'),
      );
    }
    expect(
      KilakilaLink.parse('来听 https://live.kilakila.cn/zhubo/3674092253247 呀'),
      const KilakilaLink(KilakilaLinkKind.anchor, '3674092253247'),
    );
    expect(
      KilakilaLink.parse('https://live.hongrenshuo.com.cn/index/roomuser/uid/3674092253247'),
      const KilakilaLink(KilakilaLinkKind.anchor, '3674092253247'),
    );
    for (final bad in [
      'https://live.kilakila.cn/room/0123',
      'https://live.kilakila.cn/room/123?id=4',
      'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=bad&id=1',
      'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=',
      'https://live.kilakila.cn/zhubo/abc',
      'https://example.test/room/123',
      'not a link',
    ]) {
      expect(KilakilaLink.parse(bad), isNull, reason: bad);
    }
  });
}
