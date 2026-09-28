import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/features/room/gestures.dart';
import 'package:pure_live_app/features/room/presentation.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

export 'package:pure_live_app/features/room/presentation.dart' show RoomPresentation;

/// Narrowest and widest chat panel on large windows (principles §5.2).
const double minChatWidth = 280;

/// Widest chat panel.
const double maxChatWidth = 480;

/// Lays out the video, the info section and the chat panel for the window
/// size and presentation (live-room §2.3, principles §5.2). The [video] is
/// the page's single keyed surface: every branch places it exactly once, so
/// a layout change moves it instead of rebuilding it (PS-3, PS-5).
class RoomLayout extends StatelessWidget {
  const new({
    required this.presentation,
    required this.video,
    required this.info,
    required this.chat,
    this.chatOpen = true,
    this.chatWidth = Sizes.chatWidth,
    this.onChatWidth,
    this.portraitPanel = false,
    this.onPortraitFullscreen,
    this.onForceLandscape,
    super.key,
  });

  final RoomPresentation presentation;

  /// The single video surface with its controls.
  final Widget video;

  /// Streamer, title and actions.
  final Widget info;

  /// Chat list with pinned super chats.
  final Widget chat;

  /// Whether the chat panel is open (wide, theater and fullscreen).
  final bool chatOpen;

  /// Chat panel width on large windows (280–480).
  final double chatWidth;

  /// Resizes the chat panel by dragging its edge; null keeps it fixed.
  final ValueChanged<double>? onChatWidth;

  /// Compact width with a portrait source: the three-state panel (PS-4).
  final bool portraitPanel;

  /// The panel was pulled below its lowest height or its handle tapped.
  final VoidCallback? onPortraitFullscreen;

  /// The "横屏全屏" button of the portrait layout.
  final VoidCallback? onForceLandscape;

