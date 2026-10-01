import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_player/src/mpv_engine.dart';
import 'package:live_player/src/session.dart';
import 'package:live_player/src/state.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The video of a [PlaybackSession] (3.x's `getVideoWidget`): black until
/// the session has an mpv engine, then media_kit's `Video` with [fit] and
/// no controls. Background pause and resume stay with the app's lifecycle
/// policy, not with the widget (3.x).
///
/// [outputSize] (3.x: Windows) makes the native output follow the displayed
/// size, debounced 180 ms, so a small window does not render 4K frames.
class LiveVideoView extends StatefulWidget {
  /// Creates the view.
  const new({
    required this.session,
    this.fit = BoxFit.contain,
    this.outputSize = false,
    this.fill = const Color(0xFF000000),
    super.key,
  });

  /// The session to show.
  final PlaybackSession session;

  /// How the video fills the box (3.x's `videoFitIndex`).
  final BoxFit fit;

  /// Size the native output to the displayed size.
  final bool outputSize;

  /// What fills the box around the video: black, or transparent over a
  /// backdrop (a portrait stream's ambient background).
  final Color fill;

  @override
  State<LiveVideoView> createState() => _LiveVideoViewState();
}

class _LiveVideoViewState extends State<LiveVideoView> {
  StreamSubscription<PlaybackState>? _subscription;
  Timer? _resize;
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(LiveVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  void _listen() {
    // Rebuild only when the engine appears or goes away.
    var engine = widget.session.engine;
    _subscription = widget.session.states.listen((_) {
      final next = widget.session.engine;
      if (!identical(next, engine) && mounted) {
        engine = next;
        _lastSize = null;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _resize?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _scheduleResize(VideoController controller, Size size, double ratio) {
    if (size == _lastSize || size.isEmpty) return;
    final force = _lastSize == null;
    _lastSize = size;
    _resize?.cancel();
    _resize = Timer(const Duration(milliseconds: 180), () {
      unawaited(
        controller.setSize(width: (size.width * ratio).round(), height: (size.height * ratio).round(), force: force),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.session.engine;
    if (engine is! MpvEngine) return ColoredBox(color: widget.fill, child: const SizedBox.expand());
    final video = Video(
      controller: engine.controller,
      controls: null,
      fit: widget.fit,
      fill: widget.fill,
      pauseUponEnteringBackgroundMode: false,
    );
    if (!widget.outputSize) return video;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleResize(engine.controller, constraints.biggest, ratio);
        return video;
      },
    );
  }
}
