import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A cipher that binds the name like the real ones (tests only).
final class FakeCipher implements SecretCipher {
  /// Values sealed so far.
  int sealed = 0;

  @override
  Future<Uint8List> seal(String ref, String plain) async {
    sealed++;
    return Uint8List.fromList(utf8.encode('$ref|${plain.split('').reversed.join()}'));
  }

  @override
  Future<String> open(String ref, Uint8List sealed) async {
    final text = utf8.decode(sealed);
    if (!text.startsWith('$ref|')) throw StateError('sealed for another name');
    return text.substring(ref.length + 1).split('').reversed.join();
  }
}

/// An HTTP client that answers nothing (no test goes to the network).
final class NoNetworkHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) async =>
      throw TransportFailure(request.site, TransportReason.connect, 'tests have no network');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async =>
      throw TransportFailure(request.site, TransportReason.connect, 'tests have no network');

  @override
  void close() {}
}

/// Services over an in-memory store, without background work.
Future<AppServices> testServices({LaunchArgs launch = const LaunchArgs()}) async {
  final cipher = FakeCipher();
  final store = await LiveStore.memory(cipher: cipher);
  return AppBootstrap.wire(
    store: store,
    cipher: cipher,
    launch: launch,
    dataRoot: Directory.systemTemp,
    http: NoNetworkHttp(),
    background: false,
  );
}

/// The translations straight from the asset files.
final class FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
}

/// Loads [language]'s words and makes them current.
Future<AppStrings> loadStrings([AppLanguage language = AppLanguage.zh]) async {
  final strings = await AppStrings.load(language, FileAssetBundle());
  currentStrings = strings;
  return strings;
}
