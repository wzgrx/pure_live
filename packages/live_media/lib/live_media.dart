/// Playback core of Pure Live, independent of the player engine
/// (docs/G-播放/G01-引擎/G01.1-播放核心/record.md): sources and plans, engine inputs, the
/// loopback relay (FLV splicing and HEVC rewriting, HLS with cookies,
/// descrambling and renewal), the source transaction, line and decoder
/// fallback, error classification and the source event fence. Pure Dart.
library;

export 'src/errors.dart';
export 'src/fallback.dart';
export 'src/fence.dart';
export 'src/input.dart';
export 'src/inputs/recipes.dart';
export 'src/proxy.dart';
export 'src/relay/flv.dart';
export 'src/relay/flv_splicer.dart';
export 'src/relay/hls_cookies.dart';
export 'src/relay/hls_relay.dart';
export 'src/relay/hls_window.dart';
export 'src/relay/loopback_relay.dart';
export 'src/relay/upstream.dart';
export 'src/source.dart';
export 'src/transport.dart';
