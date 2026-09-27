import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/now_playing.dart';

/// The in-app mini window (F-PIP-03, spec/modules/playback.md PIP-4).
@immutable
final class MiniPlayerState {
  /// Creates a state.
  const new({required this.playing, this.surfaceReady = false});

  /// The adopted playback.
  final NowPlaying playing;

  /// The room page's video surface is gone, so the mini window may mount its
  /// own: a session has one surface (SURF-5).
  final bool surfaceReady;
}

/// A playback taken back from the mini window (SES-9).
@immutable
final class ReclaimedPlayback {
  /// Creates the hand-back.
  const new(this.playing, this.surfaceReleased);

  /// The playback: same session, commit, quality, line and audio mode.
  final NowPlaying playing;

  /// Completes once the mini window no longer shows the video; mount the
  /// room's `LiveVideoView` after it (SURF-5).
  final Future<void> surfaceReleased;
}

/// Runs a callback after the current frame; state changes from `initState`,
/// `build` or `dispose` must wait for it.
typedef FrameScheduler = void Function(VoidCallback callback);

/// After the current frame, with a frame scheduled.
final frameSchedulerProvider = Provider<FrameScheduler>(
  (ref) => (callback) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => callback())
      ..scheduleFrame();
  },
);

/// Owns the playback of the mini window.
///
/// Hand-off with the room page (the room page owns its session until then):
/// - Leaving a room: call [adopt] from the page's `State.dispose` (capture the
///   notifier in `initState`; `ref` is unusable in `dispose`). When it
///   returns true the mini window owns the session: the page must not close,
///   dispose or detach it. When false the page closes it as usual.
/// - Entering a room: call [reclaim] in `initState`. It returns the playback
///   for the same room (reuse its session, SES-9), or closes the mini window
///   for another room and returns null.
/// - The session provider must not dispose a session the mini window [owns].
class MiniPlayerController extends Notifier<MiniPlayerState?> {
  NowPlaying? _owned;

  @override
  MiniPlayerState? build() => null;

  /// Whether a room in [state] may shrink to the mini window: it shows a
  /// picture and has no error (PIP-4; otherwise a black window would stay).
  static bool canAdopt(PlaybackState state) =>
      state.hasPicture &&
      !state.audioOnly &&
      state.failure == null &&
      !const {PlaybackPhase.idle, PlaybackPhase.error, PlaybackPhase.ended}.contains(state.phase);

  /// Whether the mini window holds a playback.
  bool get holding => _owned != null;

  /// Whether the mini window owns [session].
  bool owns(PlaybackSession session) => identical(_owned?.session, session);

  /// Takes over [playing] when the room page goes away, if the setting is on
  /// and [canAdopt] holds. The surface mounts after [pageGone] (default: the
  /// page is already unmounted, as in `State.dispose`) and one more frame.
  bool adopt(NowPlaying playing, {Future<void>? pageGone}) {
    if (!ref.read(storeProvider).settings.get(Settings.miniPlayerOnLeave)) return false;
    if (!canAdopt(playing.session.state)) return false;
    final previous = _owned;
    if (previous != null && !identical(previous.session, playing.session)) unawaited(_release(previous));
    _owned = playing;
    final schedule = ref.read(frameSchedulerProvider);
    void mount() => schedule(() {
      if (ref.mounted && identical(_owned, playing)) state = MiniPlayerState(playing: playing, surfaceReady: true);
    });
    schedule(() {
      if (!ref.mounted || !identical(_owned, playing)) return;
      state = MiniPlayerState(playing: playing);
      if (pageGone == null) {
        mount();
      } else {
        unawaited(
          pageGone
              .timeout(const Duration(seconds: 2), onTimeout: () {})
              .then((_) => mount(), onError: (Object _) => mount()),
        );
      }
    });
    return true;
  }

  /// Hands the playback of [room] back to its room page, or closes the mini
  /// window when it plays another room.
  ReclaimedPlayback? reclaim(RoomRef room) {
    final owned = _owned;
    if (owned == null) return null;
    if (owned.room != room) {
      unawaited(close());
      return null;
    }
    _owned = null;
    final released = Completer<void>();
    final schedule = ref.read(frameSchedulerProvider);
    schedule(() {
      if (ref.mounted) state = null;
      schedule(released.complete);
    });
    return ReclaimedPlayback(owned, released.future);
  }

  /// Goes back to the room: hides the video first so the room page can take
  /// the surface, then opens the room, which [reclaim]s the playback.
  void openRoom() {
    final owned = _owned;
    if (owned == null) return;
    state = MiniPlayerState(playing: owned);
    ref.read(frameSchedulerProvider)(() {
      if (ref.mounted && identical(_owned, owned)) unawaited(ref.read(routerProvider).push(roomLocation(owned.room)));
    });
  }

  /// Closes the mini window and its playback.
  Future<void> close() async {
    final owned = _owned;
    if (owned == null) return;
    _owned = null;
    await _release(owned);
  }

  /// Unmounts the surface, stops following the playback and releases the
  /// session a frame later (PIP-6: the view unmounts before the engine goes).
  Future<void> _release(NowPlaying playing) {
    final done = Completer<void>();
    final schedule = ref.read(frameSchedulerProvider);
    final nowPlaying = ref.read(nowPlayingProvider.notifier);
    schedule(() {
      if (ref.mounted && identical(state?.playing, playing)) state = null;
      nowPlaying.detach(playing.session);
      schedule(() => unawaited(_dispose(playing.session).whenComplete(done.complete)));
    });
    return done.future;
  }

  static Future<void> _dispose(PlaybackSession session) async {
    try {
      await session.close();
      await session.dispose();
    } on Object {
      // Already disposed.
    }
  }
}

/// The mini window's state and commands.
final miniPlayerProvider = NotifierProvider<MiniPlayerController, MiniPlayerState?>(MiniPlayerController.new);

/// Counts open popup routes (dialogs, bottom sheets, menus) on every
/// navigator it observes. The mini window sits above the navigators and its
/// drag layer swallows taps, so it goes offstage while any popup is open
/// (PIP-4, REG-PLAY-017).
final class PopupRouteTracker extends ChangeNotifier implements ValueListenable<int> {
  final _open = <Route<dynamic>>{};

  @override
  int get value => _open.length;

  void _add(Route<dynamic>? route) {
    if (route is PopupRoute && _open.add(route)) _changed();
  }

  void _remove(Route<dynamic>? route) {
    if (route != null && _open.remove(route)) _changed();
  }

  void _changed() {
    // Navigators report during their own build; listeners rebuild after it.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

/// Reports one navigator's popup routes to a [PopupRouteTracker]. A
/// navigator observer serves one navigator, so each navigator gets its own.
final class PopupRouteObserver extends NavigatorObserver {
  /// Reports to [_tracker].
  new(this._tracker);

  final PopupRouteTracker _tracker;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _tracker._add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _tracker._remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _tracker._remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _tracker
      .._remove(oldRoute)
      .._add(newRoute);
  }
}

/// The app-wide popup tracker; the router adds one of its observers to every
/// navigator.
final popupTrackerProvider = Provider<PopupRouteTracker>((ref) {
  final tracker = PopupRouteTracker();
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Whether the mini window is visible (PIP-4): it holds a playback whose
/// surface is ready, no popup is open and picture-in-picture does not show
/// the video-only layout. Otherwise it is offstage.
bool miniWindowVisible({required MiniPlayerState? mini, required int openPopups, required bool pipVideoOnly}) =>
    mini != null && mini.surfaceReady && openPopups == 0 && !pipVideoOnly;
