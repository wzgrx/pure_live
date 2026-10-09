import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

/// The system's audio focus as the room sees it (G05.1): asking for it and
/// giving it back, and what the system says while the room holds it. The
/// app uses [SystemAudioFocus]; tests give a fake.
abstract interface class AudioFocusPort {
  /// Asks for the focus ([active]) or gives it back; whether it was granted.
  Future<bool> activate({required bool active});

  /// Another sound wants the output: a call or an alarm ([AudioInterruptionType.pause]),
  /// a prompt that may play over a lower volume ([AudioInterruptionType.duck]),
  /// another player taking it for good ([AudioInterruptionType.unknown]);
  /// and their ends.
  Stream<AudioInterruptionEvent> get interruptions;

  /// Headphones were unplugged or a Bluetooth output went away (Android's
  /// `ACTION_AUDIO_BECOMING_NOISY`).
  Stream<void> get becomingNoisy;
}

/// [AudioFocusPort] over `audio_session` (3.x's `LiveAudioHandler`): set up
/// once as music.
final class SystemAudioFocus implements AudioFocusPort {
  new _();

  /// The app's one session.
  static final SystemAudioFocus instance = SystemAudioFocus._();

  /// Whether the system has an audio focus the room handles: Android only
  /// (the desktop and TV builds are another task; tests run on the host).
  static bool get available => Platform.isAndroid;

  Future<AudioSession>? _session;

  Future<AudioSession> _configured() => _session ??= () async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    return session;
  }();

  @override
  Future<bool> activate({required bool active}) async => await (await _configured()).setActive(active);

  @override
  Stream<AudioInterruptionEvent> get interruptions =>
      Stream.fromFuture(_configured()).asyncExpand((session) => session.interruptionEventStream);

  @override
  Stream<void> get becomingNoisy =>
      Stream.fromFuture(_configured()).asyncExpand((session) => session.becomingNoisyEventStream);
}

/// The room's audio focus (3.x `LiveAudioHandler._initSession`): the room
/// asks for the focus when it starts playing and gives it back when it is
/// left; then
/// - a call or an alarm pauses it, and their end resumes it, only when the
///   focus paused it and the user did nothing meanwhile; if the room may not
///   play where the app is now (in the background without background play),
///   it resumes once the app is back;
/// - a prompt lowers the volume to 20 % until it ends, back to the volume
///   before unless the user set another one meanwhile;
/// - another player taking the focus for good pauses it with no resume
///   (Android's permanent loss; 3.x ignored it), and playing again asks for
///   the focus again;
/// - unplugged headphones pause it for good.
///
/// Events are handled in order, one at a time (3.x's `_enqueueAudioEvent`).
/// Asking for the focus failing never stops playback.
class RoomAudioFocus with WidgetsBindingObserver {
  /// Creates the focus of [session]; call [start]. [mayPlayNow] says
  /// whether the room may play where the app is now (null: always).
  new({required this.session, required this.port, this.mayPlayNow});

  /// How far a prompt lowers the volume (3.x).
  static const duckFactor = 0.2;

  /// The room's player.
  final PlaybackSession session;

  /// The system's side.
  final AudioFocusPort port;

  /// Whether the room may play now (the background policy's rule).
  final bool Function()? mayPlayNow;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _queue = Future.value();
  bool _started = false;
  bool _disposed = false;
  bool _observing = false;

  /// The focus is held (asked for and not lost for good).
  bool _active = false;
  PlaybackStatus? _lastStatus;

  /// The focus paused the room; the end of the interruption resumes it.
  bool _pausedByFocus = false;

  /// A pause that the end of the interruption undoes is under way (the
  /// session reports "paused" before [_pausedByFocus] is set).
  bool _pausingToResume = false;

  /// Whether the room is paused by a call or another app and resumes when
  /// it ends (O01.3: the background keeps its foreground service meanwhile).
  bool get pausedUntilInterruptionEnds => _pausingToResume || _pausedByFocus || _resumeWhenBack;

  /// The user paused or stopped from the notification during an
  /// interruption: its end leaves the room paused (O01.3).
  void forgetResume() {
    _pausedByFocus = false;
    _resumeWhenBack = false;
  }

  /// The interruption ended where the room may not play: resume once the
  /// app is back.
  bool _resumeWhenBack = false;

  /// While a prompt plays: the volume before and the lowered one.
  double? _volumeBeforeDuck;
  double? _duckedVolume;

