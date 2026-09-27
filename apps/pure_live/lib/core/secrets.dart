import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';

/// The encrypted secret store; main() overrides it after opening.
final secretStoreProvider = Provider<SecretStore>((ref) => throw StateError('SecretStore is opened in main()'));

/// Opens the secret store with the platform's device-bound cipher
/// (spec/modules/store.md §4, constitution rule 8).
Future<SecretStore> openSecretStore(String root) async {
  final cipher = await platformCipher(root);
  return await SecretStore.open(cipher: cipher, backend: FileSecretBackend.inRoot(root));
}

/// Android Keystore on Android, DPAPI on Windows; elsewhere a random key in a
/// file next to the secrets, which only obfuscates (documented gap).
Future<SecretCipher> platformCipher(String root) async {
  if (Platform.isAndroid) return const _AndroidKeystoreCipher();
  if (Platform.isWindows) return _DpapiCipher();
  final file = File('$root${Platform.pathSeparator}DB${Platform.pathSeparator}secret.key');
  if (!file.existsSync()) {
    final random = Random.secure();
    await file.create(recursive: true);
    await file.writeAsBytes([for (var i = 0; i < 32; i++) random.nextInt(256)], flush: true);
  }
  return AesGcmSecretCipher(await file.readAsBytes());
}

/// Seals with a non-exportable AES-GCM key in the Android Keystore
/// (MainActivity, channel `purelive/keystore`).
final class _AndroidKeystoreCipher implements SecretCipher {
  const new();

  static const _channel = MethodChannel('purelive/keystore');

  @override
  Future<Uint8List> seal(Uint8List plaintext, Uint8List associatedData) async =>
      (await _channel.invokeMethod<Uint8List>('seal', {'data': plaintext, 'aad': associatedData}))!;

  @override
  Future<Uint8List> open(Uint8List sealed, Uint8List associatedData) async =>
      (await _channel.invokeMethod<Uint8List>('open', {'data': sealed, 'aad': associatedData}))!;
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

/// Windows DPAPI for the current user; the reference name is the optional
/// entropy, so a blob moved to another reference does not open.
final class _DpapiCipher implements SecretCipher {
  new()
    : _protect = DynamicLibrary.open('crypt32.dll').lookupFunction<_CryptNative, _CryptDart>('CryptProtectData'),
      _unprotect = DynamicLibrary.open('crypt32.dll')
          .lookupFunction<_UnprotectNative, _UnprotectDart>('CryptUnprotectData'),
      _localFree = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');

  final _CryptDart _protect;
  final _UnprotectDart _unprotect;
  final Pointer<Void> Function(Pointer<Void>) _localFree;

  static const _uiForbidden = 0x1;

  Uint8List _run(Uint8List input, Uint8List entropy, {required bool protect}) {
    final inBlob = calloc<_DataBlob>();
    final entropyBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final inBytes = calloc<Uint8>(max(input.length, 1));
    final entropyBytes = calloc<Uint8>(max(entropy.length, 1));
    try {
      inBytes.asTypedList(input.length).setAll(0, input);
      entropyBytes.asTypedList(entropy.length).setAll(0, entropy);
      inBlob.ref
        ..cbData = input.length
        ..pbData = inBytes;
      entropyBlob.ref
        ..cbData = entropy.length
        ..pbData = entropyBytes;
      final ok = protect
          ? _protect(inBlob, nullptr, entropyBlob, nullptr, nullptr, _uiForbidden, outBlob)
          : _unprotect(inBlob, nullptr, entropyBlob, nullptr, nullptr, _uiForbidden, outBlob);
      if (ok == 0) throw StateError('DPAPI ${protect ? 'protect' : 'unprotect'} failed');
      final result = Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      _localFree(outBlob.ref.pbData.cast());
      return result;
    } finally {
      calloc
        ..free(inBlob)
        ..free(entropyBlob)
        ..free(outBlob)
        ..free(inBytes)
        ..free(entropyBytes);
    }
  }

  @override
  Future<Uint8List> seal(Uint8List plaintext, Uint8List associatedData) async =>
      _run(plaintext, associatedData, protect: true);

  @override
  Future<Uint8List> open(Uint8List sealed, Uint8List associatedData) async =>
      _run(sealed, associatedData, protect: false);
}

/// live_net's cookie source backed by the encrypted store (ADR 0017 §2).
final class StoreCookieVault implements CookieVault {
  const new(this._secrets);

  final SecretStore _secrets;

  @override
  String? cookieFor(String site) => _secrets.cookieFor(site);

  @override
  Stream<String> get changes => _secrets.cookieChanges;
}