  @override
  Widget build(BuildContext context) => WindowLayoutBuilder(
    builder: (context, layout) {
      final wide = layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
      if (presentation.isFullscreen || layout.isShortLandscape) return _fullscreen(context, wide: wide);
      if (!wide) {
        final tabs = _Tabs(chat: chat, info: info);
        if (portraitPanel) {
          return PortraitPanelLayout(
            video: video,
            panel: tabs,
            onEnterFullscreen: onPortraitFullscreen,
            onForceLandscape: onForceLandscape,
          );
        }
        return Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: video),
            Expanded(child: tabs),
          ],
        );
      }
      final large = layout.width.atLeast(WidthClass.large);
      final width = large ? chatWidth.clamp(minChatWidth, maxChatWidth) : 320.0;
      // The video stays put above the scrolling info, so a swipe on the
      // picture is a volume or brightness gesture, never a page scroll.
      final main = presentation == RoomPresentation.theater
          ? ColoredBox(color: Colors.black, child: video)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: video),
                Expanded(child: SingleChildScrollView(child: info)),
              ],
            );
      return Row(
        children: [
          Expanded(child: main),
          if (chatOpen) ...[
            _ChatEdge(width: width, onWidth: large ? onChatWidth : null),
            SizedBox(width: width, child: chat),
          ],
        ],
      );
    },
  );

  /// Fullscreen: the chat squeezes the video from expanded width, and floats
  /// over the right 40% on landscape phones (70% black, principles §5.2).
  Widget _fullscreen(BuildContext context, {required bool wide}) {
    final black = ColoredBox(color: Colors.black, child: video);
    if (!chatOpen || presentation == RoomPresentation.portraitFullscreen) return black;
    // The app's dark theme: its colours, interface font and language.
    final overlay = DarkTheme.of(context);
    final panel = Theme(data: overlay, child: chat);
    if (wide) {
      return Row(
        children: [
          Expanded(child: black),
          SizedBox(
            width: chatWidth.clamp(minChatWidth, maxChatWidth),
            child: ColoredBox(color: overlay.colorScheme.surface, child: panel),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.4;
        final media = MediaQuery.of(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            // The picture's bars keep to the left 60%, as if the chat were
            // an edge of the screen: none of their buttons (the chat toggle
            // among them) lies under it.
            MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(right: math.max(media.padding.right, width))),
              child: black,
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: width,
              child: ColoredBox(
                color: const Color(0xB3000000),
                child: SafeArea(left: false, child: panel),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const new({required this.chat, required this.info});

  final Widget chat;
  final Widget info;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          tabs: [
            Tab(text: t.room.tab.danmaku),
            Tab(text: t.room.tab.room),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              chat,
              SingleChildScrollView(child: info),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The divider before the chat panel; on large windows it drags to resize
/// the panel (D-17).
class _ChatEdge extends StatelessWidget {
  const new({required this.width, this.onWidth});

  final double width;
  final ValueChanged<double>? onWidth;

  @override
  Widget build(BuildContext context) {
    final onWidth = this.onWidth;
    if (onWidth == null) return const VerticalDivider(width: 1);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onWidth((width - details.delta.dx).clamp(minChatWidth, maxChatWidth)),
        child: const SizedBox(width: 8, child: Center(child: VerticalDivider(width: 1))),
      ),
    );
  }
}

/// PS-4: a portrait stream at compact width. The video fills the space
/// above a panel with three heights; dragging snaps to the nearest one,
/// pulling well below the lowest (or tapping the handle) enters portrait
/// fullscreen, and a "横屏全屏" button rides on the panel's top edge.
class PortraitPanelLayout extends StatefulWidget {
  const new({required this.video, required this.panel, this.onEnterFullscreen, this.onForceLandscape, super.key});

  final Widget video;
  final Widget panel;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onForceLandscape;

  @override
  State<PortraitPanelLayout> createState() => PortraitPanelLayoutState();
}

/// State of a [PortraitPanelLayout]; public for tests.
class PortraitPanelLayoutState extends State<PortraitPanelLayout> {
  /// Detent index kept across size changes (PS-5): 0 low, 1 middle, 2 high.
  int detent = 1;
  double? _dragHeight;

  static const double _handle = 24;

  void _end(PortraitPanelMetrics metrics, double velocity) {
    final height = _dragHeight ?? metrics.detents[detent];
    if (metrics.entersFullscreen(height, velocity)) {
      setState(() {
        _dragHeight = null;
        detent = 0;
      });
      widget.onEnterFullscreen?.call();
      return;
    }
    final nearest = metrics.nearest(height);
    setState(() {
      _dragHeight = null;
      detent = metrics.detents.indexOf(nearest);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = PortraitPanelMetrics(constraints.maxHeight);
      final height = _dragHeight ?? metrics.detents[detent.clamp(0, 2)];
      final floor = (metrics.low - metrics.fullscreenPull - 48).clamp(0, metrics.low).toDouble();
      final scheme = Theme.of(context).colorScheme;
      return Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: (constraints.maxHeight - height).clamp(0, constraints.maxHeight).toDouble(),
            child: ColoredBox(color: Colors.black, child: widget.video),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: Material(
              color: scheme.surface,
              child: Column(
                children: [
                  GestureDetector(
                    key: const ValueKey('portrait-handle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onEnterFullscreen,
                    onVerticalDragUpdate: (details) => setState(() {
                      _dragHeight = ((_dragHeight ?? height) - details.delta.dy).clamp(floor, metrics.high);
                    }),
                    onVerticalDragEnd: (details) => _end(metrics, details.primaryVelocity ?? 0),
                    child: SizedBox(
                      height: _handle,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(Radii.full),
                          ),
                          child: const SizedBox(width: 32, height: 4),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, inner) => inner.maxHeight >= 240
                          ? widget.panel
                          : SingleChildScrollView(child: SizedBox(height: 240, child: widget.panel)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onForceLandscape != null)
            Positioned(
              right: Space.s3,
              bottom: height + Space.s3,
              child: FilledButton.tonalIcon(
                onPressed: widget.onForceLandscape,
                icon: const LiveIcon(LiveIcons.rotate),
                label: Text(t.room.forceLandscape),
              ),
            ),
        ],
      );
    },
  );
}