  /// Starts following the room and the system.
  void start({bool observeLifecycle = true}) {
    if (_started || _disposed) return;
    _started = true;
    _subscriptions
      ..add(session.states.listen(_onState))
      ..add(port.interruptions.listen(_onInterruption, onError: _onPortError))
      ..add(port.becomingNoisy.listen((_) => _enqueue(_onNoisy), onError: _onPortError));
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _onState(session.state);
  }

  void _onPortError(Object error) => developer.log('Audio session failed: $error', name: 'audio_focus');

  void _onState(PlaybackState state) {
    final status = state.status;
    final previous = _lastStatus;
    _lastStatus = status;
    if (status != PlaybackStatus.paused) {
      // The user played, or the room moved on (stopped, failed): a pause of
      // ours is no longer ours to undo.
      if (status != previous) {
        _pausedByFocus = false;
        _resumeWhenBack = false;
      }
    }
    if (status == PlaybackStatus.playing && previous != PlaybackStatus.playing && !_active) {
      _active = true;
      _enqueue(() => _activate(active: true));
    }
  }

  void _onInterruption(AudioInterruptionEvent event) {
    switch ((event.begin, event.type)) {
      case (true, AudioInterruptionType.pause):
        _enqueue(() => _pauseForFocus(resume: true));
      case (true, AudioInterruptionType.unknown):
        _active = false;
        _enqueue(() => _pauseForFocus(resume: false));
      case (true, AudioInterruptionType.duck):
        _enqueue(_duck);
      case (false, AudioInterruptionType.duck):
        _enqueue(_unduck);
      case (false, _):
        _enqueue(_interruptionEnded);
    }
  }

  bool get _sounding => switch (session.state.status) {
    PlaybackStatus.opening || PlaybackStatus.buffering || PlaybackStatus.playing => true,
    _ => false,
  };

  Future<void> _pauseForFocus({required bool resume}) async {
    _resumeWhenBack = false;
    if (!_sounding) return;
    _pausingToResume = resume;
    try {
      await session.pause();
    } finally {
      _pausingToResume = false;
    }
    _pausedByFocus = resume && session.state.status == PlaybackStatus.paused;
  }

  Future<void> _interruptionEnded() async {
    if (!_pausedByFocus) return;
    _pausedByFocus = false;
    if (session.state.status != PlaybackStatus.paused) return;
    if (mayPlayNow?.call() ?? true) {
      await session.resume();
    } else {
      _resumeWhenBack = true;
    }
  }

  Future<void> _duck() async {
    if (_duckedVolume != null) return;
    final before = session.state.volume;
    final lowered = before * duckFactor;
    _volumeBeforeDuck = before;
    _duckedVolume = lowered;
    await session.setVolume(lowered);
  }

  Future<void> _unduck() async {
    final before = _volumeBeforeDuck;
    final lowered = _duckedVolume;
    _volumeBeforeDuck = null;
    _duckedVolume = null;
    if (before == null || lowered == null) return;
    // A volume the user chose meanwhile stays.
    if ((session.state.volume - lowered).abs() < 1e-6) await session.setVolume(before);
  }

  Future<void> _onNoisy() async {
    _pausedByFocus = false;
    _resumeWhenBack = false;
    if (_sounding) await session.pause();
  }

  Future<void> _activate({required bool active}) async {
    try {
      final granted = await port.activate(active: active);
      if (active && !granted) developer.log('Audio focus was not granted', name: 'audio_focus');
    } on Object catch (error, stack) {
      // Playback goes on without the focus (3.x logged it only).
      developer.log('Audio focus failed: $error', name: 'audio_focus', stackTrace: stack);
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } on Object catch (error, stack) {
        developer.log('Audio focus event failed: $error', name: 'audio_focus', stackTrace: stack);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onAppResumed();
  }

  /// The app is back on screen: resume what an interruption left paused.
  @visibleForTesting
  void onAppResumed() {
    if (!_resumeWhenBack) return;
    _enqueue(() async {
      if (!_resumeWhenBack) return;
      _resumeWhenBack = false;
      if (session.state.status == PlaybackStatus.paused) await session.resume();
    });
  }

  /// Stops following and gives the focus back.
  Future<void> dispose() async {
    if (_disposed) return;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _queue;
    _disposed = true;
    if (_active) {
      _active = false;
      await _activate(active: false);
    }
  }
}
