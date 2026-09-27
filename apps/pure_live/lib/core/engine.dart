import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/store.dart';

/// Creates playback engines: mpv on devices (ADR 0006), a fake in tests.
/// Decoding, output and latency follow the settings at creation time (the
/// next room or cell picks up a change, F-SET-06); CDN hosts noted
/// for proxied platforms go through the proxy (F-SET-07).
final Provider<EngineFactory> engineFactoryProvider = Provider<EngineFactory>((ref) {
  final settings = ref.watch(storeProvider).settings;
  final hosts = ref.watch(proxiedHostsProvider);
  return () => mpvEngineFactory(
    MpvEngineConfig(
      hardwareDecoding: settings.get(Settings.hardwareDecoding),
      hardwareDecoder: settings.get(Settings.hardwareDecoder),
      androidCompatibility: Platform.isAndroid && settings.get(Settings.androidCompatibility),
      lowLatency: settings.get(Settings.lowLatency),
      audioOutput: settings.get(Settings.audioOutput).isEmpty ? null : settings.get(Settings.audioOutput),
      httpProxy: (uri) => hosts.contains(uri) ? proxyUrl(settings) : null,
    ),
  )();
});

/// One loopback relay for every playback session, with the app's proxy
/// policy for upstream connections (ADR 0018). Proxy changes restart it.
final Provider<Future<LoopbackRelay> Function()> sharedRelayProvider = Provider<Future<LoopbackRelay> Function()>((
  ref,
) {
  final policy = ref.watch(proxyPolicyProvider);
  Future<LoopbackRelay>? relay;
  ref.onDispose(() => unawaited(relay?.then((r) => r.close())));
  return () => relay ??= LoopbackRelay.start(proxy: policy);
});

/// A playback session on the shared engine factory and relay.
PlaybackSession newPlaybackSession(Ref ref) => PlaybackSession(
  engine: ref.read(engineFactoryProvider),
  pipeline: SourcePipeline(relay: ref.read(sharedRelayProvider)),
);
