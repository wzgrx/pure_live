import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/player/core/live_audio_handler.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Session session;
  late LiveAudioHandler handler;
  late _Player first;
  late _Player second;

  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('pure-live-audio-ownership-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
    Get.put<SettingsService>(_Settings());
    session = _Session();
    handler = LiveAudioHandler(sessionProvider: () async => session);
    first = _Player();
    second = _Player();
    await handler.activateSession();
    session.activations.clear();
    await handler.setPlayer(first);
  });
  tearDown(() async {
    if (first.stopGate?.isCompleted == false) first.stopGate!.complete();
    await handler.releasePlayer();
    await session.interruptions.close();
    await session.noisy.close();
    await first.dispose();
    await second.dispose();
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('a queued noisy event belongs to the player bound when it arrived', () async {
    final gate = Completer<({int sessionId, int intentRevision})?>();
    var pauses = 0;
    handler.configurePlaybackCommands(
      play: () async {},
      pause: () async {
        pauses++;
      },
      stop: () async {},
      pauseForInterruption: () => gate.future,
      resumeFromInterruption: (_) async => true,
    );
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    session.noisy.add(null);
    await handler.setPlayer(second);
    gate.complete((sessionId: 1, intentRevision: 1));
    await flush();
    expect(pauses, 0, reason: 'old headphone event must not pause the replacement room');
  });

  test('a late old pause token does not suppress interruption of the new player', () async {
    final gate = Completer<({int sessionId, int intentRevision})?>();
    var calls = 0;
    handler.configurePlaybackCommands(
      play: () async {},
      pause: () async {},
      stop: () async {},
      pauseForInterruption: () async {
        calls++;
        return calls == 1 ? gate.future : (sessionId: 2, intentRevision: 1);
      },
      resumeFromInterruption: (_) async => true,
    );
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    await handler.setPlayer(second);
    gate.complete((sessionId: 1, intentRevision: 1));
    await flush();
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    expect(calls, 2);
  });

  test('an unmatched interruption end does not start paused fallback playback', () async {
    first.playing = false;
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(first.playCalls, 0);
  });

  test('release detaches playback state and ignores later notification play', () async {
    await handler.releasePlayer();
    first.states.add(true);
    await flush();
    await handler.play();
    expect(first.playCalls, 0);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('old release completion leaves a newly bound player active', () async {
    final gate = Completer<void>();
    first.stopGate = gate;
    final release = handler.releasePlayer();
    await flush();
    await handler.setPlayer(second);
    second.states.add(true);
    await flush();
    gate.complete();
    first.stopGate = null;
    await release;
    expect(session.activations, isEmpty, reason: 'old release must not abandon the new audio focus');
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('notification play awaiting audio focus does not transfer to a new binding', () async {
    final gate = Completer<bool>();
    session.activationGate = gate;
    final play = handler.play();
    await flush();
    await handler.setPlayer(second);
    gate.complete(true);
    session.activationGate = null;
    await play;
    expect(first.playCalls, 0);
    expect(second.playCalls, 0);
  });

  test('concurrent binding cancels old listeners without installing a stale one', () async {
    final gate = Completer<void>();
    first.cancelGate = gate;
    final bindSecond = handler.setPlayer(second);
    await flush();
    final third = _Player();
    addTearDown(third.dispose);
    final bindThird = handler.setPlayer(third);
    gate.complete();
    first.cancelGate = null;
    await Future.wait([bindSecond, bindThird]);
    expect(second.listenCount, 0, reason: 'a superseded bind must not leave an untracked subscription');
    third.states.add(true);
    await flush();
    second.states.add(false);
    await flush();
    expect(handler.playbackState.value.playing, isTrue);
    await handler.releasePlayer();
  });

  test('same-adapter source replacement invalidates old interruption ownership', () async {
    var source = 1;
    await handler.setPlayer(first, isSourceCurrent: () => source == 1);
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    expect(first.playing, isFalse);
    source = 2;
    expect(handler.hasActiveBinding, isFalse);
    await handler.setPlayer(first, isSourceCurrent: () => source == 2);
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(handler.hasActiveBinding, isTrue);
    expect(first.playCalls, 0);
  });

  test('an invalidated source drops status and commands before a replacement binds', () async {
    var current = true;
    await handler.setPlayer(first, isSourceCurrent: () => current);
    current = false;
    first.states.add(true);
    session.noisy.add(null);
    await handler.play();
    await handler.pause();
    await flush();
    expect(first.playCalls, 0);
    expect(first.playing, isTrue);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('a matching fallback interruption resumes once and manual pause cancels it', () async {
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(first.playCalls, 1);
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(first.playCalls, 1);
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    await handler.pause();
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(first.playCalls, 1);
    expect(first.playing, isFalse);
  });

  test('focus rejection does not start playback and a later request may succeed', () async {
    session.activationResult = false;
    await handler.play();
    expect(first.playCalls, 0);
    session.activationResult = true;
    await handler.play();
    expect(first.playCalls, 1);
  });

  test('focus release and new activation execute in order without stale idle status', () async {
    final gate = Completer<bool>();
    session.activationGate = gate;
    final release = handler.releasePlayer();
    await flush();
    expect(session.activations, [false]);
    await handler.setPlayer(second);
    second.states.add(true);
    final activate = handler.activateSession();
    await flush();
    expect(session.activations, [false]);
    session.activationGate = null;
    gate.complete(true);
    await Future.wait([release, activate]);
    expect(session.activations, [false, true]);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('release awaiting cancellation does not stop a reused adapter source', () async {
    final gate = Completer<void>();
    first.cancelGate = gate;
    final release = handler.releasePlayer();
    await flush();
    await handler.setPlayer(first);
    first.cancelGate = null;
    gate.complete();
    await release;
    expect(first.stopCalls, 0);
    expect(handler.hasActiveBinding, isTrue);
  });

  test('duck end from a retired player does not force the new player volume', () async {
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    await flush();
    await handler.setPlayer(second);
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    await flush();
    expect(second.volumes, isEmpty);
  });

  test('ducking respects room volume and restores the current user choice', () async {
    var volume = 0.4;
    await handler.setPlayer(first, targetVolume: () => volume);
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    await flush();
    expect(first.volumes.single, closeTo(0.08, 0.0001));
    volume = 0.7;
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    await flush();
    expect(first.volumes.last, 0.7);
    volume = 0;
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    await flush();
    expect(first.volumes.sublist(2), [0.0, 0.0]);
  });

  test('an already resumed fallback player is not played twice by interruption end', () async {
    session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await flush();
    await handler.play();
    session.interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await flush();
    expect(first.playCalls, 1);
  });

  test('a failed focus operation does not poison later notification commands', () async {
    session.activationError = StateError('fixture focus failure');
    await expectLater(handler.play(), throwsStateError);
    session.activationError = null;
    await handler.play();
    expect(first.playCalls, 1);
  });

  test('a pending old interruption does not block system events for the new binding', () async {
    final gate = Completer<({int sessionId, int intentRevision})?>();
    var calls = 0;
    handler.configurePlaybackCommands(
      play: () async {},
      pause: () async {},
      stop: () async {},
      pauseForInterruption: () async {
        calls++;
        return calls == 1 ? gate.future : (sessionId: 2, intentRevision: 1);
      },
      resumeFromInterruption: (_) async => true,
    );
    try {
      session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await flush();
      await handler.setPlayer(second);
      session.interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await flush();
      expect(calls, 2);
    } finally {
      gate.complete((sessionId: 1, intentRevision: 1));
      await flush();
    }
  });
}

class _Session implements AudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast(sync: true);
  final noisy = StreamController<void>.broadcast(sync: true);
  final activations = <bool>[];
  Completer<bool>? activationGate;
  bool activationResult = true;
  Object? activationError;
  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream => interruptions.stream;
  @override
  Stream<void> get becomingNoisyEventStream => noisy.stream;
  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}
  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration = const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    if (activationError != null) throw activationError!;
    return activationGate?.future ?? activationResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements UnifiedPlayer {
  final states = StreamController<bool>.broadcast(sync: true);
  final volumes = <double>[];
  Completer<void>? stopGate;
  Completer<void>? cancelGate;
  var playing = true;
  var playCalls = 0;
  var stopCalls = 0;
  var listenCount = 0;
  Future<void> dispose() async {
    if (cancelGate?.isCompleted == false) cancelGate!.complete();
    await states.close();
  }

  @override
  Stream<bool> get onPlaying => _StateStream(this);
  @override
  bool get isPlayingNow => playing;
  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate?.future;
    playing = false;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StateStream extends Stream<bool> {
  _StateStream(this.player);
  final _Player player;
  @override
  StreamSubscription<bool> listen(
    void Function(bool)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    player.listenCount++;
    final subscription = player.states.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _StateSubscription(subscription, () => player.cancelGate?.future);
  }
}

class _StateSubscription implements StreamSubscription<bool> {
  _StateSubscription(this.inner, this.cancelGate);
  final StreamSubscription<bool> inner;
  final Future<void>? Function() cancelGate;
  @override
  Future<void> cancel() async {
    await inner.cancel();
    await cancelGate();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends SettingsService {
  @override
  final app = AppSettingsController();
  @override
  // Do not initialize unrelated production services in this unit fixture.
  // ignore: must_call_super
  void onInit() {}
}
