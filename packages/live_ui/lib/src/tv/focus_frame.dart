import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/theme.dart';
import 'package:live_ui/src/tv/tv_scope.dart';

/// Keyboard and remote focus of one actionable surface (spec/design/
/// principles.md §5.3, §5.4).
///
/// While it has keyboard focus the surface shows a 3 dp ring in
/// [LiveTheme.focusRing] (never after a touch or click). In TV mode it also
/// grows 1.05× and lifts one elevation level, unless [grow] is off (video
/// cells), performance mode is on or animations are disabled: then the ring
/// alone shows.
///
/// OK (the D-pad centre, Enter) calls [onActivate] on release; holding it
/// for [TvMetrics.longPress], or the menu key, calls [onMenu]. Other keys go
/// to [onKeyEvent] first (grid moves), then up the tree.
class FocusFrame extends StatefulWidget {
  /// Creates the frame.
  const new({
    required this.child,
    this.onActivate,
    this.onMenu,
    this.onKeyEvent,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.radius = Radii.r2,
    this.grow = true,
    this.ringInside = false,
    this.debugLabel,
    super.key,
  });

  /// The surface. Its own buttons should not take focus
  /// (`InkWell(canRequestFocus: false)`): the frame is the focus target.
  final Widget child;

  /// OK, Space or a tap-equivalent activation.
  final VoidCallback? onActivate;

  /// Long OK or the menu key: the card menu.
  final VoidCallback? onMenu;

  /// Keys other than OK and menu, before they bubble up (grid moves).
  final FocusOnKeyEventCallback? onKeyEvent;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  /// An external node (grids keep one per card to restore focus).
  final FocusNode? focusNode;

  /// Take focus when first shown.
  final bool autofocus;

  /// Corner radius of the ring.
  final double radius;

  /// Whether the surface may grow and lift in TV mode.
  final bool grow;

  /// Draw the ring inside the bounds (edge-to-edge surfaces such as video
  /// cells) instead of around them.
  final bool ringInside;

  /// Label of the frame's own node.
  final String? debugLabel;

  @override
  State<FocusFrame> createState() => _FocusFrameState();
}

class _FocusFrameState extends State<FocusFrame> {
  FocusNode? _own;
  bool _focused = false;
  late final OkPressTracker _ok = OkPressTracker(
    onPress: () => widget.onActivate?.call(),
    onLongPress: () => widget.onMenu,
  );

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: widget.debugLabel));

  /// The M3 level-1 shadow (principles §2.4: only lifted elements cast one).
  static const List<BoxShadow> _lift = [
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x26000000), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 1),
  ];

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _ok.dispose();
    _own?.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) {
    if (mounted && _focused) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final actionable = widget.onActivate != null || widget.onMenu != null;
    if (actionable && event.logicalKey == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) widget.onMenu?.call();
      return widget.onMenu == null ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (actionable && _ok.handle(event)) return KeyEventResult.handled;
    return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _onFocus(bool focused) {
    if (!focused) _ok.reset();
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tv = TvScope.of(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final visible = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final grow = visible && tv.enabled && tv.focusGrowth && widget.grow && !still;
    final ring = theme.extension<LiveTheme>()?.focusRing ?? theme.colorScheme.onSurface;
    final radius = BorderRadius.circular(widget.radius);
    Widget child = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: visible
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: ring,
                width: TvMetrics.focusRing,
                strokeAlign: widget.ringInside ? BorderSide.strokeAlignInside : BorderSide.strokeAlignOutside,
              ),
            )
          : const BoxDecoration(),
      child: widget.child,
    );
    if (grow) {
      child = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: _lift),
        child: child,
      );
    }
    if (tv.enabled && widget.grow) {
      child = AnimatedScale(
        scale: grow ? TvMetrics.focusScale : 1,
        duration: still ? Duration.zero : Motion.short,
        curve: Curves.easeOut,
        child: child,
      );
    }
    return Actions(
      actions: {
        if (widget.onActivate != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate!();
              return null;
            },
          ),
      },
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: _onFocus,
        child: child,
      ),
    );
  }
}
