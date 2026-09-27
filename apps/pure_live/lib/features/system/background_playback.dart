import 'dart:async';
import 'dart:ui';

import 'package:live_media/live_media.dart';

/// What playback does when the app leaves the screen (spec/modules/playback.md
/// INT-3, PERF-2, PIP-5; F-BG-01).
///
/// The decision waits [delay] after the app becomes hidden, so the short
/// hidden phases of a rotation, a picture-in-picture entry or a Surface swap
/// change nothing. Then, while the user still wants to play:
/// - in picture-in-picture nothing changes (the video is on screen);
/// - with background play allowed, video output is turned off and audio
///   continues (unless the user already chose audio only);
/// - with the in-app mini window up, playback continues (PIP-5);
/// - otherwise the session is suspended with a [SuspendReason.background]
///   token.
///
/// Back in the foreground the pending decision is cancelled, video comes back
/// if it was turned off here, and the token resumes playback. A stale token
/// (another room, a user command in between) resumes nothing (INT-2).
final class BackgroundPlayback {
  /// Creates the policy.
  new({
    required this.allowBackground,
    required this.pipActive,
    required this.miniWindowShowing,
    this.delay = const Duration(milliseconds: 1500),
  });

  /// The "后台播放" setting.
  final bool Function() allowBackground;

  /// System or Windows picture-in-picture is showing the video.
  final bool Function() pipActive;

  /// The in-app mini window holds the playback.
  final bool Function() miniWindowShowing;

  /// How long the app must stay hidden before playback changes (INT-3).
  final Duration delay;

  PlaybackSession? _session;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Timer? _timer;
  SuspendToken? _token;
  var _videoOff = false;

  /// The app is not on screen.
  bool get hidden => _isHidden(_lifecycle);

  static bool _isHidden(AppLifecycleState state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached;

  /// Follows [session] (null when nothing plays). A pending suspension of the
  /// previous session is dropped: its token would be stale anyway.
  void attach(PlaybackSession? session) {
    if (identical(session, _session)) return;
    _session = session;
    _token = null;
    _videoOff = false;
    if (hidden && session != null) _schedule();
  }

  /// Reports an app lifecycle change.
  void lifecycleChanged(AppLifecycleState state) {
    final wasHidden = hidden;
    _lifecycle = state;
    if (hidden && !wasHidden) {
      _schedule();
    } else if (state == AppLifecycleState.resumed) {
      _foreground();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(delay, _apply);
  }

  void _apply() {
    _timer = null;
    final session = _session;
    if (!hidden || session == null) return;
    final state = session.state;
    if (!state.wantsPlay || _inactive.contains(state.phase)) return;
    if (pipActive()) return;
    if (allowBackground()) {
      if (!state.audioOnly) {
        _videoOff = true;
        unawaited(session.setAudioOnly(enabled: true).catchError((Object _) {}));
      }
      return;
    }
    if (miniWindowShowing()) return;
    _token = session.suspend(SuspendReason.background);
  }

  static const Set<PlaybackPhase> _inactive = {
    PlaybackPhase.idle,
    PlaybackPhase.paused,
    PlaybackPhase.error,
    PlaybackPhase.ended,
  };

  void _foreground() {
    _timer?.cancel();
    _timer = null;
    final session = _session;
    if (session == null) return;
    if (_videoOff) {
      _videoOff = false;
      // The session keeps the audio presentation until a picture arrives (AUD-2).
      unawaited(session.setAudioOnly(enabled: false).catchError((Object _) {}));
    }
    final token = _token;
    _token = null;
    if (token != null) session.resume(token);
  }

  /// Stops the pending decision.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _session = null;
  }
}

/// Whether the Wi-Fi lock should be held (PERF-2): the app is hidden and the
/// session is actually delivering audio or video.
bool wantsWifiLock({required bool hidden, required PlaybackState? state}) {
  if (!hidden || state == null || !state.wantsPlay) return false;
  return const {
    PlaybackPhase.resolving,
    PlaybackPhase.connecting,
    PlaybackPhase.playing,
    PlaybackPhase.stalled,
    PlaybackPhase.recovering,
  }.contains(state.phase);
}
