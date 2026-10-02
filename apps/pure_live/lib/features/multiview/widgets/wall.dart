import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/logic/multiview_geometry.dart';
import 'package:pure_live/features/multiview/widgets/cell_view.dart';

/// Builds cell [index]; [nameInset] moves its corner marks right.
typedef CellBuilder = Widget Function(int index, {required bool large, required double nameInset});

/// The black picture area with the cells at [WallGeometry]'s places
/// (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c2, c3, c12): 16:9 cells, centred. In the 1+3 layout
/// the small cells sit in a rail that scrolls past three; the cells
/// scrolled out of sight are reported ([onOffscreen]) so they stop decoding
/// (UI_PLAN §9.3). Cells keep their [GlobalKey]s from [cellBuilder], so a
/// cell moving between the large place and the rail keeps its player.
class MultiviewWall extends StatefulWidget {
  /// Creates the wall.
  const new({
    required this.layout,
    required this.count,
    required this.focused,
    required this.cellBuilder,
    required this.onOffscreen,
    this.onAddCell,
    this.gap = 3,
    this.padding = 3,
    this.avoid,
    super.key,
  });

  /// The layout.
  final MultiviewLayout layout;

  /// How many cells there are.
  final int count;

  /// The large cell of the 1+3 layout.
  final int focused;

  /// Builds a cell.
  final CellBuilder cellBuilder;

  /// Receives the cells (by index) out of sight in the rail.
  final ValueChanged<Set<int>> onOffscreen;

  /// The "添加画面" slot at the rail's end (desktops, 1+3); null hides it.
  final VoidCallback? onAddCell;

  /// Between cells.
  final double gap;

  /// Around the cells.
  final double padding;

  /// A button over the wall (its top-left exit) the cells' marks keep clear
  /// of, in the wall's coordinates.
  final Rect? avoid;

  @override
  State<MultiviewWall> createState() => _MultiviewWallState();
}

class _MultiviewWallState extends State<MultiviewWall> {
  final ScrollController _rail = ScrollController();
  List<int> _railCells = const [];
  double _railExtent = 0;
  Set<int> _reported = const {};
  bool _checkScheduled = false;

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _check();
    });
  }

  void _check() {
    var offscreen = <int>{};
    if (_railCells.isNotEmpty && _rail.hasClients && _rail.position.hasContentDimensions) {
      final position = _rail.position;
      final (first, end) = visibleRailRange(
        count: _railCells.length,
        offset: position.pixels,
        viewport: position.viewportDimension,
        extent: _railExtent,
      );
      offscreen = {
        for (var i = 0; i < _railCells.length; i++)
          if (i < first || i >= end) _railCells[i],
      };
    }
    if (offscreen.length == _reported.length && offscreen.containsAll(_reported)) return;
    _reported = offscreen;
    widget.onOffscreen(offscreen);
  }

  double _inset(Rect rect) {
    final avoid = widget.avoid;
    if (avoid == null || !avoid.overlaps(rect)) return 0;
    return (avoid.right - rect.left - 2).clamp(0, rect.width / 2);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: OnVideoColors.ground,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final geometry = WallGeometry.of(
          widget.layout,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          gap: widget.gap,
          padding: widget.padding,
        );
        final count = widget.count;
        final children = <Widget>[];
        final rail = geometry.rail;
        if (rail == null) {
          _railCells = const [];
          for (var i = 0; i < count && i < geometry.cells.length; i++) {
            final rect = geometry.cells[i];
            children.add(
              Positioned.fromRect(
                rect: rect,
                child: widget.cellBuilder(i, large: false, nameInset: _inset(rect)),
              ),
            );
          }
        } else {
          final large = widget.focused.clamp(0, count - 1);
          final rect = geometry.cells.first;
          children.add(
            Positioned.fromRect(
              rect: rect,
              child: widget.cellBuilder(large, large: true, nameInset: _inset(rect)),
            ),
          );
          _railCells = [
            for (var i = 0; i < count; i++)
              if (i != large) i,
          ];
          _railExtent = geometry.railExtent;
          final vertical = geometry.railVertical;
          final side = geometry.railExtent - widget.gap;
          Widget sized(Widget child) =>
              SizedBox(width: vertical ? rail.width : side, height: vertical ? side : rail.height, child: child);
          children.add(
            Positioned.fromRect(
              rect: rail,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  _scheduleCheck();
                  return false;
                },
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: (_) {
                    _scheduleCheck();
                    return false;
                  },
                  child: SingleChildScrollView(
                    key: const ValueKey('multiview-rail'),
                    controller: _rail,
                    scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
                    child: Flex(
                      direction: vertical ? Axis.vertical : Axis.horizontal,
                      spacing: widget.gap,
                      children: [
                        for (final index in _railCells) sized(widget.cellBuilder(index, large: false, nameInset: 0)),
                        if (widget.onAddCell case final add?) sized(AddCellSlot(onTap: add)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        _scheduleCheck();
        return Stack(children: children);
      },
    ),
  );
}
