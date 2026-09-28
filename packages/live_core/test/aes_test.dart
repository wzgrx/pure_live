// AesCbc (encryption) against the FIPS 197 vectors and SP 800-38A's CBC
// vector, and against Aes128Cbc (decryption) for the padding round trip.
// Bigo's token request (AES-256-CBC, OpenSSL's envelope) is checked with
// 3.x's vectors in sites/bigo_api_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

List<int> _hex(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

String _toHex(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

void main() {
  test('FIPS 197 appendix C: AES-128, AES-192 and AES-256 of one block', () {
    final plain = _hex('00112233445566778899aabbccddeeff');
    for (final (key, cipher) in [
      ('000102030405060708090a0b0c0d0e0f', '69c4e0d86a7b0430d8cdb78070b4c55a'),
      ('000102030405060708090a0b0c0d0e0f1011121314151617', 'dda97ca4864cdfe06eaf70a0ec0d7191'),
      ('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f', '8ea2b7ca516745bfeafc49904b496089'),
    ]) {
      expect(_toHex(AesCbc.encryptBlock(plain, key: _hex(key))), cipher, reason: '${key.length * 4} bits');
    }
  });

  test('SP 800-38A F.2.5: CBC with AES-256 (first two blocks, before the padding block)', () {
    final encrypted = AesCbc.encrypt(
      _hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'),
      key: _hex('603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4'),
      iv: _hex('000102030405060708090a0b0c0d0e0f'),
    );
    expect(encrypted, hasLength(48), reason: 'a whole padding block follows');
    expect(_toHex(encrypted.sublist(0, 32)), 'f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d');
  });

  test('PKCS#7 padding round trip with Aes128Cbc', () {
    final key = List<int>.generate(16, (index) => index * 7);
    final iv = List<int>.generate(16, (index) => 255 - index);
    for (final length in [0, 1, 15, 16, 17, 64]) {
      final plain = utf8.encode('x' * length);
      final encrypted = AesCbc.encrypt(plain, key: key, iv: iv);
      expect(encrypted.length, (length ~/ 16 + 1) * 16, reason: '$length');
      expect(
        Aes128Cbc.decrypt(encrypted, key: key, iv: iv),
        plain,
        reason: '$length',
      );
    }
  });

  test('a key of another length, an IV or a block that is not 16 bytes is a FormatException', () {
    expect(() => AesCbc.encrypt(const [1], key: List.filled(20, 0), iv: List.filled(16, 0)), throwsFormatException);
    expect(() => AesCbc.encrypt(const [1], key: List.filled(16, 0), iv: List.filled(8, 0)), throwsFormatException);
    expect(() => AesCbc.encryptBlock(List.filled(15, 0), key: List.filled(16, 0)), throwsFormatException);
  });
}
