import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/event_mapper.dart';
import 'package:live_player/src/mpv_options.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The mpv [PlayerEngine] (ADR 0006: mpv on every platform) over the
/// self-maintained media_kit fork (ADR 0002).
///
/// - Events are media_kit's own streams mapped in arrival order
///   ([MediaKitEventMapper]); on Windows the patched `frameRevision` adds
///   frame progress (EVT-11).
/// - Every open sets `http-proxy` (empty for loopback inputs, SRC-3) and
///   `hwdec` (software for a software retry, REC-1 step 4) before loading.
/// - Audio-only mode never reopens (AUD-1): Android turns the video output
///   off through the patched controller, desktop selects `vid=no`. Turning
///   video back on waits for a decoded picture (at most 2.8 s, then about two
///   frames) so the view never uncovers a black texture (AUD-2). Android
///   does not re-send `vid=auto` after an open (EVT-9).
/// - [dispose] waits for media_kit's release, which on Windows runs the
///   patched teardown order (SURF-2).
final class MpvEngine implements PlayerEngine {
  new _(this.player, this.controller, this.config)
    : _mapper = MediaKitEventMapper(
        MediaKitStreams.of(player.stream),
        frames: defaultTargetPlatform == TargetPlatform.windows && !kIsWeb ? controller.frameRevision : null,
      );

  /// Creates the player and its video controller and applies
  /// [MpvEngineConfig.liveProperties]. Needs a Flutter binding.
  static Future<MpvEngine> create({MpvEngineConfig config = const MpvEngineConfig()}) async {
    MediaKit.ensureInitialized();
    final player = Player(
      // Error-level logs feed the diagnostics (EVT-7); 32 MiB demuxer buffer (PERF-3).
      configuration: const PlayerConfiguration(title: 'Pure Live'),
    );
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: config.androidCompatibility && defaultTargetPlatform == TargetPlatform.android ? 'mediacodec_embed' : null,
        hwdec: config.hwdecFor(softwareDecoding: false),
        enableHardwareAcceleration: config.hardwareDecoding,
      ),
    );
    final engine = MpvEngine._(player, controller, config);
    for (final MapEntry(:key, :value) in config.liveProperties.entries) {
      await engine._setProperty(key, value);
    }
    return engine;
  }

  /// The media_kit player.
  final Player player;

  /// Its video controller; `LiveVideoView` renders it.
  final VideoController controller;

  /// Configuration.
  final MpvEngineConfig config;

  final MediaKitEventMapper _mapper;
  var _audioOnly = false;
  var _disposed = false;

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  EngineCapabilities get capabilities =>
      EngineCapabilities(frameProgress: defaultTargetPlatform == TargetPlatform.windows && !kIsWeb);

  @override
  Stream<EngineEvent> get events => _mapper.events;

  Future<void> _setProperty(String name, String value) async {
    final platform = player.platform;
    if (platform is NativePlayer) await platform.setProperty(name, value);
  }

  @override
  Future<void> open(EngineMedia media) async {
    await _setProperty('http-proxy', media.local ? '' : config.httpProxy?.call(media.uri) ?? '');
    await _setProperty('hwdec', config.hwdecFor(softwareDecoding: media.softwareDecoding));
    await player.open(Media(media.uri.toString(), httpHeaders: media.headers));
    if (media.audioOnly) {
      await _applyAudioOnly(enabled: true);
    } else if (_audioOnly && !_android) {
      await player.setVideoTrack(VideoTrack.auto());
      _audioOnly = false;
    } else if (_audioOnly) {
      await controller.setVideoOutputEnabled(true);
      _audioOnly = false;
    }
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setVolume(double volume) => player.setVolume((volume * 100).clamp(0, 100).toDouble());

  @override
  Future<void> setAudioOnly({required bool enabled}) => _applyAudioOnly(enabled: enabled);

  Future<void> _applyAudioOnly({required bool enabled}) async {
    if (enabled) {
      if (_android) {
        await controller.setVideoOutputEnabled(false);
      } else {
        await player.setVideoTrack(VideoTrack.no());
      }
      _audioOnly = true;
      return;
    }
    final picture = Completer<void>();
    final subscription = player.stream.videoParams.listen((params) {
      final width = params.dw ?? params.w ?? 0;
      final height = params.dh ?? params.h ?? 0;
      if (width > 0 && height > 0 && !picture.isCompleted) picture.complete();
    });
    try {
      if (_android) {
        await controller.setVideoOutputEnabled(true);
      } else {
        await player.setVideoTrack(VideoTrack.auto());
      }
      _audioOnly = false;
      var ready = true;
      await picture.future.timeout(const Duration(milliseconds: 2800), onTimeout: () => ready = false);
      // videoParams precede the first composited frame by a moment.
      if (ready) await Future<void>.delayed(const Duration(milliseconds: 34));
    } finally {
      unawaited(subscription.cancel());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _mapper.close();
    try {
      await player.stop();
    } on Object {
      // Already stopped or never opened.
    }
    await player.dispose();
  }
}

/// An [EngineFactory] creating [MpvEngine]s with [config].
EngineFactory mpvEngineFactory([MpvEngineConfig config = const MpvEngineConfig()]) =>
    () => MpvEngine.create(config: config);
