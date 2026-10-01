import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

/// The danmaku of the mini windows (3.x `CompactDanmakuOverlay`, U.2j-e):
/// the "小窗弹幕" settings (size with automatic scaling, at least 10 since
/// c7; weight, speed, opacity, area, how many at once, the gap between two,
/// the frame rate, one colour or the platform's, text only), the main
/// danmaku's outline. Nothing when "小窗显示弹幕" is off or the room hides its
/// danmaku. Its own layer: it never repaints the picture.
class CompactDanmakuLayer extends ConsumerStatefulWidget {
  /// Creates the layer for [controller]'s messages.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  ConsumerState<CompactDanmakuLayer> createState() => _CompactDanmakuLayerState();
}

class _CompactDanmakuLayerState extends ConsumerState<CompactDanmakuLayer> {
  final StreamController<LiveMessage> _out = StreamController.broadcast(sync: true);
  final Queue<(LiveMessage, DateTime)> _pending = Queue();
  StreamSubscription<LiveMessage>? _in;
  Timer? _next;
  DateTime? _last;
  Duration _gap = const Duration(milliseconds: 350);
  bool _textOnly = false;

  /// 3.x's waiting line: at most 36 messages, none older than 3 s.
  static const int _maxPending = 36;
  static const Duration _maxAge = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _in = widget.controller.flying.listen(_take);
  }

  @override
  void didUpdateWidget(CompactDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    unawaited(_in?.cancel());
    _pending.clear();
    _in = widget.controller.flying.listen(_take);
  }

  @override
  void dispose() {
    _next?.cancel();
    unawaited(_in?.cancel());
    unawaited(_out.close());
    super.dispose();
  }

  void _take(LiveMessage message) {
    var text = message.message;
    if (_textOnly) text = withoutEmoteCodes(text, [for (final emote in message.emotes) emote.code]);
    if (text.trim().isEmpty) return;
    final kept = text == message.message
        ? message
        : LiveMessage(
            type: message.type,
            userName: message.userName,
            userId: message.userId,
            message: text,
            color: message.color,
            messageId: message.messageId,
            isLocal: message.isLocal,
          );
    final now = DateTime.now();
    if (_pending.isEmpty && (_last == null || now.difference(_last!) >= _gap)) {
      _emit(kept, now);
      return;
    }
    _pending.addLast((kept, now));
    while (_pending.length > _maxPending) {
      _pending.removeFirst();
    }
    _schedule();
  }

  void _emit(LiveMessage message, DateTime now) {
    _last = now;
    if (!_out.isClosed) _out.add(message);
  }

  void _schedule() {
    if (_next?.isActive ?? false) return;
    final last = _last ?? DateTime.now();
    final wait = _gap - DateTime.now().difference(last);
    _next = Timer(wait.isNegative ? Duration.zero : wait, () {
      final now = DateTime.now();
      while (_pending.isNotEmpty && now.difference(_pending.first.$2) > _maxAge) {
        _pending.removeFirst();
      }
      if (_pending.isEmpty || !mounted) return;
      _emit(_pending.removeFirst().$1, now);
      if (_pending.isNotEmpty) _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown =
        watchSetting(ref, Settings.enablePipDanmaku) &&
        watchSetting(ref, Settings.enableDanmakuDisplay) &&
        !watchSetting(ref, Settings.hideDanmaku);
    final autoScale = watchSetting(ref, Settings.pipDanmakuAutoScale);
    final fontSize = watchSetting(ref, Settings.pipDanmakuFontSize);
    final speed = watchSetting(ref, Settings.pipDanmakuSpeed);
    final weight = watchSetting(ref, Settings.pipDanmakuFontWeight);
    final opacity = watchSetting(ref, Settings.pipDanmakuOpacity);
    final area = watchSetting(ref, Settings.pipDanmakuArea);
    final maxVisible = watchSetting(ref, Settings.pipDanmakuMaxVisibleCount);
    final original = watchSetting(ref, Settings.pipDanmakuUseOriginalColor);
    final color = watchSetting(ref, Settings.pipDanmakuColor);
    final stroke = watchSetting(ref, Settings.enableDanmakuStroke);
    final strokeWidth = watchSetting(ref, Settings.danmakuFontBorder);
    final autoFps = watchSetting(ref, Settings.pipDanmakuAutoFps);
    final fps = watchSetting(ref, Settings.pipDanmakuFps);
    final refreshMode = watchSetting(ref, Settings.refreshRateMode);
    _textOnly = watchSetting(ref, Settings.pipDanmakuNoEmojiMode);
    final interval = watchSetting(ref, Settings.pipDanmakuEmitInterval);
    _gap = Duration(milliseconds: (interval.clamp(0, 5) * 1000).round());
    return ValueListenableBuilder(
      valueListenable: DisplayMode.info,
      builder: (context, display, _) => LayoutBuilder(
        builder: (context, constraints) {
          final metrics = CompactDanmakuMetrics.resolve(
            width: constraints.maxWidth,
            autoScale: autoScale,
            fontSize: fontSize,
            speed: speed,
          );
          return RepaintBoundary(
            key: const ValueKey('mini-danmaku'),
            child: DanmakuOverlay(
              messages: _out.stream,
              retractions: widget.controller.retractions,
              visible: shown,
              maxVisible: maxVisible,
              color: original ? null : Color(color),
              fps: compactDanmakuFps(
                automatic: autoFps,
                configured: fps,
                mode: refreshMode,
                maxRefreshRate: display?.maxRefreshRate,
                currentRefreshRate: display?.currentRefreshRate,
              ),
              look: DanmakuLook(
                fontSize: metrics.fontSize,
                fontWeight: weight.clamp(100, 900),
                speed: metrics.speed,
                opacity: opacity,
                area: area,
                stroke: stroke && strokeWidth > 0,
                strokeWidth: strokeWidth.clamp(0, 4).toDouble(),
                laneHeight: metrics.laneHeight,
              ),
            ),
          );
        },
      ),
    );
  }
}
