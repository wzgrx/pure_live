import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:live_ui/src/metrics.dart';

/// A header above scrolling content that slides away while the user scrolls
/// down and comes back when they scroll up or reach the top: the top bar of
/// landscape phones (spec/design/principles.md §5.2, 顶栏随滚动收起).
///
/// Only vertical scrolling counts; horizontal paging (tab views) leaves the
/// header as it is.
class ScrollAwayHeader extends StatefulWidget {
  /// Creates the header.
  const new({required this.header, required this.body, super.key});

  /// The header.
  final Widget header;

  /// The scrolling content.
  final Widget body;

  @override
  State<ScrollAwayHeader> createState() => ScrollAwayHeaderState();
}

/// State of a [ScrollAwayHeader]; public for tests.
class ScrollAwayHeaderState extends State<ScrollAwayHeader> {
  bool _shown = true;

  /// Whether the header shows.
  bool get shown => _shown;

  void _show(bool value) {
    if (value != _shown) setState(() => _shown = value);
  }

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is UserScrollNotification) {
      // Content that does not scroll keeps its header.
      final scrolls = metrics.maxScrollExtent > metrics.minScrollExtent;
      if (notification.direction == ScrollDirection.reverse && scrolls) _show(false);
      if (notification.direction == ScrollDirection.forward) _show(true);
    } else if (notification is ScrollUpdateNotification && metrics.pixels <= metrics.minScrollExtent) {
      _show(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRect(
          child: AnimatedAlign(
            duration: still ? Duration.zero : Motion.medium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            heightFactor: _shown ? 1 : 0,
            child: widget.header,
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
        ),
      ],
    );
  }
}
