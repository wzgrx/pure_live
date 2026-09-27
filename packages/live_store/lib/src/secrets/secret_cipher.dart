import 'dart:typed_data';

import 'package:live_store/src/secrets/crypto.dart';

/// Encrypts secrets at rest with a device-bound key (spec/modules/store.md
/// §4, constitution rule 8).
///
/// The app supplies the platform implementation: Android seals with a
/// non-exportable Android Keystore AES-GCM key, Windows with DPAPI for the
/// current user. Neither exposes key bytes, so the interface is "seal and
/// open", not "give me the key". [AesGcmSecretCipher] is the portable
/// implementation for a key the caller already holds.
abstract interface class SecretCipher {
  /// Encrypts [plaintext], binding it to [associatedData] (the secret's
  /// reference name), and returns an opaque blob.
  Future<Uint8List> seal(Uint8List plaintext, Uint8List associatedData);

  /// Decrypts a blob from [seal]; throws when it cannot be authenticated
  /// (wrong key, other device, tampering, other reference name).
  Future<Uint8List> open(Uint8List sealed, Uint8List associatedData);
}

/// AES-256-GCM with a caller-supplied 32-byte key.
///
/// Blob layout: version byte `1`, 12-byte random nonce, ciphertext, 16-byte
/// tag. Security equals the key's: a key kept next to the secrets file only
/// obfuscates. Use it with a key from the platform's keystore, or in tests.
final class AesGcmSecretCipher implements SecretCipher {
  /// Uses [key], which must be 32 bytes.
  new(Uint8List key) : _key = Uint8List.fromList(key) {
    if (key.length != 32) throw ArgumentError.value(key.length, 'key', 'AES-256 needs 32 bytes');
  }

  final Uint8List _key;

  static const _version = 1;

  @override
  Future<Uint8List> seal(Uint8List plaintext, Uint8List associatedData) async {
    final nonce = Crypto.randomBytes(Crypto.nonceLength);
    final sealed = Crypto.seal(_key, nonce, plaintext, associatedData);
    return Uint8List.fromList([_version, ...nonce, ...sealed]);
  }

  @override
  Future<Uint8List> open(Uint8List sealed, Uint8List associatedData) async {
    if (sealed.length < 1 + Crypto.nonceLength + Crypto.tagBits ~/ 8 || sealed.first != _version) {
      throw const FormatException('Unknown secret blob');
    }
    final nonce = Uint8List.sublistView(sealed, 1, 1 + Crypto.nonceLength);
    final body = Uint8List.sublistView(sealed, 1 + Crypto.nonceLength);
    return Crypto.open(_key, nonce, body, associatedData);
  }

  @override
  String toString() => 'AesGcmSecretCipher(<key hidden>)';
}
