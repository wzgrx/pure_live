import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/platform/display_mode.dart';

/// Tells the display what the room plays (docs/ui/compare/U.2i c2-c4): the
/// video's frame rate while it plays or buffers with "播放时匹配视频帧率" on
/// and the app in front or in picture-in-picture (Flutter reports that as
/// inactive); nothing while paused, in the background, with the switch off
/// or once the room is left. Only sends when the answer changes.
final class RoomRefreshRate {
  /// Watches the session and the settings; [apply] reaches the display
  /// ([DisplayMode.setPlayback] by default).
  new({required this._session, required this._settings, Future<void> Function(PlaybackRefresh? playback)? apply})
    : _apply = apply ?? DisplayMode.setPlayback;

  final PlaybackSession _session;
  final SettingsStore _settings;
  final Future<void> Function(PlaybackRefresh? playback) _apply;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  AppLifecycleListener? _lifecycle;
  AppLifecycleState? _state = WidgetsBinding.instance.lifecycleState;
  PlaybackRefresh? _sent;
  bool _started = false;

  /// What goes to the display now.
  PlaybackRefresh? get current => _sent;

  /// Starts watching.
  void start() {
    _subscriptions
      ..add(_session.states.listen((_) => _update()))
      ..add(
        _settings.changes
            .where((setting) => setting == Settings.matchVideoFrameRate || setting == Settings.refreshRateMode)
            .listen((_) => _update()),
      );
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _state = state;
        _update();
      },
    );
    _update();
  }

  void _update() {
    final playback = _session.state;
    final fps = playback.frameRate;
    final front = switch (_state) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      _ => false,
    };
    final playing = playback.status == PlaybackStatus.playing || playback.status == PlaybackStatus.buffering;
    final next = _settings.get(Settings.matchVideoFrameRate) && front && playing && !playback.audioOnly && fps != null
        ? PlaybackRefresh(frameRate: normalizeFrameRate(fps), mode: _settings.get(Settings.refreshRateMode))
        : null;
    if (_started && next == _sent) return;
    _started = true;
    _sent = next;
    unawaited(_apply(next));
  }

  /// The room is left: the declaration goes.
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _lifecycle?.dispose();
    _lifecycle = null;
    if (_sent != null) unawaited(_apply(null));
    _sent = null;
  }
}
