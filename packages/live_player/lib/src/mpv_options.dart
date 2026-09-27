import 'package:flutter/foundation.dart';

/// How `MpvEngine` configures libmpv for live streams (spec/modules/playback.md
/// PERF-3, PERF-4, REC-1, SURF-6). One property set for the room player and
/// every multiview cell.
@immutable
final class MpvEngineConfig {
  /// Creates a configuration.
  const new({
    this.hardwareDecoding = true,
    this.hardwareDecoder = 'auto-safe',
    this.androidCompatibility = false,
    this.lowLatency = false,
    this.httpProxy,
    this.audioOutput,
  });

  /// Decode in hardware when possible; mpv falls back to software on the
  /// first failing frame (`hwdec-software-fallback=1`), and the session
  /// retries a failing URL once with software decoding (REC-1 step 4).
  final bool hardwareDecoding;

  /// mpv `hwdec` value when [hardwareDecoding] is on.
  final String hardwareDecoder;

  /// Android compatibility mode, a user setting (SURF-6): `mediacodec_embed`
  /// output with `mediacodec` decoding.
  final bool androidCompatibility;

  /// Smaller caches and probes for lower latency (PERF-4; values provisional
  /// until measured on devices).
  final bool lowLatency;

  /// Proxy URL for a non-loopback media URL (`http://127.0.0.1:7897`), or
  /// null for a direct connection. Loopback inputs never use it (SRC-3).
  final String? Function(Uri url)? httpProxy;

  /// mpv `ao` override; the platform default when null.
  final String? audioOutput;

  /// The `hwdec` value for an open.
  String hwdecFor({required bool softwareDecoding}) {
    if (softwareDecoding || !hardwareDecoding) return 'no';
    return androidCompatibility ? 'mediacodec' : hardwareDecoder;
  }

  /// Properties applied once after the player is created.
  Map<String, String> get liveProperties => {
    // PERF-4 start-up: short probes, a network timeout that ends a dead
    // connection as `completed` (EVT-15), hardware-decoder fallback after the
    // first failing frame, and a seekable demuxer cache.
    'demuxer-lavf-probesize': lowLatency ? '524288' : '2097152',
    'demuxer-lavf-analyzeduration': lowLatency ? '1' : '2',
    'network-timeout': '15',
    'hwdec-software-fallback': '1',
    'force-seekable': 'yes',
    // PERF-3 bounded memory: live streams are not meaningfully seekable, so
    // the forward and back buffers stay small and never go to disk.
    'cache': 'yes',
    'cache-on-disk': 'no',
    'cache-secs': lowLatency ? '2' : '6',
    'demuxer-max-bytes': '${32 * 1024 * 1024}',
    'demuxer-max-back-bytes': '${4 * 1024 * 1024}',
    'demuxer-readahead-secs': lowLatency ? '1' : '2',
    'protocol_whitelist': 'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto',
    'ao': ?audioOutput,
  };
}
