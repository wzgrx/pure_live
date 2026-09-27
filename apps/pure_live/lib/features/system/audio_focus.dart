import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/system/now_playing.dart';

/// An audio focus or output event from the platform.
enum FocusEvent {
  /// Another app took the focus for a while (a call, a voice message).
  lostTransient,

  /// Another app took the focus for good.
  lost,

  /// The focus came back after [lostTransient].
  regained,

  /// Headphones were unplugged.
  becameNoisy,
}

/// The platform side of audio focus.
abstract interface class AudioFocusPort {
  /// Asks for the focus; false when it was refused.
  Future<bool> activate();

  /// Gives the focus back.
  Future<void> deactivate();

  /// Focus and output events.
  Stream<FocusEvent> get events;
}

/// Pauses for other apps' audio (spec/modules/playback.md INT-4, F-BG-01).
///
/// The focus is held while the user wants to play. A transient loss suspends
/// with a [SuspendReason.audioFocus] token and the regained focus resumes it;
/// any user command in between makes the token stale (INT-2). A permanent loss
/// and unplugged headphones pause like the user did, since no "regained"
/// follows them.
final class AudioFocusCoordinator {
  /// Creates the coordinator and listens to [port].
  new(this.port) {
    _events = port.events.listen(_onEvent);
  }

  /// The platform.
  final AudioFocusPort port;

  late final StreamSubscription<FocusEvent> _events;
  StreamSubscription<PlaybackState>? _states;
  PlaybackSession? _session;
  SuspendToken? _token;
  var _active = false;

  /// Follows [session] (null when nothing plays).
  void attach(PlaybackSession? session) {
    if (identical(session, _session)) return;
    unawaited(_states?.cancel());
    _states = null;
    _session = session;
    _token = null;
    if (session == null) {
      _setActive(false);
      return;
    }
    _states = session.states.listen(_onState);
    _onState(session.state);
  }

  void _onState(PlaybackState state) {
    final wants = state.wantsPlay && state.phase != PlaybackPhase.idle;
    if (!wants) _token = null;
    _setActive(wants);
  }

  void _setActive(bool active) {
    if (active == _active) return;
    _active = active;
    unawaited((active ? port.activate() : port.deactivate()).catchError((Object _) => false));
  }

  void _onEvent(FocusEvent event) {
    final session = _session;
    if (session == null) return;
    switch (event) {
      case FocusEvent.lostTransient:
        if (session.state.wantsPlay) _token = session.suspend(SuspendReason.audioFocus);
      case FocusEvent.regained:
        final token = _token;
        _token = null;
        if (token != null) session.resume(token);
      case FocusEvent.lost:
      case FocusEvent.becameNoisy:
        _token = null;
        if (session.state.wantsPlay) runSessionCommand(session.pause);
    }
  }

  /// Stops listening and gives the focus back.
  Future<void> dispose() async {
    await _states?.cancel();
    await _events.cancel();
    _session = null;
    if (_active) await port.deactivate().catchError((Object _) {});
    _active = false;
  }
}

/// [AudioFocusPort] over audio_session: Android audio focus with automatic
/// ducking, and the becoming-noisy broadcast.
final class AudioSessionFocusPort implements AudioFocusPort {
  /// Creates the port; the audio session is configured on first use.
  new();

  static const _configuration = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.movie,
      usage: AndroidAudioUsage.media,
    ),
    // Android 8+ lowers the volume by itself for short sounds.
    androidWillPauseWhenDucked: false,
  );

  Future<AudioSession>? _session;
  StreamController<FocusEvent>? _controller;

  Future<AudioSession> _ready() => _session ??= () async {
    final session = await AudioSession.instance;
    await session.configure(_configuration);
    return session;
  }();

  @override
  Future<bool> activate() async => await (await _ready()).setActive(true);

  @override
  Future<void> deactivate() async => await (await _ready()).setActive(false);

  @override
  Stream<FocusEvent> get events => (_controller ??= _createEvents()).stream;

  StreamController<FocusEvent> _createEvents() {
    final subscriptions = <StreamSubscription<Object?>>[];
    late final StreamController<FocusEvent> controller;
    return controller = StreamController<FocusEvent>.broadcast(
      onListen: () async {
        final session = await _ready();
        subscriptions
          ..add(
            session.interruptionEventStream.listen((event) {
              final mapped = focusEventOf(event);
              if (mapped != null) controller.add(mapped);
            }),
          )
          ..add(session.becomingNoisyEventStream.listen((_) => controller.add(FocusEvent.becameNoisy)));
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );
  }
}

/// Maps an audio_session interruption to a [FocusEvent]; ducking is left to
/// the system.
FocusEvent? focusEventOf(AudioInterruptionEvent event) => switch ((event.begin, event.type)) {
  (true, AudioInterruptionType.pause) => FocusEvent.lostTransient,
  (true, AudioInterruptionType.unknown) => FocusEvent.lost,
  (false, AudioInterruptionType.pause) => FocusEvent.regained,
  _ => null,
};
