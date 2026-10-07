import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The width of the fade at the end of a scrolling tab strip
/// (docs/A-界面设计/A09-浏览界面/A09.12-浏览界面真机对照修正 c1).
const double tabStripEndFade = 24;

/// A [TabBar] that desktop users can also scroll with the mouse wheel and by
/// dragging with the mouse (from liuchuancong/pure_live). Touch behaviour and
/// the given scroll physics are unchanged. With [endFade] a scrolling strip
/// fades out over its last [endFade] points while more tabs lie beyond, so
/// a tab cut by the edge (or by a button after the strip) fades instead of
/// stopping hard.
class ScrollableTabBar extends StatefulWidget {
  /// Creates the tab bar.
  const new({
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.indicatorColor,
    this.dividerColor,
    this.indicatorWeight = 2.0,
    this.indicatorSize,
    this.indicator,
    this.indicatorPadding = EdgeInsets.zero,
    this.labelColor,
    this.unselectedLabelColor,
    this.labelStyle,
    this.unselectedLabelStyle,
    this.labelPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.dividerHeight,
    this.tabAlignment,
    this.physics,
    this.onTap,
    this.onHover,
    this.onFocusChange,
    this.overlayColor,
    this.mouseCursor,
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableFeedback = true,
    this.splashBorderRadius,
    this.splashFactory,
    this.enableMouseWheel = true,
    this.mouseWheelScrollFactor = 1.0,
    this.mouseWheelDuration = const Duration(milliseconds: 100),
    this.mouseWheelCurve = Curves.easeOut,
    this.endFade = 0,
    super.key,
  });

  /// Passed to [TabBar.tabs].
  final List<Widget> tabs;

  /// Passed to [TabBar.controller].
  final TabController? controller;

  /// Passed to [TabBar.isScrollable].
  final bool isScrollable;

  /// Passed to [TabBar.padding].
  final EdgeInsetsGeometry? padding;

  /// Passed to [TabBar.indicatorColor].
  final Color? indicatorColor;

  /// Passed to [TabBar.dividerColor].
  final Color? dividerColor;

  /// Passed to [TabBar.indicatorWeight].
  final double indicatorWeight;

  /// Passed to [TabBar.indicatorSize].
  final TabBarIndicatorSize? indicatorSize;

  /// Passed to [TabBar.indicator].
  final Decoration? indicator;

  /// Passed to [TabBar.indicatorPadding].
  final EdgeInsetsGeometry indicatorPadding;

  /// Passed to [TabBar.labelColor].
  final Color? labelColor;

  /// Passed to [TabBar.unselectedLabelColor].
  final Color? unselectedLabelColor;

  /// Passed to [TabBar.labelStyle].
  final TextStyle? labelStyle;

  /// Passed to [TabBar.unselectedLabelStyle].
  final TextStyle? unselectedLabelStyle;

  /// Passed to [TabBar.labelPadding].
  final EdgeInsetsGeometry labelPadding;

  /// Passed to [TabBar.dividerHeight].
  final double? dividerHeight;

  /// Passed to [TabBar.tabAlignment].
  final TabAlignment? tabAlignment;

  /// Passed to [TabBar.physics].
  final ScrollPhysics? physics;

  /// Passed to [TabBar.onTap].
  final void Function(int)? onTap;

  /// Passed to [TabBar.onHover].
  final TabValueChanged<bool>? onHover;

  /// Passed to [TabBar.onFocusChange].
  final TabValueChanged<bool>? onFocusChange;

  /// Passed to [TabBar.overlayColor].
  final WidgetStateProperty<Color?>? overlayColor;

  /// Passed to [TabBar.mouseCursor].
  final MouseCursor? mouseCursor;

  /// Passed to [TabBar.dragStartBehavior].
  final DragStartBehavior dragStartBehavior;

  /// Passed to [TabBar.enableFeedback].
  final bool enableFeedback;

  /// Passed to [TabBar.splashBorderRadius].
  final BorderRadius? splashBorderRadius;

  /// Passed to [TabBar.splashFactory].
  final InteractiveInkFeatureFactory? splashFactory;

  /// Scrolls the strip with the mouse wheel.
  final bool enableMouseWheel;

  /// Pixels scrolled per pixel of wheel delta.
  final double mouseWheelScrollFactor;

  /// Duration of a wheel scroll.
  final Duration mouseWheelDuration;

