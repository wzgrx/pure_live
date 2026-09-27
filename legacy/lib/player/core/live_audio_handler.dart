import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/player/core/background_playback_policy.dart';
import 'package:pure_live/player/core/background_playback_service.dart';
import 'package:pure_live/player/core/playback_lifecycle_coordinator.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';

class LiveAudioHandler extends BaseAudioHandler {
  UnifiedPlayer? _currentPlayer; // 动态绑定
  late AudioSession _session;
  late final Future<void> _sessionReady;

  StreamSubscription? _playStateSubscription;
  Timer? _sleepTimer;
  Future<void> _audioEventQueue = Future<void>.value();
  Future<void> _focusQueue = Future<void>.value();
  int _bindingRevision = 0;
  bool Function()? _sourceIsCurrent;
  double Function()? _targetVolume;
  bool _fallbackInterruptedPlaying = false;
  bool _ducked = false;
  PlaybackLifecyclePauseToken? _interruptionToken;
  Future<void> Function()? _playCommand;
  Future<void> Function()? _pauseCommand;
  Future<void> Function()? _stopCommand;
  Future<PlaybackLifecyclePauseToken?> Function()? _pauseForInterruption;
  Future<bool> Function(PlaybackLifecyclePauseToken token)? _resumeFromInterruption;

  LiveAudioHandler({Future<AudioSession> Function()? sessionProvider})
    : _sessionProvider = sessionProvider ?? _defaultSessionProvider {
    _sessionReady = _initSession();
  }

  final Future<AudioSession> Function() _sessionProvider;
  static Future<AudioSession> _defaultSessionProvider() => AudioSession.instance;

  Future<void> setPlayer(
    UnifiedPlayer player, {
    bool Function()? isSourceCurrent,
    double Function()? targetVolume,
  }) async {
    final revision = ++_bindingRevision;
    // A slow native pause in the previous binding must not block the new
    // source's system events. Detached callbacks still check their revision.
    _audioEventQueue = Future<void>.value();
    final previous = _playStateSubscription;
    _playStateSubscription = null;
    _interruptionToken = null;
    _fallbackInterruptedPlaying = false;
    _ducked = false;
    _currentPlayer = player;
    _sourceIsCurrent = isSourceCurrent;
    _targetVolume = targetVolume;
    await previous?.cancel();
    if (_ownsBinding(player, revision)) _listenPlayState(player, revision);
  }

  bool _ownsBinding(UnifiedPlayer player, int revision) =>
      revision == _bindingRevision && identical(_currentPlayer, player) && (_sourceIsCurrent?.call() ?? true);

  bool get hasActiveBinding {
    final player = _currentPlayer;
    return player != null && _ownsBinding(player, _bindingRevision);
  }

  void configurePlaybackCommands({
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    required Future<PlaybackLifecyclePauseToken?> Function() pauseForInterruption,
    required Future<bool> Function(PlaybackLifecyclePauseToken token) resumeFromInterruption,
  }) {
    _playCommand = play;
    _pauseCommand = pause;
    _stopCommand = stop;
    _pauseForInterruption = pauseForInterruption;
    _resumeFromInterruption = resumeFromInterruption;
  }

  void _enqueueAudioEvent(Future<void> Function(bool Function() isCurrent) operation) {
    final player = _currentPlayer;
    final revision = _bindingRevision;
    if (player == null) return;
    bool isCurrent() => _ownsBinding(player, revision);
    _audioEventQueue = _audioEventQueue
        .then((_) async {
          if (isCurrent()) await operation(isCurrent);
        })
        .catchError((Object error, StackTrace stackTrace) {
          developer.log('Audio session event failed: $error', stackTrace: stackTrace);
        });
  }

