import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pointycastle/export.dart';

/// AES-256-GCM and PBKDF2-HMAC-SHA256 on pointycastle (pure Dart).
@internal
abstract final class Crypto {
  static final Random _random = Random.secure();

  /// GCM nonce length in bytes.
  static const nonceLength = 12;

  /// GCM tag length in bits.
  static const tagBits = 128;

  /// [length] random bytes from the platform's secure generator.
  static Uint8List randomBytes(int length) => Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  /// Encrypts [plaintext]; returns ciphertext followed by the 16-byte tag.
  static Uint8List seal(Uint8List key, Uint8List nonce, Uint8List plaintext, Uint8List associatedData) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), tagBits, nonce, associatedData));
    return cipher.process(plaintext);
  }

  /// Decrypts and authenticates [sealed]; throws [InvalidCipherTextException]
  /// when the key, nonce, data or associated data do not match.
  static Uint8List open(Uint8List key, Uint8List nonce, Uint8List sealed, Uint8List associatedData) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), tagBits, nonce, associatedData));
    return cipher.process(sealed);
  }

  /// PBKDF2-HMAC-SHA256 of [passphrase] (UTF-8).
  static Uint8List pbkdf2(String passphrase, Uint8List salt, int iterations, {int length = 32}) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, length));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }
}
