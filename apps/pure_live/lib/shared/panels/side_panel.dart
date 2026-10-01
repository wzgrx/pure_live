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

class _RoomSidePanelState extends State<RoomSidePanel> {
  double _drag = 0;

  void _dragged(DragUpdateDetails details) {
    setState(() => _drag = (_drag + details.delta.dy).clamp(0, 400));
  }

  void _released(DragEndDetails details) {
    if (_drag > 72 || (details.primaryVelocity ?? 0) > 600) {
      widget.onClose();
    } else {
      setState(() => _drag = 0);
    }
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
    return Transform.translate(
      offset: Offset(0, _drag),
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
