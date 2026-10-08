import 'dart:async';

import 'package:live_player/live_player.dart';

/// A scripted [PlayerEngine]: records every call; [onOpen] decides what an
/// open does (default: succeed, then report buffering and playing).
final class FakeEngine implements PlayerEngine {
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);

  /// Every opened media, in order.
  final List<EngineMedia> opens = [];

  /// Calls other than open, in order (`play`, `pause`, `stop`, `seek`, ...).
  final List<String> calls = [];

  /// What the next opens do; null opens and plays.
  Future<void> Function(EngineMedia media)? onOpen;

  @override
  bool reportsFrames = false;

  /// Whether [dispose] ran.
  bool disposed = false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  /// Reports [event].
  void emit(EngineEvent event) => _events.add(event);

  /// The position [advance] reports next.
  Duration position = Duration.zero;

  /// Reports playback moving on by [step] (mpv's `time-pos`).
  void advance([Duration step = const Duration(seconds: 1)]) {
    position += step;
    emit(EnginePosition(position));
  }

  /// Reports a started picture.
  void playing() {
    emit(const EngineBuffering(buffering: false));
    emit(const EnginePlaying(playing: true));
  }

  @override
  Future<void> open(EngineMedia media) async {
    opens.add(media);
    final script = onOpen;
    if (script != null) {
      await script(media);
      return;
    }
    playing();
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async => calls.add('seek ${position.inSeconds}');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume $volume');

  @override
  Future<void> setAudioOnly({required bool enabled}) async => calls.add('audioOnly $enabled');

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
