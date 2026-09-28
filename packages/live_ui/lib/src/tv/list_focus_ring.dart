import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:live_ui/src/theme.dart';
import 'package:live_ui/src/tv/focus_frame.dart';
import 'package:live_ui/src/tv/tv_scope.dart';

/// The focus ring of list rows in TV mode (principles §5.3): whichever
/// [ListTile] holds the remote's focus (a plain row, a switch, radio or
/// checkbox row, an expansion header, a slider inside a row) gets the same
/// 3 dp ring as a [FocusFrame], drawn inside its bounds; so do menu items,
/// tabs and the segments of a segmented button, the other controls the
/// theme only fills. The theme's focus fill alone reads at under 2:1 from
/// the sofa.
///
/// One layer over the whole app draws it, so every list row has it without
/// wrapping each one; rows that already are a [FocusFrame] (their tile does
/// not take focus) and controls with rings of their own (buttons, fields,
/// chips) inside a row are left alone. The ring is clipped to the row's
/// scrolling viewport and follows scrolling in the same frame; other moves
/// (page transitions) catch up a frame later.
class TvListFocusRings extends StatefulWidget {
  /// Draws the rings over [child].
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  State<TvListFocusRings> createState() => _TvListFocusRingsState();
}

class _TvListFocusRingsState extends State<TvListFocusRings> {
  final _Ring _ring = _Ring();

  /// The focused row, when a row has focus.
  Element? _row;
  Rect? _painted;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _ring.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) => _ring.changed();

  void _onFocus() {
    if (!mounted) return;
    final row = _rowOf(FocusManager.instance.primaryFocus);
    if (row == _row) return;
    _row = row;
    _ring.changed();
    if (row != null) _watch();
  }

  /// After every frame the app draws anyway, a row that moved without a
  /// scroll (a page transition) gets its ring moved; no frames of its own.
  void _watch() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watching = false;
      if (!mounted || _row == null) return;
      final rect = _rowRect();
      if (rect != _painted) _ring.changed();
      _watch();
    });
  }

  /// Walks up from [node] to the [ListTile] or menu item it belongs to, or
  /// the tab it is; none when a control with its own ring comes first, or
  /// the node is not in a row.
  static Element? _rowOf(FocusNode? node) {
    final context = node?.context;
    if (context is! Element || !context.mounted) return null;
    Element? row;
    var depth = 0;
    context.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is ListTile || widget is PopupMenuItem) {
        row = ancestor;
        return false;
      }
      if (widget is TabBar) {
        // A tab's focus is its own ink well.
        row = context;
        return false;
      }
      if (widget is ButtonStyleButton) {
        // A segment of a segmented button: the theme only fills it.
        if (_inSegmentedButton(ancestor)) row = ancestor;
        return false;
      }
      // Controls that show focus themselves, and the ends of a row's reach.
      if (widget is IconButton ||
          widget is PopupMenuButton ||
          widget is TextField ||
          widget is RawChip ||
          widget is SearchBar ||
          widget is FocusFrame ||
          widget is Scrollable ||
          widget is ModalBarrier ||
          widget is Navigator) {
        return false;
      }
      return ++depth < 40;
    });
    return row;
  }

  static bool _inSegmentedButton(Element element) {
    var found = false;
    var depth = 0;
    element.visitAncestorElements((ancestor) {
      found = ancestor.widget is SegmentedButton;
      // The segmented button's own Material sits in between.
      return !found && ++depth < 24;
    });
    return found;
  }

  /// The focused row's rect and its viewport's, in this layer's coordinates.
  (Rect, Rect?)? _geometry() {
    final row = _row;
    final layer = context.findRenderObject();
    if (row == null || !row.mounted || layer is! RenderBox || !layer.attached) return null;
    final box = row.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = MatrixUtils.transformRect(box.getTransformTo(layer), Offset.zero & box.size);
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    Rect? clip;
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      clip = MatrixUtils.transformRect(viewport.getTransformTo(layer), Offset.zero & viewport.size);
    }
    return (rect, clip);
  }

  Rect? _rowRect() => _geometry()?.$1;

  void _paint(Canvas canvas, Color color) {
    final geometry = _geometry();
    _painted = geometry?.$1;
    if (geometry == null || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    final (rect, clip) = geometry;
    final visible = clip == null ? rect : rect.intersect(clip);
    if (visible.isEmpty || visible.width <= 0 || visible.height <= 0) return;
    canvas
      ..save()
      ..clipRect(visible)
      ..drawRect(
        rect.deflate(TvMetrics.focusRing / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = TvMetrics.focusRing
          ..color = color,
      )
      ..restore();
  }

  bool _onNotification(Notification notification) {
    if (_row != null && (notification is ScrollNotification || notification is ScrollMetricsNotification)) {
      _ring.changed();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.extension<LiveTheme>()?.focusRing ?? theme.colorScheme.onSurface;
    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: CustomPaint(
        foregroundPainter: _RingPainter(this, color),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

/// Repaints the ring layer.
final class _Ring extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _RingPainter extends CustomPainter {
  new(this.state, this.color) : super(repaint: state._ring);

  final _TvListFocusRingsState state;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => state._paint(canvas, color);

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.color != color || oldDelegate.state != state;

  @override
  bool? hitTest(Offset position) => false;
}
