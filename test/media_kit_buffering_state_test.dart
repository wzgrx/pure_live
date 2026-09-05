import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';
import 'package:pure_live/player/core/engine_fallback_manager.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
  });
  tearDown(Get.reset);

  for (final event in ['playing', 'video-tail', 'audio-tail']) {
    test('real adapter retains native buffering after $event until buffering ends', () async {
      final player = _ControlledPlayer();
      final adapter = MediaKitAdapter.headlessForTest(player);
      final loading = <bool>[];
      final states = <PlayerState>[];
      final subscriptions = [adapter.onLoading.listen(loading.add), adapter.onStateChanged.listen(states.add)];
      try {
        await adapter.setDataSource(
          'https://cdn.example/live.flv',
          const [],
          const {},
          audioOnly: event == 'audio-tail',
        );
        player.buffering(true);
        await _flushEvents();
        expect(loading.last, isTrue);
        if (event == 'playing') {
          player.playing(false);
          player.playing(true);
        } else if (event == 'video-tail') {
          player.videoFrame();
        } else {
          player.audioFrame();
        }
        await _flushEvents();
        expect(loading.last, isTrue, reason: 'playing and queued tail frames do not end demux buffering');
        expect(states.last, PlayerState.buffering);
        player.buffering(false);
        await _flushEvents();
        expect(loading.last, isFalse);
        expect(states.last, PlayerState.playing);
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await adapter.hardDispose();
      }
    });
  }

  test('open snapshot preserves buffering even when decoder parameters are ready', () async {
    final player = _ControlledPlayer()
      ..state = const mk.PlayerState(playing: true, buffering: true, videoParams: mk.VideoParams(w: 1920, h: 1080));
    final adapter = MediaKitAdapter.headlessForTest(player);
    final loading = <bool>[];
    final subscription = adapter.onLoading.listen(loading.add);
    try {
      await adapter.setDataSource('https://cdn.example/snapshot.flv', const [], const {});
      await _flushEvents();
      expect(loading.last, isTrue, reason: 'successful open is not the end of native buffering');
      player.buffering(false);
      await _flushEvents();
      expect(loading.last, isFalse);
    } finally {
      await subscription.cancel();
      await adapter.hardDispose();
    }
  });

  test('manager open completion does not overwrite adapter buffering with ready', () async {
    final player = _ControlledPlayer()
      ..state = const mk.PlayerState(playing: true, buffering: true, videoParams: mk.VideoParams(w: 1920, h: 1080));
    final adapter = MediaKitAdapter.headlessForTest(player);
    final manager = PlayerManager(
      playerCreator: (_) => adapter,
      fallbackManager: EngineFallbackManager(
        defaultEngine: PlayerEngine.mediaKit,
        supportedEngines: [PlayerEngine.mediaKit],
      ),
      lineManager: LineFallbackManager(),
      useHardStopOnExit: () => true,
      audioModeServiceSync: (_, _) async {},
      audioSessionStart: (_) async {},
    );
    manager.configureDefaultEngine(PlayerEngine.mediaKit);
    final states = <PlayerState>[];
    final subscription = manager.onStateChanged.listen(states.add);
    try {
      await manager.play('https://cdn.example/live.flv', const ['https://cdn.example/live.flv'], const {});
      await _flushEvents();
      expect(states.last, PlayerState.buffering);
      player.buffering(false);
      await _flushEvents();
      expect(states.last, PlayerState.playing);
    } finally {
      await subscription.cancel();
      await manager.dispose();
    }
  });

  test('playing without optional frame metadata ends source preparation when native is not buffering', () async {
    final player = _ControlledPlayer()..state = const mk.PlayerState();
    final adapter = MediaKitAdapter.headlessForTest(player);
    final loading = <bool>[];
    final subscription = adapter.onLoading.listen(loading.add);
    try {
      await adapter.setDataSource('https://cdn.example/first.flv', const [], const {});
      player.playing(true);
      await _flushEvents();
      expect(loading.last, isFalse);
      expect(adapter.isPlayingNow, isTrue);
      player.playing(false);
      await _flushEvents();
      expect(adapter.isPlayingNow, isFalse);
      expect(loading.last, isFalse);
    } finally {
      await subscription.cancel();
      await adapter.hardDispose();
    }
  });

  test('new source clears an old buffering episode from its own successful snapshot', () async {
    final player = _ControlledPlayer();
    final adapter = MediaKitAdapter.headlessForTest(player);
    final loading = <bool>[];
    final subscription = adapter.onLoading.listen(loading.add);
    try {
      await adapter.setDataSource('https://cdn.example/old.flv', const [], const {});
      player.buffering(true);
      await _flushEvents();
      expect(loading.last, isTrue);
      // No false callback for the old source: open's current state must recover
      // the new generation rather than inheriting a permanently true flag.
      player.state = const mk.PlayerState(playing: true);
      adapter.beginSourceTransition();
      await adapter.setDataSource('https://cdn.example/new.flv', const [], const {});
      await _flushEvents();
      expect(loading.last, isFalse);
      expect(adapter.isPlayingNow, isTrue);
    } finally {
      await subscription.cancel();
      await adapter.hardDispose();
      expect(player.stream.playingEvents.hasListener, isFalse);
      expect(player.stream.loadingEvents.hasListener, isFalse);
    }
  });

  test('late old open finalizer cannot publish a newer source native snapshot', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var opens = 0;
    final player = _ControlledPlayer()
      ..onOpen = () async {
        if (opens++ == 0) {
          entered.complete();
          await release.future;
        }
      };
    final adapter = MediaKitAdapter.headlessForTest(player);
    final loading = <bool>[];
    final subscription = adapter.onLoading.listen(loading.add);
    final oldOpen = adapter.setDataSource('https://cdn.example/old.flv', const [], const {});
    try {
      await entered.future.timeout(const Duration(seconds: 3));
      player.state = const mk.PlayerState(playing: true, videoParams: mk.VideoParams(w: 1920, h: 1080));
      await adapter.setDataSource('https://cdn.example/new.flv', const [], const {});
      player.buffering(true);
      await _flushEvents();
      expect(loading.last, isTrue);
      // The native snapshot can advance before its async event is delivered.
      // An old open still has no authority to publish it for this generation.
      player.state = player.state.copyWith(buffering: false);
      release.complete();
      await oldOpen;
      await _flushEvents();
      expect(loading.last, isTrue);
      player.buffering(false);
      await _flushEvents();
      expect(loading.last, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await oldOpen;
      await subscription.cancel();
      await adapter.hardDispose();
    }
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _ControlledPlayer implements mk.Player {
  Future<void> Function()? onOpen;
  @override
  mk.PlayerState state = const mk.PlayerState(playing: true);
  @override
  final _ControlledStreams stream = _ControlledStreams();
  @override
  mk.PlatformPlayer? platform;

  void buffering(bool value) {
    state = state.copyWith(buffering: value);
    stream.loadingEvents.add(value);
  }

  void playing(bool value) {
    state = state.copyWith(playing: value);
    stream.playingEvents.add(value);
  }

  void videoFrame() {
    const value = mk.VideoParams(w: 1920, h: 1080);
    state = state.copyWith(videoParams: value);
    stream.videoEvents.add(value);
  }

  void audioFrame() {
    const value = mk.AudioParams(format: 'float', sampleRate: 48000, channelCount: 2);
    state = state.copyWith(audioParams: value);
    stream.audioEvents.add(value);
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    await onOpen?.call();
  }

  @override
  Future<void> setVideoTrack(mk.VideoTrack track) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => stream.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

class _ControlledStreams implements mk.PlayerStream {
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  final loadingEvents = StreamController<bool>.broadcast(sync: true);
  final videoEvents = StreamController<mk.VideoParams>.broadcast(sync: true);
  final audioEvents = StreamController<mk.AudioParams>.broadcast(sync: true);
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<bool> get buffering => loadingEvents.stream;
  @override
  Stream<mk.VideoParams> get videoParams => videoEvents.stream;
  @override
  Stream<mk.AudioParams> get audioParams => audioEvents.stream;
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();

  Future<void> close() async {
    await Future.wait([playingEvents.close(), loadingEvents.close(), videoEvents.close(), audioEvents.close()]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}