  Future<void> _initSession() async {
    _session = await _sessionProvider();
    await _session.configure(const AudioSessionConfiguration.music());

    // 音频中断（来电、通知）
    _session.interruptionEventStream.listen((event) {
      if (_currentPlayer == null) return;

      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.pause:
            _enqueueAudioEvent((isCurrent) async {
              if (_interruptionToken != null || _fallbackInterruptedPlaying) return;
              final pauseForInterruption = _pauseForInterruption;
              if (pauseForInterruption != null) {
                final token = await pauseForInterruption();
                if (isCurrent()) _interruptionToken = token;
              } else {
                final player = _currentPlayer!;
                final wasPlaying = player.isPlayingNow;
                if (wasPlaying) await player.pause();
                if (isCurrent()) _fallbackInterruptedPlaying = wasPlaying;
              }
            });
            break;
          case AudioInterruptionType.unknown:
            break;
          case AudioInterruptionType.duck:
            _enqueueAudioEvent((isCurrent) async {
              if (_ducked) return;
              await _currentPlayer!.setVolume((_targetVolume?.call() ?? 1.0).clamp(0.0, 1.0) * 0.2);
              if (isCurrent()) _ducked = true;
            });
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.pause:
            _enqueueAudioEvent((isCurrent) async {
              final token = _interruptionToken;
              _interruptionToken = null;
              final fallbackWasPlaying = _fallbackInterruptedPlaying;
              _fallbackInterruptedPlaying = false;
              final resumeFromInterruption = _resumeFromInterruption;
              if (token != null && resumeFromInterruption != null) {
                await resumeFromInterruption(token);
              } else if (resumeFromInterruption == null && fallbackWasPlaying && !_currentPlayer!.isPlayingNow) {
                await _currentPlayer?.play();
              }
            });
            break;
          case AudioInterruptionType.duck:
            _enqueueAudioEvent((isCurrent) async {
              if (!_ducked) return;
              _ducked = false;
              await _currentPlayer!.setVolume((_targetVolume?.call() ?? 1.0).clamp(0.0, 1.0));
            });
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // 拔掉耳机 / 连接蓝牙音箱暂停
    _session.becomingNoisyEventStream.listen((_) {
      _enqueueAudioEvent((isCurrent) async {
        _interruptionToken = null;
        _fallbackInterruptedPlaying = false;
        final pauseCommand = _pauseCommand;
        if (pauseCommand != null) {
          await pauseCommand();
        } else {
          await _currentPlayer?.pause();
        }
      });
    });
  }

  /// 监听播放状态同步到通知栏
  void _listenPlayState(UnifiedPlayer player, int revision) {
    _playStateSubscription = player.onPlaying.listen((playing) {
      if (!_ownsBinding(player, revision)) return;
      final keepAlive =
          playing &&
          BackgroundPlaybackPolicy.shouldContinue(
            backgroundPlaybackEnabled: SettingsService.to.app.enableBackgroundPlay.value,
            sleepSessionActive: BackgroundPlaybackService.sleepSessionActive,
            audioOnlySessionActive: BackgroundPlaybackService.audioOnlySessionActive,
          );

      unawaited(BackgroundPlaybackService.setKeepAlive(keepAlive));

      playbackState.add(
        playbackState.value.copyWith(
          controls: [playing ? MediaControl.pause : MediaControl.play, MediaControl.stop],
          // 单直播流不存在上一首/下一首，保留播放与停止即可，避免生成
          // 无实际处理器的通知栏动作，也让紧凑通知的索引始终有效。
          androidCompactActionIndices: const [0, 1],
          playing: playing,
          processingState: AudioProcessingState.ready,
        ),
      );
    });
  }

  void configureSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;

    if (duration == null || duration <= Duration.zero) return;

    _sleepTimer = Timer(duration, () async {
      BackgroundPlaybackService.sleepSessionActive = false;
      await stop();
    });
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  /// Claims media audio focus as soon as playback starts in the room. Waiting
  /// until the notification play action is pressed makes Android pause the
  /// already-running stream when the app first goes to the background.
  Future<bool> activateSession({bool Function()? isCurrent}) => _setSessionActive(true, isCurrent: isCurrent);

  Future<bool> _setSessionActive(bool active, {bool Function()? isCurrent}) {
    final operation = _focusQueue.then((_) async {
      await _sessionReady;
      if (isCurrent?.call() == false) return false;
      return _session.setActive(active);
    });
    // Preserve the caller's error, but one failure must not poison later focus commands.
    _focusQueue = operation.then<void>((_) {}).catchError((Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<void> play() async {
    final player = _currentPlayer;
    final revision = _bindingRevision;
    if (player == null) return;
    bool isCurrent() => _ownsBinding(player, revision);
    if (!await activateSession(isCurrent: isCurrent)) return;
    if (!isCurrent()) return;
    final playCommand = _playCommand;
    await (playCommand != null ? playCommand() : _currentPlayer!.play());
  }

  @override
  Future<void> pause() async {
    final player = _currentPlayer;
    if (player == null || !_ownsBinding(player, _bindingRevision)) return;
    _fallbackInterruptedPlaying = false;
    _interruptionToken = null;
    final pauseCommand = _pauseCommand;
    await (pauseCommand != null ? pauseCommand() : _currentPlayer!.pause());
  }

  @override
  Future<void> stop() async {
    final stopCommand = _stopCommand;
    if (stopCommand != null) {
      await stopCommand();
      return;
    }
    await releasePlayer();
  }

  Future<void> releasePlayer() async {
    final player = _currentPlayer;
    final revision = ++_bindingRevision;
    _audioEventQueue = Future<void>.value();
    final subscription = _playStateSubscription;
    _playStateSubscription = null;
    _currentPlayer = null;
    _sourceIsCurrent = null;
    _targetVolume = null;
    BackgroundPlaybackService.sleepSessionActive = false;
    BackgroundPlaybackService.audioOnlySessionActive = false;
    _interruptionToken = null;
    _fallbackInterruptedPlaying = false;
    _ducked = false;

    _sleepTimer?.cancel();
    _sleepTimer = null;

    try {
      try {
        await subscription?.cancel();
      } finally {
        // The same adapter may already own a newer source while subscription
        // cleanup awaits. Do not stop that replacement source.
        if (_bindingRevision == revision || !identical(_currentPlayer, player)) await player?.stop();
      }
    } catch (e) {
      developer.log("Player already disposed or failed to stop: $e");
    } finally {
      bool stillReleased() => _bindingRevision == revision && _currentPlayer == null;
      if (stillReleased()) {
        await _setSessionActive(false, isCurrent: stillReleased);
        if (stillReleased()) {
          await BackgroundPlaybackService.setKeepAlive(false);
          if (stillReleased()) {
            playbackState.add(playbackState.value.copyWith(playing: false, processingState: AudioProcessingState.idle));
          }
        }
      }
    }
  }
}
