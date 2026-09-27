import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:live_store/src/secrets/crypto.dart';
import 'package:meta/meta.dart';

/// Thrown when the backup passphrase does not open the secrets section.
final class WrongPassphraseException implements Exception {
  /// Creates the exception.
  const new();

  @override
  String toString() => 'WrongPassphraseException';
}

/// The passphrase-encrypted secrets section of a v4 backup (store.md §7.3):
/// PBKDF2-HMAC-SHA256 (600 000 iterations, 16-byte salt) derives an AES-256
/// key; AES-256-GCM (12-byte nonce) seals the JSON map of reference names to
/// values, bound to `format|version|createdAt`.
@internal
abstract final class SecretEnvelope {
  /// Iterations for new envelopes.
  static const defaultIterations = 600000;

  /// Highest iteration count accepted when reading, against denial of
  /// service by a crafted file.
  static const maxIterations = 10000000;

  /// Seals [secrets] with [passphrase]. Key derivation runs on another
  /// isolate so the UI stays responsive.
  static Future<Map<String, Object?>> seal(
    Map<String, String> secrets,
    String passphrase, {
    required String associatedData,
    int iterations = defaultIterations,
  }) async {
    final salt = Crypto.randomBytes(16);
    final nonce = Crypto.randomBytes(Crypto.nonceLength);
    final key = await Isolate.run(() => Crypto.pbkdf2(passphrase, salt, iterations));
    final data = Crypto.seal(
      key,
      nonce,
      Uint8List.fromList(utf8.encode(jsonEncode(secrets))),
      Uint8List.fromList(utf8.encode(associatedData)),
    );
    return {
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
      'data': base64Encode(data),
    };
  }

  /// Opens an envelope; throws [FormatException] for a malformed one and
  /// [WrongPassphraseException] when [passphrase] does not match.
  static Future<Map<String, String>> open(Object? envelope, String passphrase, {required String associatedData}) async {
    if (envelope is! Map<String, Object?> ||
        envelope['kdf'] != 'pbkdf2-sha256' ||
        envelope['cipher'] != 'aes-256-gcm') {
      throw const FormatException('Unsupported secrets section');
    }
    final iterations = envelope['iterations'];
    if (iterations is! int || iterations < 1 || iterations > maxIterations) {
      throw const FormatException('Invalid secrets iteration count');
    }
    final Uint8List salt;
    final Uint8List nonce;
    final Uint8List data;
    try {
      salt = base64Decode(envelope['salt']! as String);
      nonce = base64Decode(envelope['nonce']! as String);
      data = base64Decode(envelope['data']! as String);
    } on Object {
      throw const FormatException('Invalid secrets encoding');
    }
    if (nonce.length != Crypto.nonceLength) throw const FormatException('Invalid secrets nonce');
    final key = await Isolate.run(() => Crypto.pbkdf2(passphrase, salt, iterations));
    final Uint8List plain;
    try {
      plain = Crypto.open(key, nonce, data, Uint8List.fromList(utf8.encode(associatedData)));
    } on Object {
      throw const WrongPassphraseException();
    }
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, Object?>) throw const FormatException('Invalid secrets content');
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value is String) key: value,
    };
  }
}
