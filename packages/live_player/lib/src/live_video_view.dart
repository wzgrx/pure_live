import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/mpv_engine.dart';
import 'package:live_player/src/output_size.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The single video surface of a [PlaybackSession] (SURF-5).
///
/// Keep exactly one per session and move it between the embedded, theater,
/// fullscreen, PiP and mini-window layouts with a `GlobalKey`, so the native
/// surface is never rebuilt; a second view of the same session fails an
/// assertion in debug builds. Sharp corners: callers must not clip it round.
///
/// - [fit] maps to contain, cover or fill; the box is painted [background].
/// - [occluded]: an opaque page covers the video. On Windows the texture is
///   unmounted (playback and sound continue), the frame watchdog pauses, and
///   the next layout forces the output size (SURF-1, MON-3). Elsewhere the
///   surface stays mounted offstage (SURF-4).
/// - On desktop the native output follows the displayed size, debounced
///   180 ms (PERF-1). Android keeps the decoder size (spec §12 item 6).
class LiveVideoView extends StatefulWidget {
  /// Creates the view.
  const new({
    required this.session,
    this.fit = VideoFit.contain,
    this.occluded = false,
    this.background = const Color(0xFF000000),
    this.wakelock = true,
    super.key,
  });

  /// Session whose engine is shown.
  final PlaybackSession session;

  /// Fit mode.
  final VideoFit fit;

  /// Covered by an opaque page.
  final bool occluded;

  /// Letterbox and placeholder color.
  final Color background;

  /// Keep the screen on while the video plays.
  final bool wakelock;

  @override
  State<LiveVideoView> createState() => _LiveVideoViewState();
}

final Map<PlaybackSession, State<LiveVideoView>> _surfaces = {};

bool get _desktop =>
    !kIsWeb &&
    const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);

bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class _LiveVideoViewState extends State<LiveVideoView> {
  StreamSubscription<PlaybackState>? _states;
  late PlaybackState _state;
  var _forceSize = false;
  Timer? _resize;
  Size? _requested;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    assert(() {
      final other = _surfaces[widget.session];
      if (other != null && other != this && other.mounted) {
        throw FlutterError(
          'A PlaybackSession has one LiveVideoView (spec SURF-5); move it with a GlobalKey instead of '
          'building a second one.',
        );
      }
      return true;
    }(), 'single video surface');
    _surfaces[widget.session] = this;
    _state = widget.session.state;
    _states = widget.session.states.listen((next) {
      final changed =
          next.engineRevision != _state.engineRevision ||
          next.videoWidth != _state.videoWidth ||
          next.videoHeight != _state.videoHeight;
      _state = next;
      if (changed && mounted) setState(() {});
    });
    widget.session.setVisible(visible: !widget.occluded);
  }

  void _detach(PlaybackSession session) {
    unawaited(_states?.cancel());
    _states = null;
    if (identical(_surfaces[session], this)) _surfaces.remove(session);
  }

  @override
  void didUpdateWidget(LiveVideoView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _detach(old.session);
      _requested = null;
      _attach();
    } else if (old.occluded != widget.occluded) {
      widget.session.setVisible(visible: !widget.occluded);
      if (!widget.occluded && _windows) _forceSize = true;
    }
  }

  @override
  void dispose() {
    _resize?.cancel();
    _detach(widget.session);
    super.dispose();
  }

  BoxFit get _boxFit => switch (widget.fit) {
    VideoFit.contain => BoxFit.contain,
    VideoFit.cover => BoxFit.cover,
    VideoFit.fill => BoxFit.fill,
  };

  void _scheduleResize(VideoController controller, Size viewport, double pixelRatio) {
    final size = videoOutputSize(
      viewport: viewport,
      pixelRatio: pixelRatio,
      fit: widget.fit,
      sourceWidth: _state.videoWidth,
      sourceHeight: _state.videoHeight,
    );
    if (size.isEmpty || (size == _requested && !_forceSize)) return;
    final force = _forceSize;
    _forceSize = false;
    _requested = size;
    _resize?.cancel();
    _resize = Timer(force ? Duration.zero : const Duration(milliseconds: 180), () {
      unawaited(controller.setSize(width: size.width.toInt(), height: size.height.toInt(), force: force));
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.session.engine;
    Widget surface = const SizedBox.expand();
    if (engine is MpvEngine && !(widget.occluded && _windows)) {
      final video = Video(
        controller: engine.controller,
        // No media_kit controls: the room page draws its own.
        controls: null,
        fit: _boxFit,
        fill: widget.background,
        wakelock: widget.wakelock,
        // The app's lifecycle policy owns background pauses (INT-3).
        pauseUponEnteringBackgroundMode: false,
      );
      surface = _desktop
          ? LayoutBuilder(
              builder: (context, constraints) {
                _scheduleResize(engine.controller, constraints.biggest, MediaQuery.devicePixelRatioOf(context));
                return video;
              },
            )
          : video;
      if (widget.occluded) surface = Offstage(child: surface);
    }
    return ColoredBox(color: widget.background, child: surface);
  }
}

/// A [ValueListenable] of a session's state, for `ValueListenableBuilder`
/// and simple glue; Riverpod code can listen to [PlaybackSession.states]
/// directly.
final class PlaybackStateNotifier extends ValueNotifier<PlaybackState> {
  /// Follows [session] until [dispose].
  new(this.session) : super(session.state) {
    _subscription = session.states.listen((state) => value = state);
  }

  /// The session followed.
  final PlaybackSession session;
  late final StreamSubscription<PlaybackState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
