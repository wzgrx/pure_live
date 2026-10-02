import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

export 'package:pure_live/shared/danmaku/setting_rows.dart' show PanelCard, PanelGroupTitle;

// The panel the live room opens beside the picture (docs/ui/compare/U.2f,
// 统一规则); the multi-view page (docs/ui/compare/U.8) opens the same one.

/// The width of a panel on the right (landscape, tablets, desktops).
const double roomSidePanelWidth = 360;

/// A panel of the room (U.2f): the same look in every layout, only its place
/// changes; under the picture in portrait (rising from its lower edge, all
/// the height below it), on the right in landscape and on wide screens
/// ([roomSidePanelWidth] wide, the full height, over the chat column). The
/// picture keeps playing and is not dimmed. The header has the [title],
/// [actions] and ✕; in portrait a downward drag on the header closes it too
/// ([dragToClose]); Back closes it before anything else (the page).
class RoomSidePanel extends StatefulWidget {
  /// Creates the panel.
  const new({
    required this.title,
    required this.onClose,
    required this.child,
    this.actions = const [],
    this.dragToClose = false,
    this.leading,
    this.borderRadius,
    super.key,
  });

  /// The panel's name.
  final String title;

  /// Closes the panel.
  final VoidCallback onClose;

  /// The content (a scrolling list).
  final Widget child;

  /// Between the title and ✕ ("录制中心 ›", "改动立即生效").
  final List<Widget> actions;

  /// A downward drag on the header closes the panel (portrait).
  final bool dragToClose;

  /// Before the title: the back of a panel's second page (U.2k K3).
  final Widget? leading;

  /// Rounded corners where the panel floats over the picture (the
  /// multi-view's immersive and fullscreen modes); square by default.
  final BorderRadius? borderRadius;

  @override
  State<RoomSidePanel> createState() => _RoomSidePanelState();
}

class _RoomSidePanelState extends State<RoomSidePanel> with SingleTickerProviderStateMixin {
  /// Pulled further than this, letting go closes the panel.
  static const double _closeDistance = 72;

  /// How far the header has pulled the panel down from its place.
  late final AnimationController _pull = AnimationController.unbounded(vsync: this);
  bool _closing = false;

  @override
  void didUpdateWidget(RoomSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.dragToClose && !_closing && _pull.value != 0) _pull.value = 0;
  }

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  /// How far down the panel is out of sight.
  double get _height => math.max(0, context.size?.height ?? 0);

  void _started(DragStartDetails details) {
    // Catches a panel springing back.
    if (!_closing) _pull.stop();
  }

  void _dragged(DragUpdateDetails details) {
    if (_closing) return;
    // With the finger, down to out of sight; never above its place.
    _pull.value = (_pull.value + details.delta.dy).clamp(0, _height);
  }

  /// A spring takes the panel on from the finger at its speed (research
  /// 2026-10-02 S2): out of sight and closed, or back to its place. A fling
  /// decides which (down closes, up keeps it), otherwise how far it was
  /// pulled, as Android's and Flutter's bottom sheets do.
  void _released(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.primaryVelocity ?? 0;
    final close = velocity.abs() >= AppMotion.panelFlingVelocity ? velocity > 0 : _pull.value > _closeDistance;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pull.value = 0;
      if (close) _close();
      return;
    }
    final height = _height;
    final run = _pull.animateRelease(
      ReleaseSpringSimulation(
        spring: AppMotion.panelSpring,
        start: _pull.value,
        end: close ? height : 0,
        velocity: velocity,
        // Out of sight is the end: no slow tail at the edge.
        beyond: close ? height * 0.01 : 0,
        tolerance: AppMotion.tolerance(MediaQuery.devicePixelRatioOf(context)),
      ),
      refreshRate: View.of(context).display.refreshRate,
    );
    if (!close) return;
    _closing = true;
    run.whenCompleteOrCancel(() {
      if (mounted) _close();
    });
  }

  void _close() {
    _closing = true;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(widget.leading == null ? 16 : 4, 4, 4, 0),
      child: SizedBox(
        height: kMinInteractiveDimension + 4,
        child: Row(
          children: [
            ?widget.leading,
            Expanded(
              child: Text(
                widget.title,
                key: const ValueKey('room-panel-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.emphasis.copyWith(color: scheme.onSurface),
              ),
            ),
            ...widget.actions,
            IconButton(
              key: const ValueKey('room-panel-close'),
              tooltip: i18n('close'),
              onPressed: widget.onClose,
              icon: const Icon(AppIcons.close),
            ),
          ],
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _pull,
      builder: (context, panel) => Transform.translate(offset: Offset(0, math.max(0, _pull.value)), child: panel),
      child: Material(
        key: const ValueKey('room-panel'),
        color: scheme.surface,
        elevation: 2,
        borderRadius: widget.borderRadius,
        child: SafeArea(
          top: false,
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.dragToClose)
                GestureDetector(
                  key: const ValueKey('room-panel-drag'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: _started,
                  onVerticalDragUpdate: _dragged,
                  onVerticalDragEnd: _released,
                  child: header,
                )
              else
                header,
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text link in a panel header or footer: "录制中心 ›".
class PanelLink extends StatelessWidget {
  /// Creates the link.
  const new({required this.text, required this.onPressed, super.key});

  /// The words.
  final String text;

  /// Follows the link.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          Icon(AppIcons.forward, size: 18, color: scheme.primary),
        ],
      ),
    );
  }
}
