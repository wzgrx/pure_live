import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/features/system/now_playing.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Lays out a room normally, or only its video while picture-in-picture is
/// entering or active (PIP-2). The room page wraps its layout with it and
/// passes its single video widget (with its `GlobalKey`), which moves between
/// the two layouts (SURF-5).
class PipAwareLayout extends ConsumerWidget {
  /// Creates the layout.
  const new({required this.session, required this.video, required this.builder, super.key});

  /// The room's session.
  final PlaybackSession session;

  /// The room's video widget.
  final Widget video;

  /// The normal layout around [video].
  final Widget Function(BuildContext context, Widget video) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoOnly = ref.watch(pipProvider.select((pip) => pip.videoOnly));
    return videoOnly ? PipVideoFrame(session: session, child: video) : builder(context, video);
  }
}

/// The video in picture-in-picture: black letterbox. On Windows the frameless
/// window moves by dragging the video, a double click leaves (PIP-3) and
/// hovering shows play/pause and "退出画中画". Android draws its own controls.
class PipVideoFrame extends ConsumerStatefulWidget {
  /// Creates the frame.
  const new({required this.session, required this.child, super.key});

  /// The room's session.
  final PlaybackSession session;

  /// The video.
  final Widget child;

  @override
  ConsumerState<PipVideoFrame> createState() => _PipVideoFrameState();
}

class _PipVideoFrameState extends ConsumerState<PipVideoFrame> {
  var _hover = false;
  StreamSubscription<PlaybackState>? _states;

  @override
  void initState() {
    super.initState();
    _states = widget.session.states.listen((_) {
      if (mounted && _hover) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  Future<void> _exit() async {
    final restored = await ref.read(pipProvider.notifier).exit();
    if (!restored && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.system.restoreWindowFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = ColoredBox(color: Colors.black, child: widget.child);
    if (!Platform.isWindows) return video;
    final paused = !widget.session.state.wantsPlay;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => unawaited(ref.read(desktopWindowProvider).startDragging()),
        onDoubleTap: () => unawaited(_exit()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            video,
            if (_hover)
              ColoredBox(
                color: const Color(0x55000000),
                child: Stack(
                  children: [
                    Center(
                      child: IconButton(
                        tooltip: paused ? t.common.play : t.common.pause,
                        color: Colors.white,
                        iconSize: 36,
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                        onPressed: () => runSessionCommand(paused ? widget.session.play : widget.session.pause),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        tooltip: t.system.exitPip,
                        color: Colors.white,
                        icon: const Icon(Icons.close_fullscreen),
                        onPressed: () => unawaited(_exit()),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
