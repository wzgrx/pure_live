import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live/platform/display_mode.dart';

/// Strict GBK decoding for IPTV playlists that are not UTF-8 (3.x used the
/// charset_converter plugin): Android's `Charset`, Windows code page 936.
/// Malformed bytes throw [FormatException], so a broken file is reported
/// instead of imported as replacement characters.
IptvLegacyDecoder? platformGbkDecoder() {
  if (Platform.isAndroid) return _androidGbk;
  if (Platform.isWindows) return _windowsGbk;
  return null;
}

const MethodChannel _textCodec = MethodChannel('pure_live/text_codec');

Future<String> _androidGbk(Uint8List bytes) async {
  try {
    return await _textCodec.invokeMethod<String>('decode', {'bytes': bytes, 'charset': 'GBK'}) ?? '';
  } on PlatformException catch (error) {
    throw FormatException('Not GBK text: ${error.message}');
  }
}

typedef _MultiByteNative = Int32 Function(
  Uint32 codePage,
  Uint32 flags,
  Pointer<Uint8> input,
  Int32 inputLength,
  Pointer<Uint16> output,
  Int32 outputLength,
);
typedef _MultiByteDart = int Function(
  int codePage,
  int flags,
  Pointer<Uint8> input,
  int inputLength,
  Pointer<Uint16> output,
  int outputLength,
);

String _windowsGbk(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  const gbkCodePage = 936;
  const errorOnInvalid = 0x8; // MB_ERR_INVALID_CHARS
  final convert = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_MultiByteNative, _MultiByteDart>('MultiByteToWideChar');
  return using((arena) {
    final input = arena<Uint8>(bytes.length);
    input.asTypedList(bytes.length).setAll(0, bytes);
    final length = convert(gbkCodePage, errorOnInvalid, input, bytes.length, nullptr, 0);
    if (length <= 0) throw const FormatException('Not GBK text');
    final output = arena<Uint16>(length);
    if (convert(gbkCodePage, errorOnInvalid, input, bytes.length, output, length) != length) {
      throw const FormatException('Not GBK text');
    }
    return String.fromCharCodes(output.asTypedList(length));
  });
}

/// Android's Wi-Fi multicast lock (`pure_live/multicast_lock`): without it
/// many phones drop the SSDP announcements DLNA discovery listens for
/// (live_cast; 3.x found renderers through search replies only). Hold it
/// while a discovery runs.
final class MulticastLock {
  /// Creates the lock over [channel].
  new({this.channel = const MethodChannel('pure_live/multicast_lock')});

  /// The native channel.
  final MethodChannel channel;

  /// Takes the lock; false where there is none (not Android, no Wi-Fi
  /// service, permission refused).
  Future<bool> acquire() async {
    if (!Platform.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('acquire') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Gives the lock back.
  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('release');
    } on PlatformException {
      // Released with the engine anyway.
    }
  }

  /// Runs [action] while holding the lock.
  Future<T> hold<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }
}

/// The refresh-rate hint of Android (`pure_live/display_mode`), for
/// live_ui's `AdaptiveRefreshRateController`; the answer updates
/// [DisplayMode.info] (the settings page shows the rates).
Future<void> applyHighRefreshRate({required bool high}) => DisplayMode.applyHighRefreshRate(high: high);
