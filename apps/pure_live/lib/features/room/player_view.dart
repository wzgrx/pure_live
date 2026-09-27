import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart' as player;
import 'package:live_store/live_store.dart' as store;
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/room/playback.dart';

/// What the user reads when playback fails, by failure kind (principles rule 3:
/// say what happened in place and offer the next step).
String failureText(PlaybackFailure failure) => switch (failure.kind) {
  FailureKind.network => '网络中断了',
  FailureKind.source => '直播流打不开，可以换条线路试试',
  FailureKind.bufferingStall => '缓冲太久了，可以换条线路或降低画质',
  FailureKind.liveCompleted => '直播流中断了',
  FailureKind.unexpectedPause => '播放意外停止了',
  FailureKind.frameStall => '画面卡住了',
  FailureKind.videoDecode => '视频解码失败，可以在设置里关闭硬件解码',
  FailureKind.audioDecode => '音频解码失败',
  FailureKind.engine => '播放器出错了',
  FailureKind.unavailable => '拿不到直播流',
  FailureKind.exhausted => '多次重试都没有成功',
};

/// The room's video with its controls: tap toggles the controls (they hide
/// after 3 s while playing), double tap toggles fullscreen, quality and line
/// menus, refresh, and failures shown in place with retry.
class PlayerView extends ConsumerStatefulWidget {
  const new({required this.detail, required this.fullscreen, required this.onFullscreen, super.key});

  final RoomDetail detail;

  /// Whether the page shows the video fullscreen.
  final bool fullscreen;

  /// Enters or leaves fullscreen.
  final ValueChanged<bool> onFullscreen;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  final GlobalKey _videoKey = GlobalKey();
  late final PlaybackSession _session;
  StreamSubscription<PlaybackState>? _subscription;
  PlaybackState _state = const PlaybackState();
  Object? _openError;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _session = ref.read(playbackSessionProvider);
    _state = _session.state;
    _subscription = _session.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state.phase == PlaybackPhase.playing) _scheduleHide();
    });
    if (widget.detail.state == LiveState.live) unawaited(_open());
  }

  Future<void> _open() async {
    setState(() => _openError = null);
    try {
      await openRoom(
        site: ref.read(sitesProvider)[widget.detail.ref.platform]!,
        settings: ref.read(storeProvider).settings,
        session: _session,
        detail: widget.detail,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _openError = error);
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _state.phase == PlaybackPhase.playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _chooseQuality() async {
    final chosen = await _choose<Quality>('画质', [for (final q in _state.qualities) (q, q.label, q == _state.quality)]);
    if (chosen != null && chosen != _state.quality) await _session.selectQuality(chosen);
  }

  Future<void> _chooseLine() async {
    final lines = _state.lines;
    final chosen = await _choose<String>('线路', [
      for (final (i, line) in lines.indexed) (line.lineId, '线路 ${i + 1}', line.lineId == _state.line?.lineId),
    ]);
    if (chosen != null && chosen != _state.line?.lineId) await _session.selectLine(chosen);
  }

  Future<T?> _choose<T>(String title, List<(T, String, bool)> options) => showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          for (final (value, label, selected) in options)
            ListTile(
              title: Text(label),
              trailing: selected ? const Icon(Icons.check) : null,
              selected: selected,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fitSetting = ref.watch(videoFitSetting);
    final fit = switch (fitSetting) {
      store.VideoFit.cover => player.VideoFit.cover,
      store.VideoFit.fill => player.VideoFit.fill,
      _ => player.VideoFit.contain,
    };
    final live = widget.detail.state == LiveState.live;
    final keepOn = ref.watch(screenKeepOnSetting);
    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTap: () => widget.onFullscreen(!widget.fullscreen),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (live)
              player.LiveVideoView(key: _videoKey, session: _session, fit: fit, wakelock: keepOn)
            else
              _OfflineCover(detail: widget.detail),
            if (live && _state.showsBuffering && _openError == null)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_openError != null || _state.failure != null) _failureOverlay(),
            if (_state.showsPaused && _openError == null)
              Center(
                child: IconButton.filled(iconSize: 40, onPressed: _session.play, icon: const Icon(Icons.play_arrow)),
              ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: Motion.medium,
              child: IgnorePointer(ignoring: !_controls, child: _controlsLayer(live)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failureOverlay() {
    final String title;
    final String message;
    if (_openError != null) {
      final text = describeError(_openError!);
      title = text.title;
      message = text.message;
    } else {
      title = failureText(_state.failure!);
      message = _state.lines.length > 1 ? '当前线路出错，可以重试或换线路' : '可以稍后重试';
    }
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.s1),
              Text(
                message,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.s3),
              Wrap(
                spacing: Space.s2,
                children: [
                  FilledButton(onPressed: _openError != null ? _open : _session.retry, child: const Text('重试')),
                  if (_state.lines.length > 1)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: _chooseLine,
                      child: const Text('换线路'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer(bool live) {
    const ink = Colors.white;
    final card = widget.detail.card;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0x99000000)],
          stops: [0, 0.3, 0.7, 1],
        ),
      ),
      child: SafeArea(
        top: widget.fullscreen,
        bottom: widget.fullscreen,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  color: ink,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => widget.fullscreen ? widget.onFullscreen(false) : context.pop(),
                ),
                Expanded(
                  child: Text(
                    widget.fullscreen ? '${card.anchorName} · ${card.title}' : card.anchorName,
                    style: const TextStyle(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (live)
              Row(
                children: [
                  IconButton(tooltip: '刷新', color: ink, icon: const Icon(Icons.refresh), onPressed: _session.retry),
                  if (_state.phase == PlaybackPhase.playing)
                    IconButton(tooltip: '暂停', color: ink, icon: const Icon(Icons.pause), onPressed: _session.pause),
                  const Spacer(),
                  if (_state.qualities.length > 1)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: ink),
                      onPressed: _chooseQuality,
                      child: Text(_state.quality?.label ?? '画质'),
                    ),
                  if (_state.lines.length > 1)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: ink),
                      onPressed: _chooseLine,
                      child: const Text('线路'),
                    ),
                  IconButton(
                    tooltip: widget.fullscreen ? '退出全屏' : '全屏',
                    color: ink,
                    icon: Icon(widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: () => widget.onFullscreen(!widget.fullscreen),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OfflineCover extends StatelessWidget {
  const new({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    final cover = networkImage(
      detail.card.cover,
      logicalWidth: MediaQuery.sizeOf(context).width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          Opacity(
            opacity: 0.35,
            child: Image(image: cover, fit: BoxFit.cover),
          ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off_outlined, color: Colors.white, size: 48),
              const SizedBox(height: Space.s2),
              Text(detail.state == LiveState.replay ? '回放中' : '未开播', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Immersive, landscape fullscreen on phones; the system bars come back on exit.
Future<void> applyFullscreen({required bool on, required bool portraitVideo}) async {
  if (on) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!portraitVideo) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }
}
