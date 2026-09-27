import 'dart:convert';
import 'dart:typed_data';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

Uint8List _hex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

String _string(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

void main() {
  final zero = Uint8List(16);

  test('FIPS-197 appendix C: one block for each key size', () {
    final plain = _hex('00112233445566778899aabbccddeeff');
    const vectors = {
      '000102030405060708090a0b0c0d0e0f': '69c4e0d86a7b0430d8cdb78070b4c55a',
      '000102030405060708090a0b0c0d0e0f1011121314151617': 'dda97ca4864cdfe06eaf70a0ec0d7191',
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f': '8ea2b7ca516745bfeafc49904b496089',
    };
    for (final MapEntry(:key, value: cipher) in vectors.entries) {
      final aes = AesCbc(_hex(key));
      // With a zero IV the first CBC block is the bare block cipher.
      final out = aes.encrypt(plain, zero);
      expect(_string(out.sublist(0, 16)), cipher, reason: 'key of ${key.length * 4} bits');
      expect(aes.decrypt(out, zero), plain);
    }
  });

  test('SP 800-38A F.2.1: CBC over four blocks', () {
    final aes = AesCbc(_hex('2b7e151628aed2a6abf7158809cf4f3c'));
    final iv = _hex('000102030405060708090a0b0c0d0e0f');
    final plain = _hex(
      '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'
      '30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710',
    );
    final out = aes.encrypt(plain, iv);
    expect(
      _string(out.sublist(0, 64)),
      '7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2'
      '73bed6b8e3c1743b7116e69e222295163ff1caa1681fac09120eca307586e1a7',
    );
    expect(out, hasLength(80), reason: 'a whole padding block follows block-aligned input');
    expect(aes.decrypt(out, iv), plain);
  });

  test('PKCS#7 padding matches openssl enc', () {
    final aes = AesCbc(_hex('2b7e151628aed2a6abf7158809cf4f3c'));
    final iv = _hex('000102030405060708090a0b0c0d0e0f');
    final text = utf8.encode('hello acfun, 你好');
    expect(_string(aes.encrypt(text, iv)), 'ebd0938f3a1afd8dd3f3398447b0e5a5f7efb98635eaf1d50921d22619911047');
    expect(
      utf8.decode(aes.decrypt(_hex('ebd0938f3a1afd8dd3f3398447b0e5a5f7efb98635eaf1d50921d22619911047'), iv)),
      'hello acfun, 你好',
    );
    final counted = List.generate(32, (i) => i);
    expect(
      _string(aes.encrypt(counted, iv)),
      '7df76b0c1ab899b33e42f047b91b546f1caa8018c80b15b8e7aea82794adcb00b93f34a2e3f93021c61bb886c3ea499a',
    );
    expect(aes.encrypt(const [], iv), hasLength(16));
  });

  test('a wrong key or a torn message is a FormatException, a bad size an ArgumentError', () {
    final iv = _hex('000102030405060708090a0b0c0d0e0f');
    final sealed = AesCbc(_hex('2b7e151628aed2a6abf7158809cf4f3c')).encrypt(utf8.encode('secret'), iv);
    expect(() => AesCbc(Uint8List(16)).decrypt(sealed, iv), throwsFormatException);
    expect(() => AesCbc(Uint8List(16)).decrypt(sealed.sublist(0, 15), iv), throwsFormatException);
    expect(() => AesCbc(Uint8List(15)), throwsArgumentError);
    expect(() => AesCbc(Uint8List(16)).encrypt(const [1], Uint8List(8)), throwsArgumentError);
  });
}
