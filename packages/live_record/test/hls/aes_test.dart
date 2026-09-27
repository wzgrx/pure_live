import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart' show Aes128Cbc;
import 'package:live_record/src/hls/aes.dart';
import 'package:test/test.dart';

Uint8List _hex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

void main() {
  test('NIST SP 800-38A F.2.1/F.2.2: CBC-AES128 test vectors', () {
    final key = _hex('2b7e151628aed2a6abf7158809cf4f3c');
    final iv = _hex('000102030405060708090a0b0c0d0e0f');
    final plain = _hex(
      '6bc1bee22e409f96e93d7e117393172a'
      'ae2d8a571e03ac9c9eb76fac45af8e51'
      '30c81c46a35ce411e5fbc1191a0a52ef'
      'f69f2445df4f9b17ad2b417be66c3710',
    );
    final cipher = _hex(
      '7649abac8119b246cee98e9b12e9197d'
      '5086cb9b507219ee95db113a917678b2'
      '73bed6b8e3c1743b7116e69e22229516'
      '3ff1caa1681fac09120eca307586e1a7',
    );
    final aes = HlsAes128(key);
    final encrypted = aes.encrypt(plain, iv);
    expect(encrypted.sublist(0, 64), cipher, reason: 'the last block is the PKCS#7 padding');
    expect(aes.decrypt(encrypted, iv), plain);
  });

  test('agrees with live_core Aes128Cbc on random data of every length', () {
    final random = Random(7);
    for (var length = 0; length < 80; length++) {
      final key = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final plain = Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
      final encrypted = HlsAes128(key).encrypt(plain, iv);
      expect(Aes128Cbc.decrypt(encrypted, key: key, iv: iv), plain);
      expect(HlsAes128(key).decrypt(encrypted, iv), plain);
    }
  });

  test('agrees with openssl (AES-128-CBC, PKCS#7)', () async {
    final key = _hex('000102030405060708090a0b0c0d0e0f');
    final iv = HlsAes128.sequenceIv(1041);
    expect(iv, _hex('00000000000000000000000000000411'), reason: 'the media sequence number, big endian');
    final plain = Uint8List.fromList(List.generate(1000, (i) => i * 7 & 0xFF));
    final dir = Directory.systemTemp.createTempSync('aes');
    try {
      File('${dir.path}/plain').writeAsBytesSync(plain);
      final result = await Process.run('openssl', [
        'enc',
        '-aes-128-cbc',
        '-K',
        '000102030405060708090a0b0c0d0e0f',
        '-iv',
        '00000000000000000000000000000411',
        '-in',
        '${dir.path}/plain',
        '-out',
        '${dir.path}/cipher',
      ]);
      if (result.exitCode != 0) {
        markTestSkipped('openssl is not available');
        return;
      }
      final cipher = File('${dir.path}/cipher').readAsBytesSync();
      expect(HlsAes128(key).encrypt(plain, iv), cipher);
      expect(HlsAes128(key).decrypt(cipher, iv), plain);
    } on ProcessException {
      markTestSkipped('openssl is not available');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a wrong key, a cut segment or a bad key length are errors', () {
    final key = Uint8List(16);
    final iv = Uint8List(16);
    final encrypted = HlsAes128(key).encrypt(List.filled(100, 1), iv);
    final wrong = Uint8List(16)..[0] = 1;
    expect(() => HlsAes128(wrong).decrypt(encrypted, iv), throwsFormatException);
    expect(() => HlsAes128(key).decrypt(Uint8List.sublistView(encrypted, 0, 50), iv), throwsFormatException);
    expect(() => HlsAes128(Uint8List(15)), throwsArgumentError);
  });

  test('decrypts megabytes quickly enough for live segments', () {
    final key = Uint8List(16);
    final iv = Uint8List(16);
    final plain = Uint8List(4 << 20);
    final encrypted = HlsAes128(key).encrypt(plain, iv);
    final watch = Stopwatch()..start();
    HlsAes128(key).decrypt(encrypted, iv);
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(2000), reason: '4 MiB (a 16 Mbit/s, 2 s segment)');
  });
}
