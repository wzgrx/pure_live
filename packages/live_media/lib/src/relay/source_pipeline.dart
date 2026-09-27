import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv_splicer.dart';
import 'package:live_media/src/relay/loopback_relay.dart';

/// How a line reaches the engine (SRC-2, checked in this order).
enum PipelineMode {
  /// FLV whose lease cuts the connection: the loopback relay splices renewals in (SRC-5).
  splice,

  /// HLS with a relay recipe (per-path cookies, restored segments): the
  /// loopback relay rewrites and forwards it.
  hls,

  /// Everything else, single HTTP streams (`StreamFormat.other`) included:
  /// the engine connects to the CDN itself.
  direct;

  /// The mode for [line]. Splicing needs a way to renew the line. Codec-12
  /// HEVC needs no rewriting: every v4 libmpv ships FFmpeg >= 8.
  static PipelineMode of(StreamLine line, {required bool canRenew}) {
    final lease = line.lease;
    if (canRenew && line.format == StreamFormat.flv && lease != null && lease.cutsConnection) return splice;
    if (line.format == StreamFormat.hls && line.hlsRelay != null) return hls;
    return direct;
  }
}

/// One opened input: what the engine opens, released when replaced (SRC-1).
abstract interface class PlaybackInput {
  /// How the line is delivered.
  PipelineMode get mode;

  /// URI for the engine.
  Uri get uri;

  /// Headers for the engine; empty for a relayed input.
  Map<String, String> get headers;

  /// A loopback input the engine must not proxy (SRC-3).
  bool get local;

  /// Whether the relay renews the lease itself (then the session neither
  /// prefetches nor hands over, SRC-5).
  bool get renewsLease;

  /// Releases the input.
  Future<void> close();
}

final class _DirectInput implements PlaybackInput {
  new(this.line);

  final StreamLine line;

  @override
  PipelineMode get mode => PipelineMode.direct;

  @override
  Uri get uri => line.url;

  @override
  Map<String, String> get headers => line.headers;

  @override
  bool get local => false;

  @override
  bool get renewsLease => false;

  @override
  Future<void> close() async {}
}

final class _RelayedInput implements PlaybackInput {
  new(this.input, this.mode);

  final RelayInput input;

  @override
  final PipelineMode mode;

  @override
  Uri get uri => input.uri;

  @override
  Map<String, String> get headers => const {};

  @override
  bool get local => true;

  /// Only the splice renews; an HLS relay keeps the session's prefetch, which
  /// also keeps a niconico seat open (spec/sites/niconico.md §6.4).
  @override
  bool get renewsLease => mode == PipelineMode.splice;

  @override
  Future<void> close() => input.close();
}

/// Turns lines into engine inputs, starting the loopback relay on first need.
final class SourcePipeline {
  /// Creates a pipeline. [relay] returns a shared relay the caller owns; by
  /// default the pipeline starts its own with [LoopbackRelay.start] (direct
  /// upstream routes) on first need, and [close] stops it.
  new({Future<LoopbackRelay> Function()? relay})
    : _startRelay = relay ?? LoopbackRelay.start,
      _ownsRelay = relay == null;

  final Future<LoopbackRelay> Function() _startRelay;
  final bool _ownsRelay;
  Future<LoopbackRelay>? _relay;

  /// Opens [line] of platform [site] (the relay's proxy route key). With
  /// [renew], a line whose lease cuts the connection is spliced; [onRenewed]
  /// then receives each line the relay switched to.
  Future<PlaybackInput> open(
    StreamLine line, {
    required String site,
    LineRenewer? renew,
    void Function(StreamLine line)? onRenewed,
    void Function(SpliceEvent event)? onEvent,
  }) async {
    switch (PipelineMode.of(line, canRenew: renew != null)) {
      case PipelineMode.direct:
        return _DirectInput(line);
      case PipelineMode.splice:
        final relay = await (_relay ??= _startRelay());
        return _RelayedInput(
          relay.openSplice(line, site: site, renew: renew!, onRenewed: onRenewed, onEvent: onEvent),
          PipelineMode.splice,
        );
      case PipelineMode.hls:
        final relay = await (_relay ??= _startRelay());
        return _RelayedInput(relay.openHls(line, site: site), PipelineMode.hls);
    }
  }

  /// Stops the relay if this pipeline started it.
  Future<void> close() async {
    final relay = _relay;
    _relay = null;
    if (relay != null && _ownsRelay) await (await relay).close();
  }
}
