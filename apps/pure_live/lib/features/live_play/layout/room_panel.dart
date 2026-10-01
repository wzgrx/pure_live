import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

export 'package:pure_live/shared/danmaku/setting_rows.dart' show PanelCard, PanelGroupTitle;

/// The panels the live room opens beside the picture (docs/ui/compare/U.2f,
/// 统一规则): recording and the danmaku settings. One at a time.
enum RoomPanelKind {
  /// The record panel (the bar's record button, the "● 录制中" mark).
  record,

  /// The danmaku settings (the picture's settings button).
  danmaku,

  /// The IPTV programme guide in landscape fullscreen (docs/ui/compare/U.2g
  /// c16: under the picture in portrait, in the right column on wide
  /// windows, here on the right).
  guide,
}

/// The panel open in the room, or null.
final class RoomPanelController extends ValueNotifier<RoomPanelKind?> {
  /// Creates the controller with no panel open.
  new() : super(null);

  /// Opens [kind] (closing another one).
  void open(RoomPanelKind kind) {
    if (value != kind) value = kind;
  }

  /// Closes the panel.
  void close() => value = null;
}

/// Gives the room's widgets (the bar's record button, the picture's
/// buttons) the [RoomPanelController] of the page.
class RoomPanelScope extends InheritedNotifier<RoomPanelController> {
  /// Creates the scope.
  const new({required RoomPanelController super.notifier, required super.child, super.key});

  /// The page's controller, or null outside a live room (a lone button
  /// then shows its panel in a sheet). Does not rebuild [context] when a
  /// panel opens.
  static RoomPanelController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RoomPanelScope>()?.notifier;
}

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
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: SizedBox(
        height: kMinInteractiveDimension + 4,
        child: Row(
          children: [
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
