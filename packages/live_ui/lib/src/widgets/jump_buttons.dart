import 'package:flutter/material.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';

/// How far a list scrolls before "to top" shows (3.x `BasePageView`: 400).
const double jumpButtonsThreshold = 400;

/// "To top" and "to bottom" over a list once it scrolls (3.x
/// `BasePageView`'s mini buttons, docs/A-界面设计/A02-组件/A02.1-通用组件 c20): neither
/// before the list first moves (3.x updated them only on a scroll;
/// docs/A-界面设计/A09-浏览界面/A09.12-浏览界面真机对照修正 c2), then "to top" past
/// [jumpButtonsThreshold], "to bottom" while more than that remains. Each
/// looks 40 round on `surfaceContainerHighest` with a floating shadow and
/// takes taps on 48 (3.x's 40 was too small); hover, press and the keyboard
/// focus frame on computers.
class ScrollJumpButtons extends StatefulWidget {
  /// Creates the buttons for [controller].
  const new({
    required this.controller,
    required this.heroTag,
    required this.topTooltip,
    required this.bottomTooltip,
    super.key,
  });

  /// The list's position.
  final ScrollController controller;

  /// Unique per page (two lists may be alive at once).
  final String heroTag;

  /// "回到顶部".
  final String topTooltip;

  /// "到底部".
  final String bottomTooltip;

  @override
  State<ScrollJumpButtons> createState() => _ScrollJumpButtonsState();
}

class _ScrollJumpButtonsState extends State<ScrollJumpButtons> {
  bool _top = false;
  bool _bottom = false;

  /// Whether the list has moved since the buttons came: a list that opens
  /// at its top shows no "to bottom" until the user scrolls.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    // A list that comes back already scrolled (a kept offset) counts as
    // scrolled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(ScrollJumpButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _scrolled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _scrolled = true;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final controller = widget.controller;
    if (!controller.hasClients || controller.positions.length != 1) {
      if (_top || _bottom) setState(() => _top = _bottom = false);
      return;
    }
    final position = controller.position;
    if (!_scrolled && position.hasPixels && position.pixels > position.minScrollExtent) _scrolled = true;
    final top = _scrolled && position.pixels > jumpButtonsThreshold;
    final bottom = _scrolled && position.maxScrollExtent - position.pixels > jumpButtonsThreshold;
    if (top != _top || bottom != _bottom) {
      setState(() {
        _top = top;
        _bottom = bottom;
      });
    }
  }

  void _jump({required bool up}) {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final target = up ? 0.0 : controller.position.maxScrollExtent;
    final distance = (target - controller.offset).abs();
    controller.animateTo(
      target,
      duration: Duration(milliseconds: (180 + distance / 8).round().clamp(220, 520)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button({required bool shown, required bool up}) => AnimatedScale(
      scale: shown ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: ExcludeFocus(
        excluding: !shown,
        child: FocusRing(
          borderRadius: BorderRadius.circular(20),
          child: FloatingActionButton.small(
            key: ValueKey(up ? 'jump-top' : 'jump-bottom'),
            heroTag: '${widget.heroTag}-${up ? 'top' : 'bottom'}',
            elevation: 3,
            focusElevation: 3,
            hoverElevation: 4,
            highlightElevation: 3,
            shape: const CircleBorder(),
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurface,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            tooltip: up ? widget.topTooltip : widget.bottomTooltip,
            onPressed: shown ? () => _jump(up: up) : null,
            child: Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(shown: _top, up: true),
        button(shown: _bottom, up: false),
      ],
    );
  }
}
