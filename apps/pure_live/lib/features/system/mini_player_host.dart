import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart' show OnVideoTextScale;
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/mini_player.dart';
import 'package:pure_live_app/features/system/now_playing.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Longest edge of the mini window (PIP-4): 350 on desktops, 220 elsewhere.
double miniWindowLongEdge({required bool desktop}) => desktop ? 350 : 220;

/// The mini window's size for a video of [aspect].
Size miniWindowSize({required double aspect, required bool desktop}) {
  final edge = miniWindowLongEdge(desktop: desktop);
  final safe = aspect.isFinite && aspect > 0 ? aspect.clamp(0.4, 2.5) : 16 / 9;
  return safe >= 1 ? Size(edge, edge / safe) : Size(edge * safe, edge);
}

/// Keeps a window of [size] at [position] inside [area].
Offset clampMiniWindow(Offset position, Size size, Rect area) => Offset(
  position.dx.clamp(area.left, math.max(area.left, area.right - size.width)),
  position.dy.clamp(area.top, math.max(area.top, area.bottom - size.height)),
);

/// Puts the mini window above the app's pages (F-PIP-03). Wrap the router's
/// child in `MaterialApp.builder` with it; [child] keeps its place in the tree
/// whether or not the window shows.
class MiniPlayerHost extends ConsumerWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The app's navigator.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mini = ref.watch(miniPlayerProvider);
    final pipVideoOnly = ref.watch(pipProvider.select((pip) => pip.videoOnly));
    final popups = ref.watch(popupTrackerProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (mini != null)
          ValueListenableBuilder<int>(
            valueListenable: popups,
            builder: (context, open, _) => _MiniWindow(
              key: ObjectKey(mini.playing.session),
              playing: mini.playing,
              surfaceReady: mini.surfaceReady,
              visible: miniWindowVisible(mini: mini, openPopups: open, pipVideoOnly: pipVideoOnly),
            ),
          ),
      ],
    );
  }
}

class _MiniWindow extends ConsumerStatefulWidget {
  const new({required this.playing, required this.surfaceReady, required this.visible, super.key});

  final NowPlaying playing;
  final bool surfaceReady;
  final bool visible;

  @override
  ConsumerState<_MiniWindow> createState() => _MiniWindowState();
}

class _MiniWindowState extends ConsumerState<_MiniWindow> {
  final GlobalKey _videoKey = GlobalKey();
  StreamSubscription<PlaybackState>? _states;
  late PlaybackState _state;
  Offset? _position;
  var _controls = false;
  Timer? _hide;

  PlaybackSession get _session => widget.playing.session;

  @override
  void initState() {
    super.initState();
    _state = _session.state;
    _states = _session.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    unawaited(_states?.cancel());
    super.dispose();
  }

  void _showControls() {
    setState(() => _controls = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  /// Phones: the first tap shows the controls, the next one returns to the
  /// room (PIP-4). Desktops show the controls on hover, so a click returns.
  void _onTap() {
    if (!isDesktop && !_controls) {
      _showControls();
      return;
    }
    ref.read(miniPlayerProvider.notifier).openRoom();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final area = (media.padding + const EdgeInsets.all(8)).deflateRect(Offset.zero & media.size);
    final size = miniWindowSize(aspect: pipAspect(_state), desktop: isDesktop);
    // Start in the bottom-right corner, above a bottom navigation bar.
    final start = Offset(area.right - size.width, area.bottom - size.height - 72);
    final position = clampMiniWindow(_position ?? start, size, area);
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: Offstage(
        offstage: !widget.visible,
        child: MouseRegion(
          onEnter: (_) => setState(() => _controls = true),
          onExit: (_) => setState(() => _controls = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onPanUpdate: (details) => setState(() => _position = clampMiniWindow(position + details.delta, size, area)),
            child: Material(
              color: Colors.black,
              elevation: 8,
              // Text over the picture grows at most 1.3× (principles §2.3).
              child: OnVideoTextScale(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.surfaceReady)
                      LiveVideoView(
                        key: _videoKey,
                        session: _session,
                        // Offstage under a popup counts as covered (SURF-1, SURF-4).
                        occluded: !widget.visible,
                        wakelock: ref.watch(screenKeepOnSetting),
                      ),
                    if (_state.showsBuffering)
                      const Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    if (_state.phase == PlaybackPhase.error)
                      Center(
                        child: Text(t.system.playbackError, style: const TextStyle(color: Colors.white)),
                      ),
                    if (_controls) _overlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay() {
    const ink = Colors.white;
    final paused = !_state.wantsPlay;
    // No tooltips: the window sits above the navigator, outside any Overlay.
    return ColoredBox(
      color: const Color(0x66000000),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Semantics(
              label: t.system.backToRoom,
              button: true,
              child: IconButton(
                color: ink,
                iconSize: 20,
                icon: const Icon(Icons.open_in_full),
                onPressed: () => ref.read(miniPlayerProvider.notifier).openRoom(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Semantics(
              label: t.system.closeMini,
              button: true,
              child: IconButton(
                color: ink,
                iconSize: 20,
                icon: const Icon(Icons.close),
                onPressed: () => unawaited(ref.read(miniPlayerProvider.notifier).close()),
              ),
            ),
          ),
          Center(
            child: Semantics(
              label: paused ? t.common.play : t.common.pause,
              button: true,
              child: IconButton(
                color: ink,
                iconSize: 32,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                onPressed: () {
                  runSessionCommand(paused ? _session.play : _session.pause);
                  if (!isDesktop) _showControls();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