  /// Curve of a wheel scroll.
  final Curve mouseWheelCurve;

  /// The width of the fade at the strip's end while more tabs lie beyond
  /// it ([tabStripEndFade]); 0 for none.
  final double endFade;

  @override
  State<ScrollableTabBar> createState() => ScrollableTabBarState();
}

/// The state of a [ScrollableTabBar].
class ScrollableTabBarState extends State<ScrollableTabBar> {
  bool _moreAfter = false;

  /// Whether the strip's end fades now: [ScrollableTabBar.endFade] is set
  /// and tabs lie beyond the end.
  bool get fadesEnd => widget.endFade > 0 && _moreAfter;

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.horizontal || !metrics.hasContentDimensions) return false;
    final moreAfter = metrics.extentAfter > 0.5;
    if (moreAfter != _moreAfter) setState(() => _moreAfter = moreAfter);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var strip = _tabBar();
    if (widget.endFade > 0) {
      // The mask stays in the tree when nothing lies beyond (then it is
      // opaque), so the strip keeps its state and scroll position.
      final fade = widget.endFade;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final moreAfter = _moreAfter;
      strip = NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) => _onMetrics(notification.metrics, notification.depth),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) => _onMetrics(notification.metrics, notification.depth),
          child: ShaderMask(
            key: const ValueKey('tab-strip-fade'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final width = bounds.width <= 0 ? 1.0 : bounds.width;
              return LinearGradient(
                begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
                end: rtl ? Alignment.centerLeft : Alignment.centerRight,
                colors: [const Color(0xFFFFFFFF), Color(moreAfter ? 0x00FFFFFF : 0xFFFFFFFF)],
                stops: [if (moreAfter) ((width - fade) / width).clamp(0.0, 1.0) else 1.0, 1.0],
              ).createShader(bounds);
            },
            child: strip,
          ),
        ),
      );
    }
    return Listener(onPointerSignal: widget.enableMouseWheel ? _handlePointerSignal : null, child: strip);
  }

  Widget _tabBar() {
    return ScrollConfiguration(
      behavior: const _CrossPlatformTabBarScrollBehavior(),
      child: TabBar(
        controller: widget.controller,
        tabs: widget.tabs,
        isScrollable: widget.isScrollable,
        padding: widget.padding,
        indicatorColor: widget.indicatorColor,
        dividerColor: widget.dividerColor,
        indicatorWeight: widget.indicatorWeight,
        indicatorSize: widget.indicatorSize,
        indicator: widget.indicator,
        indicatorPadding: widget.indicatorPadding,
        labelColor: widget.labelColor,
        unselectedLabelColor: widget.unselectedLabelColor,
        labelStyle: widget.labelStyle,
        unselectedLabelStyle: widget.unselectedLabelStyle,
        labelPadding: widget.labelPadding,
        dividerHeight: widget.dividerHeight,
        tabAlignment: widget.tabAlignment,
        physics: widget.physics,
        onTap: widget.onTap,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        overlayColor: widget.overlayColor,
        mouseCursor: widget.mouseCursor,
        dragStartBehavior: widget.dragStartBehavior,
        enableFeedback: widget.enableFeedback,
        splashBorderRadius: widget.splashBorderRadius,
        splashFactory: widget.splashFactory,
      ),
    );
  }

  /// The tab strip's own horizontal scroll position, looked up on demand so
  /// the very first wheel turn works (upstream waited for a scroll notification).
  ScrollPosition? _tabPosition() {
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.axis == Axis.horizontal) {
          found = position;
          return;
        }
      }
      element.visitChildren(visit);
    }

    if (mounted) (context as Element).visitChildren(visit);
    return found;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final position = _tabPosition();
    if (position == null || !position.hasContentDimensions || position.maxScrollExtent <= 0) return;
    var delta = event.scrollDelta.dx;
    if (delta.abs() < 0.01) delta = event.scrollDelta.dy;
    if (delta.abs() < 0.01) return;
    // Claim the event so the page behind the tabs does not scroll as well.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final target = (position.pixels + delta * widget.mouseWheelScrollFactor).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 0.01) return;
      position.animateTo(target, duration: widget.mouseWheelDuration, curve: widget.mouseWheelCurve);
    });
  }
}

class _CrossPlatformTabBarScrollBehavior extends MaterialScrollBehavior {
  const new();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}
