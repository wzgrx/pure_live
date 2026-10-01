import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/diagnostics.dart';
import 'package:live_player/src/engine.dart';
import 'package:live_player/src/mpv_options.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The [MpvPlatform] of a Flutter [platform]; null on Fuchsia.
MpvPlatform? mpvPlatformOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => MpvPlatform.android,
  TargetPlatform.iOS => MpvPlatform.ios,
  TargetPlatform.windows => MpvPlatform.windows,
  TargetPlatform.linux => MpvPlatform.linux,
  TargetPlatform.macOS => MpvPlatform.macos,
  TargetPlatform.fuchsia => null,
};

/// The display size in [params] with rotation applied (3.x's
/// `resolveVideoParamsDisplaySize`): width and height come from the same
/// event, so a transient width is never paired with an older height.
({int width, int height})? displaySizeOf(VideoParams params) {
  var width = params.dw ?? params.w ?? 0;
  var height = params.dh ?? params.h ?? 0;
  if (width <= 0 || height <= 0) return null;
  final rotate = (params.rotate ?? 0) % 180;
  if (rotate == 90) (width, height) = (height, width);
  return (width: width, height: height);
}

/// The mpv [PlayerEngine] over the media_kit fork in `third_party/` (3.x's
/// `MediaKitAdapter`, the only engine in v4).
///
/// - [MpvEngineConfig.liveProperties] are applied once per player; every
///   open sets `hwdec` (software for the session's decoder fallback) and
///   `http-proxy` (empty for loopback inputs), then loads the media with its
///   headers.
/// - mpv's error log goes through [NativeDiagnosticGate]; the session only
///   sees confirmed failures.
/// - Audio-only mode never reopens: Android turns the controller's video
///   output off (the fork's `setVideoOutputEnabled`), desktop selects
///   `vid=no`; Android does not re-send `vid=auto` after an open.
/// - Windows reports presented frames (the fork's `frameRevision`).
final class MpvEngine implements PlayerEngine {
  new _(this.player, this.controller, this.config) {
    _gate = NativeDiagnosticGate(onError: (error) => _add(EngineError(error)));
    _bind();
  }

  /// Creates the player and its video controller. Needs a Flutter binding.
  static Future<MpvEngine> create({MpvEngineConfig? config}) async {
    final resolved = config ?? MpvEngineConfig(platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux);
    MediaKit.ensureInitialized();
    final player = Player(configuration: const PlayerConfiguration(title: 'Pure Live'));
    final native = player.platform;
    if (native is NativePlayer) {
      for (final MapEntry(:key, :value) in resolved.liveProperties.entries) {
        await native.setProperty(key, value);
      }
    }
    final macos = resolved.platform == MpvPlatform.macos;
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: resolved.videoOutput,
        hwdec: resolved.preferredHardwareDecoder,
        enableHardwareAcceleration: !macos && resolved.preferredHardwareDecoder != 'no',
        androidAttachSurfaceAfterVideoParameters: resolved.customOutput || resolved.androidCompatibility ? null : false,
      ),
    );
    return MpvEngine._(player, controller, resolved);
  }

  /// The media_kit player.
  final Player player;

  /// Its video controller; `LiveVideoView` renders it.
  final VideoController controller;

  /// Configuration.
  final MpvEngineConfig config;

  late final NativeDiagnosticGate _gate;
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  VoidCallback? _frameListener;
  var _audioOnly = false;
  var _disposed = false;

  bool get _android => config.platform == MpvPlatform.android;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  bool get reportsFrames => config.platform == MpvPlatform.windows;

  void _add(EngineEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _bind() {
    final stream = player.stream;
    _subscriptions
      ..add(
        stream.playing.listen((playing) {
          _gate.playback(playing: playing, buffering: player.state.buffering, audioOnly: _audioOnly);
          _add(EnginePlaying(playing: playing));
        }),
      )
      ..add(
        stream.buffering.listen((buffering) {
          _gate.playback(playing: player.state.playing, buffering: buffering, audioOnly: _audioOnly);
          _add(EngineBuffering(buffering: buffering));
        }),
      )
      ..add(
        stream.completed.listen((completed) {
          if (completed) _add(const EngineCompleted());
        }),
      )
      ..add(
        stream.videoParams.listen((params) {
          final size = displaySizeOf(params);
          if (size == null) return;
          _gate.videoFrame();
          _add(EngineVideoSize(size.width, size.height));
        }),
      )
      ..add(
        stream.audioParams.listen((params) {
          if ((params.format?.isNotEmpty ?? false) || (params.sampleRate ?? 0) > 0) _gate.audioFrame();
        }),
      )
      ..add(stream.position.listen((position) => _add(EnginePosition(position))))
      ..add(stream.duration.listen((duration) => _add(EngineDuration(duration))))
      ..add(stream.log.listen((log) => _gate.log(log.prefix, log.level, log.text)));
    if (reportsFrames) {
      var last = controller.frameRevision.value;
      void onFrame() {
        final revision = controller.frameRevision.value;
        if (revision == last) return;
        last = revision;
        _add(const EngineFrame());
      }

      _frameListener = onFrame;
      controller.frameRevision.addListener(onFrame);
    }
  }

  Future<void> _setProperty(String name, String value) async {
    final native = player.platform;
    if (native is NativePlayer) await native.setProperty(name, value);
  }

  @override
  Future<void> open(EngineMedia media) async {
    _gate.beginOpen();
    try {
      await _setProperty('hwdec', config.hwdecFor(software: media.decoder == DecoderMode.software));
      await _setProperty('http-proxy', media.proxyUrl);
      await player.open(Media(media.uri.toString(), httpHeaders: media.headers, start: media.start));
    } on Object catch (error, stack) {
      if (error is PlayerException) rethrow;
      final classification = NativeDiagnostic.classify(error.toString());
      throw PlayerException(
        message: 'Media open failed: $error',
        type: classification.type == PlayerErrorType.native ? PlayerErrorType.source : classification.type,
        code: classification.code,
        error: error,
        stackTrace: stack,
      );
    } finally {
      _gate.finishOpen();
    }
    if (media.audioOnly) {
      await _applyAudioOnly(enabled: true);
    } else if (_audioOnly) {
      await _applyAudioOnly(enabled: false);
    }
    // The session acts on these once the open is authorized.
    final state = player.state;
    final size = displaySizeOf(state.videoParams);
    if (size != null) _add(EngineVideoSize(size.width, size.height));
    _add(EngineBuffering(buffering: state.buffering));
    _add(EnginePlaying(playing: state.playing));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> seek(Duration position) => player.seek(position);

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
    if (!_audioOnly) return;
    // Wait for a decoded picture (at most 2.8 s) so the view never uncovers
    // a black texture.
    final picture = Completer<void>();
    final subscription = player.stream.videoParams.listen((params) {
      if (displaySizeOf(params) != null && !picture.isCompleted) picture.complete();
    });
    try {
      if (_android) {
        await controller.setVideoOutputEnabled(true);
      } else {
        await player.setVideoTrack(VideoTrack.auto());
      }
      _audioOnly = false;
      await picture.future.timeout(const Duration(milliseconds: 2800), onTimeout: () {});
    } finally {
      unawaited(subscription.cancel());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _gate.close();
    final listener = _frameListener;
    if (listener != null) controller.frameRevision.removeListener(listener);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await player.stop();
    } on Object {
      // Already stopped or never opened.
    }
    await player.dispose();
    await _events.close();
  }
}

/// An [EngineFactory] creating [MpvEngine]s with [config].
EngineFactory mpvEngineFactory([MpvEngineConfig? config]) =>
    () => MpvEngine.create(config: config);
